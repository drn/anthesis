extends GutTest

# ---------------------------------------------------------------------------
# Constants mirrored from the contract (kept local so the test is an
# independent check on the production values, not a tautology).
# ---------------------------------------------------------------------------

const EXPECTED_HEAT := {
	&"combat_hit": 0.35,
	&"player_hurt": 0.45,
	&"enemy_near": 0.12,
	&"dig": 0.06,
	&"cast": 0.15,
	&"harvest": 0.04,
	&"storm_warning": 0.25,
	&"storm": 0.5,
}
const EXPECTED_DECAY := 0.012
const EPS := 1e-6

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------


## A fresh model starts at exactly 0.0 intensity.
func test_starts_at_zero() -> void:
	var m := IntensityModel.new()
	assert_eq(m.level(), 0.0, "Level must start at 0.0")


## Two independently constructed models both start at zero (no shared state).
func test_two_instances_independent_initial() -> void:
	var a := IntensityModel.new()
	var b := IntensityModel.new()
	a.on_event(&"player_hurt")
	assert_eq(b.level(), 0.0, "A second instance must not share state with the first")


# ---------------------------------------------------------------------------
# Heat values per kind (exact)
# ---------------------------------------------------------------------------


## Each known kind, applied once to a fresh model, yields exactly its heat.
func test_each_kind_exact_heat() -> void:
	for kind: StringName in EXPECTED_HEAT.keys():
		var m := IntensityModel.new()
		m.on_event(kind)
		assert_almost_eq(
			m.level(), float(EXPECTED_HEAT[kind]), EPS, "Heat for %s must be exact" % kind
		)


## The model's published HEAT table matches the contract exactly (keys+values).
func test_heat_table_matches_contract() -> void:
	assert_eq(
		IntensityModel.HEAT.size(), EXPECTED_HEAT.size(), "HEAT must have exactly the contract keys"
	)
	for kind: StringName in EXPECTED_HEAT.keys():
		assert_true(IntensityModel.HEAT.has(kind), "HEAT must contain %s" % kind)
		assert_almost_eq(
			float(IntensityModel.HEAT[kind]),
			float(EXPECTED_HEAT[kind]),
			EPS,
			"HEAT[%s] value must match contract" % kind
		)


## Repeated events accumulate additively (below the clamp ceiling).
func test_events_accumulate_additively() -> void:
	var m := IntensityModel.new()
	m.on_event(&"dig")  # 0.06
	m.on_event(&"dig")  # 0.12
	m.on_event(&"cast")  # 0.27
	assert_almost_eq(m.level(), 0.06 + 0.06 + 0.15, EPS, "Heat must accumulate additively")


# ---------------------------------------------------------------------------
# Unknown kinds
# ---------------------------------------------------------------------------


## An unknown kind is ignored and leaves the level untouched.
func test_unknown_kind_ignored_from_zero() -> void:
	var m := IntensityModel.new()
	m.on_event(&"not_a_real_event")
	assert_eq(m.level(), 0.0, "Unknown kind must not change the level")


## An unknown kind does not disturb an already-raised level.
func test_unknown_kind_ignored_after_raise() -> void:
	var m := IntensityModel.new()
	m.on_event(&"cast")  # 0.15
	m.on_event(&"")  # empty StringName, unknown
	m.on_event(&"combat_miss")  # unknown
	assert_almost_eq(m.level(), 0.15, EPS, "Unknown kinds must leave a raised level unchanged")


# ---------------------------------------------------------------------------
# Clamp at 1.0
# ---------------------------------------------------------------------------


## Heat beyond 1.0 is clamped; the level never exceeds 1.0.
func test_clamps_at_one() -> void:
	var m := IntensityModel.new()
	for _i in range(10):
		m.on_event(&"player_hurt")  # 0.45 each, would reach 4.5 unclamped
	assert_eq(m.level(), 1.0, "Level must clamp at 1.0")


## Clamping is not lossy past the ceiling in a way that hides a single decay:
## once at 1.0, exactly one decay brings it to 1.0 - DECAY (no "overflow credit").
func test_clamp_has_no_overflow_credit() -> void:
	var m := IntensityModel.new()
	for _i in range(10):
		m.on_event(&"player_hurt")
	assert_eq(m.level(), 1.0, "Precondition: saturated at 1.0")
	m.tick()
	assert_almost_eq(
		m.level(),
		1.0 - EXPECTED_DECAY,
		EPS,
		"One tick after saturation must drop by exactly one decay step"
	)


# ---------------------------------------------------------------------------
# Decay per tick (exact)
# ---------------------------------------------------------------------------


## A single tick decays by exactly DECAY_PER_TICK.
func test_single_tick_exact_decay() -> void:
	var m := IntensityModel.new()
	m.on_event(&"player_hurt")  # 0.45
	m.tick()
	assert_almost_eq(m.level(), 0.45 - EXPECTED_DECAY, EPS, "One tick must subtract exactly DECAY")


