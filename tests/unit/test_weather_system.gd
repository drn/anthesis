extends GutTest

## Exercises [WeatherSystem]: same-seed determinism over a long simulated run,
## the calm→warning→storm→calm state-machine ordering, storm pulse cadence and
## count (45 pulses per storm), ticks_until_storm bookkeeping, and the
## force_storm debug hook (short 10-tick warning then a full storm).

const WARNING := WeatherSystem.WARNING_TICKS
const STORM := WeatherSystem.STORM_TICKS
const PULSE := WeatherSystem.PULSE_INTERVAL

# Shared mutable tick cursor for the transition-collecting closure (lambda capture).
var ws_tick: int = 0
# Tick cursor shared with the cadence-test closure (lambda capture helper).
var _pulse_at: int = 0


func _weather(seed_value: int) -> WeatherSystem:
	var ws := WeatherSystem.new()
	add_child_autofree(ws)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	ws.setup(rng)
	return ws


## Run a fresh system and collect every (tick, new_state) transition.
func _transitions(seed_value: int, total_ticks: int) -> Array:
	var ws := _weather(seed_value)
	var seen: Array = []
	ws.weather_changed.connect(func(state: StringName) -> void: seen.append([ws_tick, state]))
	for t in range(1, total_ticks + 1):
		ws_tick = t
		ws.on_tick(t)
	return seen


func test_starts_calm() -> void:
	var ws := _weather(1)
	assert_eq(ws.state(), &"calm")
	assert_gt(ws.ticks_until_storm(), 0)


func test_setup_does_not_emit() -> void:
	var ws := WeatherSystem.new()
	add_child_autofree(ws)
	watch_signals(ws)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	ws.setup(rng)
	assert_signal_not_emitted(ws, "weather_changed")


func test_same_seed_identical_schedule_over_20k_ticks() -> void:
	var a := _transitions(123456, 20000)
	var b := _transitions(123456, 20000)
	assert_eq(a, b, "same seed → identical transition tick sequence")
	assert_gt(a.size(), 0, "at least one storm cycle occurred in 20k ticks")
	# Sanity: every transition is one of the three states.
	for entry in a:
		assert_true(entry[1] in [&"calm", &"warning", &"storm"])


func test_different_seed_differs() -> void:
	var a := _transitions(111, 20000)
	var b := _transitions(999, 20000)
	# The gap lengths differ, so the transition tick ladder must differ somewhere.
	assert_ne(a, b, "different seeds → different schedules")


func test_state_machine_ordering() -> void:
	var ws := _weather(7)
	ws.force_storm()
	var states: Array = []
	ws.weather_changed.connect(func(s: StringName) -> void: states.append(s))
	# Tick enough to traverse: calm→warning(10)→storm(900)→calm.
	for t in range(1, 10 + STORM + 5):
		ws.on_tick(t)
	assert_eq(states, [&"warning", &"storm", &"calm"])


func test_warning_lasts_exactly_warning_ticks() -> void:
	# Drive a natural cycle: tick out the calm gap, then assert warning length.
	var ws := _weather(31)
	var gap := ws.ticks_until_storm()
	var t := 0
	# Tick through calm; the transition into warning happens on tick gap.
	for _i in range(gap):
		t += 1
		ws.on_tick(t)
	assert_eq(ws.state(), &"warning")
	# Now tick WARNING-1 more and we should still be warning; one more → storm.
	for _i in range(WARNING - 1):
		t += 1
		ws.on_tick(t)
	assert_eq(ws.state(), &"warning")
	t += 1
	ws.on_tick(t)
	assert_eq(ws.state(), &"storm")


func test_pulse_count_is_45_per_storm() -> void:
	var ws := _weather(7)
	ws.force_storm()
	var pulses: Array = []
	ws.storm_pulse.connect(func(idx: int) -> void: pulses.append(idx))
	# Enter warning (10) then full storm (900). Tick a little past.
	for t in range(1, 10 + STORM + 5):
		ws.on_tick(t)
	assert_eq(pulses.size(), STORM / PULSE, "900/20 = 45 pulses")
	# pulse_index increments from 0.
	assert_eq(pulses[0], 0)
	assert_eq(pulses[pulses.size() - 1], (STORM / PULSE) - 1)


func test_pulse_cadence_every_20_ticks() -> void:
	# force_storm: tick 1 enters warning, warning lasts 10 ticks → storm starts on
	# tick 11 (it is the 11th tick that transitions). The first storm tick that
	# elapses is tick 12; the first pulse fires 20 storm-ticks later.
	var ws := _weather(7)
	ws.force_storm()
	var fire_ticks: Array = []
	ws.storm_pulse.connect(func(idx: int) -> void: fire_ticks.append([idx, _pulse_at]))
	for t in range(1, 10 + STORM + 5):
		_pulse_at = t
		ws.on_tick(t)
	# Storm begins when the warning's 11th tick (tick 11) transitions; storm_elapsed
	# counts from the next tick (12). Pulse 0 at 12+19=31, pulse 1 at 51, +20 each.
	assert_eq(fire_ticks[0][0], 0)
	assert_eq(fire_ticks[1][0], 1)
	assert_eq(fire_ticks[1][1] - fire_ticks[0][1], PULSE, "pulses are PULSE ticks apart")


func test_ticks_until_storm_counts_down_and_zeroes_in_storm() -> void:
	var ws := _weather(55)
	var before := ws.ticks_until_storm()
	ws.on_tick(1)
	assert_eq(ws.ticks_until_storm(), before - 1)
	# Force into warning; ticks_until_storm reads 0 outside calm.
	ws.force_storm()
	ws.on_tick(2)  # now warning
	assert_eq(ws.state(), &"warning")
	assert_eq(ws.ticks_until_storm(), 0)


func test_force_storm_uses_short_warning() -> void:
	var ws := _weather(7)
	ws.force_storm()
	# 1 calm tick → warning, then exactly 10 warning ticks → storm.
	ws.on_tick(1)
	assert_eq(ws.state(), &"warning")
	for t in range(2, 2 + 9):
		ws.on_tick(t)
	assert_eq(ws.state(), &"warning", "still warning after 9 of 10 warning ticks")
	ws.on_tick(11)
	assert_eq(ws.state(), &"storm")


func test_storm_returns_to_calm_with_new_gap() -> void:
	var ws := _weather(7)
	ws.force_storm()
	# 1 calm tick → warning, 10 warning ticks → storm, STORM storm ticks → calm.
	for t in range(1, 11 + STORM + 1):
		ws.on_tick(t)
	assert_eq(ws.state(), &"calm")
	assert_gt(ws.ticks_until_storm(), 0, "a fresh gap was rolled on return to calm")
	assert_gte(ws.ticks_until_storm(), WeatherSystem.STORM_MIN_GAP_TICKS - 1)
	assert_lte(ws.ticks_until_storm(), WeatherSystem.STORM_MAX_GAP_TICKS)
