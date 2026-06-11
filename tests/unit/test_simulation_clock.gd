extends GutTest

# Drives SimulationClock by calling _process(delta) directly on a node that is
# NOT in the scene tree, so ticking is fully deterministic and independent of
# the engine's real frame loop.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## A SimulationClock at the given rate, never added to the tree. Freed in teardown.
var _clocks: Array[SimulationClock] = []


func _make(rate := 10.0) -> SimulationClock:
	var clock := SimulationClock.new()
	clock.ticks_per_second = rate
	_clocks.append(clock)
	return clock


func after_each() -> void:
	for clock in _clocks:
		if is_instance_valid(clock):
			clock.free()
	_clocks.clear()


# ---------------------------------------------------------------------------
# Tick counts
# ---------------------------------------------------------------------------


## A fresh clock has emitted nothing; current_tick() reports -1.
func test_initial_tick_is_minus_one() -> void:
	var clock := _make(10.0)
	assert_eq(clock.current_tick(), -1, "No tick emitted yet")


## The very first emitted tick carries index 0.
func test_first_tick_index_is_zero() -> void:
	var clock := _make(10.0)
	watch_signals(clock)
	clock._process(0.1)  # exactly one tick interval at 10 t/s
	assert_signal_emitted_with_parameters(clock, "ticked", [0])
	assert_eq(clock.current_tick(), 0, "First tick is index 0")


## Accumulated time below one interval fires no tick.
func test_subinterval_fires_nothing() -> void:
	var clock := _make(10.0)
	watch_signals(clock)
	clock._process(0.05)  # half a 0.1s interval
	assert_signal_emit_count(clock, "ticked", 0)
	assert_eq(clock.current_tick(), -1)


## Exactly one interval's worth of time fires exactly one tick.
func test_exact_interval_fires_one_tick() -> void:
	var clock := _make(10.0)
	watch_signals(clock)
	clock._process(0.1)
	assert_signal_emit_count(clock, "ticked", 1)


## A long frame fires multiple ticks in a single _process call, in order.
func test_multi_tick_frame() -> void:
	var clock := _make(10.0)
	watch_signals(clock)
	clock._process(0.34)  # 3.4 intervals -> 3 ticks, ~0.04 interval carried
	assert_signal_emit_count(clock, "ticked", 3)
	assert_eq(clock.current_tick(), 2, "Indices 0,1,2 emitted")
	# ~0.04s carried: another 0.07s completes the 4th interval.
	clock._process(0.07)
	assert_signal_emit_count(clock, "ticked", 4)
	assert_eq(clock.current_tick(), 3)


## The accumulator carries remainder across frames so the long-run rate holds.
func test_accumulator_carries_across_frames() -> void:
	var clock := _make(10.0)
	watch_signals(clock)
	clock._process(0.07)  # below one interval -> 0 ticks, 0.07 carried
	assert_signal_emit_count(clock, "ticked", 0)
	clock._process(0.07)  # total 0.14 -> 1 tick, 0.04 carried
	assert_signal_emit_count(clock, "ticked", 1)
	clock._process(0.07)  # total 0.11 -> 1 tick
	assert_signal_emit_count(clock, "ticked", 2)


## A single enormous frame is capped at MAX_TICKS_PER_FRAME ticks.
func test_ten_tick_frame_cap() -> void:
	var clock := _make(10.0)
	watch_signals(clock)
	clock._process(100.0)  # 1000 intervals worth, far over the cap
	assert_signal_emit_count(
		clock, "ticked", SimulationClock.MAX_TICKS_PER_FRAME, "Capped per frame"
	)
	assert_eq(clock.current_tick(), SimulationClock.MAX_TICKS_PER_FRAME - 1)


## Surplus beyond the cap is dropped, not queued into the next frame.
func test_surplus_beyond_cap_is_dropped() -> void:
	var clock := _make(10.0)
	watch_signals(clock)
	clock._process(100.0)  # cap hit, surplus dropped
	# The very next frame should require a full fresh interval to tick again.
	clock._process(0.09)  # below one interval
	assert_signal_emit_count(
		clock, "ticked", SimulationClock.MAX_TICKS_PER_FRAME, "No backlog leaked in"
	)
	clock._process(0.02)  # now total 0.11 past the cap -> one more tick
	assert_signal_emit_count(clock, "ticked", SimulationClock.MAX_TICKS_PER_FRAME + 1)


# ---------------------------------------------------------------------------
# Monotonicity / determinism
# ---------------------------------------------------------------------------


## tick_index increments by exactly 1 per emission, strictly monotonic from 0.
func test_tick_index_monotonic_from_zero() -> void:
	var clock := _make(10.0)
	var seen: Array[int] = []
	clock.ticked.connect(func(i: int) -> void: seen.append(i))
	for _f in range(5):
		clock._process(0.1)  # one tick per frame
	assert_eq(seen, [0, 1, 2, 3, 4], "Exactly +1 per emission from 0")


## The same delta sequence always yields the same tick stream (determinism).
func test_deterministic_for_same_deltas() -> void:
	var deltas := [0.03, 0.12, 0.005, 0.2, 0.077]
	var a: Array[int] = []
	var b: Array[int] = []
	var clock_a := _make(10.0)
	clock_a.ticked.connect(func(i: int) -> void: a.append(i))
	var clock_b := _make(10.0)
	clock_b.ticked.connect(func(i: int) -> void: b.append(i))
	for d in deltas:
		clock_a._process(d)
		clock_b._process(d)
	assert_eq(a, b, "Identical delta streams produce identical tick streams")


# ---------------------------------------------------------------------------
# Pause / resume
# ---------------------------------------------------------------------------


## A fresh clock is not paused.
func test_not_paused_initially() -> void:
	assert_false(_make().is_paused())


## While paused, _process fires no ticks and the index is frozen.
func test_pause_freezes_ticks() -> void:
	var clock := _make(10.0)
	watch_signals(clock)
	clock._process(0.1)  # tick 0
	clock.pause()
	assert_true(clock.is_paused())
	clock._process(1.0)  # would be many ticks if running
	assert_signal_emit_count(clock, "ticked", 1, "No ticks while paused")
	assert_eq(clock.current_tick(), 0, "Index frozen while paused")


## Resuming continues ticking; the index picks up where it left off.
func test_resume_continues() -> void:
	var clock := _make(10.0)
	clock._process(0.1)  # tick 0
	clock.pause()
	clock._process(5.0)  # ignored
	clock.resume()
	assert_false(clock.is_paused())
	clock._process(0.1)  # tick 1
	assert_eq(clock.current_tick(), 1, "Resumes from where it paused")