## N ticks decay by exactly N * DECAY_PER_TICK (while above the floor).
func test_multiple_ticks_linear_decay() -> void:
	var m := IntensityModel.new()
	m.on_event(&"player_hurt")  # 0.45
	var n := 10
	for _i in range(n):
		m.tick()
	assert_almost_eq(
		m.level(), 0.45 - n * EXPECTED_DECAY, EPS, "N ticks must subtract exactly N*DECAY"
	)


## The published DECAY_PER_TICK matches the contract value exactly.
func test_decay_constant_matches_contract() -> void:
	assert_almost_eq(
		IntensityModel.DECAY_PER_TICK, EXPECTED_DECAY, EPS, "DECAY_PER_TICK must match contract"
	)


# ---------------------------------------------------------------------------
# Decay floors at 0
# ---------------------------------------------------------------------------


## Ticking a zero-level model keeps it at 0.0 (never negative).
func test_tick_from_zero_floors_at_zero() -> void:
	var m := IntensityModel.new()
	m.tick()
	m.tick()
	assert_eq(m.level(), 0.0, "Decay must floor at 0.0, never negative")


## Enough ticks to overshoot zero still land exactly on 0.0.
func test_decay_overshoot_floors_at_zero() -> void:
	var m := IntensityModel.new()
	m.on_event(&"dig")  # 0.06 -> needs 5 ticks to cross zero
	for _i in range(100):
		m.tick()
	assert_eq(m.level(), 0.0, "Excess decay must clamp to exactly 0.0")


## The last partial step lands on 0.0 (within float epsilon) and never below.
## 0.06 over 5 decay steps reaches the floor; binary-float subtraction leaves at
## most a sub-epsilon residue, and the level is clamped so it is never negative.
func test_decay_lands_on_zero_floor() -> void:
	var m := IntensityModel.new()
	# 0.06 / 0.012 = 5 steps to reach the 0.0 floor.
	m.on_event(&"dig")
	for _i in range(5):
		m.tick()
	assert_almost_eq(m.level(), 0.0, EPS, "0.06 over 5 decay steps must reach the 0.0 floor")
	assert_true(m.level() >= 0.0, "Level must never be negative")


# ---------------------------------------------------------------------------
# Event ordering independence
# ---------------------------------------------------------------------------


## The same multiset of events in different orders yields the same level
## (addition is commutative; no order-dependent state).
func test_event_ordering_independent() -> void:
	var a := IntensityModel.new()
	a.on_event(&"dig")
	a.on_event(&"cast")
	a.on_event(&"harvest")

	var b := IntensityModel.new()
	b.on_event(&"harvest")
	b.on_event(&"dig")
	b.on_event(&"cast")

	assert_almost_eq(a.level(), b.level(), EPS, "Event order must not affect the resulting level")


## Interleaving ticks between events is purely additive/subtractive: a tick then
## an event equals an event then the same tick (commute below clamp/floor).
func test_tick_event_commute_in_interior() -> void:
	var a := IntensityModel.new()
	a.on_event(&"cast")  # 0.15
	a.tick()  # 0.138
	a.on_event(&"dig")  # 0.198

	var b := IntensityModel.new()
	b.on_event(&"cast")  # 0.15
	b.on_event(&"dig")  # 0.21
	b.tick()  # 0.198

	assert_almost_eq(a.level(), b.level(), EPS, "tick/event must commute away from clamp and floor")


# ---------------------------------------------------------------------------
# Determinism — no RNG, no wall-clock
# ---------------------------------------------------------------------------


## Identical call sequences on separate instances yield identical levels,
## proving there is no hidden RNG or time dependence.
func test_deterministic_across_instances() -> void:
	var script := [
		&"player_hurt", &"tick", &"dig", &"tick", &"combat_hit", &"tick", &"tick", &"cast"
	]
	var a := IntensityModel.new()
	var b := IntensityModel.new()
	for step: StringName in script:
		if step == &"tick":
			a.tick()
			b.tick()
		else:
			a.on_event(step)
			b.on_event(step)
	assert_eq(a.level(), b.level(), "Identical scripts must produce bit-identical levels")


## The model's own source declares no RNG or wall-clock calls. This is a static
## guard against accidental introduction of nondeterminism.
func test_source_has_no_rng_or_clock() -> void:
	var path := "res://scripts/systems/audio/intensity_model.gd"
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "intensity_model.gd must be readable at %s" % path)
	var src := f.get_as_text()
	for needle in ["randf", "randi", "randomize", "RandomNumberGenerator", "Time.", "OS.get_ticks"]:
		assert_false(
			src.contains(needle), "Source must not reference '%s' (nondeterminism)" % needle
		)
