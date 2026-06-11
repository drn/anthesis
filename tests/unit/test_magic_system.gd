extends GutTest

## Exercises the [MagicSystem] rule gate: the deterministic cooldown-then-cost
## ordering, the effect-false no-spend invariant, cooldown math against a fake
## tick source, signal reasons, and independent per-ability cooldowns.


## Mutable tick source standing in for the SimulationClock. try_cast reads the
## current tick through a Callable; this holder lets a test advance time.
class FakeClock:
	extends RefCounted

	var tick: int = 0

	func now() -> int:
		return tick


## Records how many times an effect ran and what it returned.
class EffectSpy:
	extends RefCounted

	var calls: int = 0
	var result := true

	func run() -> bool:
		calls += 1
		return result


func _ability(id: StringName, cost: float, cooldown: int, kind := &"shape_burst") -> AbilityDef:
	var a := AbilityDef.new()
	a.id = id
	a.kind = kind
	a.lumen_cost = cost
	a.cooldown_ticks = cooldown
	return a


## A well constructed at [param capacity] and filled to the brim. The well starts
## empty by design (lumen is gathered, never free), so casting tests top it up.
func _full_well(capacity := 100.0) -> LumenWell:
	var well := LumenWell.new(capacity)
	well.add(capacity)
	return well


# ---------------------------------------------------------------------------
# Affordability gate
# ---------------------------------------------------------------------------


func test_cast_succeeds_when_affordable_and_off_cooldown() -> void:
	var clock := FakeClock.new()
	var well := _full_well(100.0)
	var magic := MagicSystem.new(well, clock.now)
	var ability := _ability(&"burst", 25.0, 30)
	watch_signals(magic)

	var ok := magic.try_cast(ability, func() -> bool: return true)

	assert_true(ok)
	assert_eq(well.current(), 75.0)
	assert_signal_emitted(magic, "cast_succeeded")


func test_cast_fails_on_cost_when_well_too_low() -> void:
	var clock := FakeClock.new()
	var well := _full_well(100.0)
	well.spend(90.0)  # 10 left
	var magic := MagicSystem.new(well, clock.now)
	var ability := _ability(&"burst", 25.0, 30)
	var spy := EffectSpy.new()
	watch_signals(magic)

	var ok := magic.try_cast(ability, spy.run)

	assert_false(ok)
	assert_eq(spy.calls, 0, "effect must not run when unaffordable")
	assert_eq(well.current(), 10.0, "nothing spent on a cost failure")
	assert_signal_emitted_with_parameters(magic, "cast_failed", [ability, &"cost"])


func test_can_cast_reflects_affordability() -> void:
	var clock := FakeClock.new()
	var well := _full_well(100.0)
	var magic := MagicSystem.new(well, clock.now)
	var ability := _ability(&"burst", 25.0, 30)

	assert_true(magic.can_cast(ability))
	well.spend(80.0)  # 20 left, cost 25
	assert_false(magic.can_cast(ability))


# ---------------------------------------------------------------------------
# Cooldown gate + ordering
# ---------------------------------------------------------------------------


func test_cooldown_blocks_second_cast_until_elapsed() -> void:
	var clock := FakeClock.new()
	var well := _full_well(100.0)
	var magic := MagicSystem.new(well, clock.now)
	var ability := _ability(&"burst", 10.0, 20)
	watch_signals(magic)

	assert_true(magic.try_cast(ability, func() -> bool: return true))
	# Same tick: on cooldown.
	assert_false(magic.try_cast(ability, func() -> bool: return true))
	assert_signal_emitted_with_parameters(magic, "cast_failed", [ability, &"cooldown"])

	clock.tick = 19  # still one tick short
	assert_false(magic.try_cast(ability, func() -> bool: return true))

	clock.tick = 20  # exactly elapsed
	assert_true(magic.try_cast(ability, func() -> bool: return true))


func test_cooldown_remaining_math() -> void:
	var clock := FakeClock.new()
	var well := _full_well(100.0)
	var magic := MagicSystem.new(well, clock.now)
	var ability := _ability(&"burst", 10.0, 30)

	assert_eq(magic.cooldown_remaining(ability), 0, "never cast => ready")

	clock.tick = 100
	magic.try_cast(ability, func() -> bool: return true)
	assert_eq(magic.cooldown_remaining(ability), 30)

	clock.tick = 110
	assert_eq(magic.cooldown_remaining(ability), 20)

	clock.tick = 130
	assert_eq(magic.cooldown_remaining(ability), 0)

	clock.tick = 200  # long idle never goes negative
	assert_eq(magic.cooldown_remaining(ability), 0)


func test_cooldown_checked_before_cost() -> void:
	## Sanderson determinism: when both gates would fail, cooldown wins so the
	## reason is stable regardless of well state.
	var clock := FakeClock.new()
	var well := _full_well(100.0)
	var magic := MagicSystem.new(well, clock.now)
	var ability := _ability(&"burst", 25.0, 30)

	assert_true(magic.try_cast(ability, func() -> bool: return true))  # well now 75
	well.spend(75.0)  # drain so cost would also fail
	watch_signals(magic)

	var ok := magic.try_cast(ability, func() -> bool: return true)
	assert_false(ok)
	assert_signal_emitted_with_parameters(magic, "cast_failed", [ability, &"cooldown"])


# ---------------------------------------------------------------------------
# Effect-false: nothing spent, no cooldown armed
# ---------------------------------------------------------------------------


func test_effect_false_spends_nothing_and_arms_no_cooldown() -> void:
	var clock := FakeClock.new()
	var well := _full_well(100.0)
	var magic := MagicSystem.new(well, clock.now)
	var ability := _ability(&"burst", 25.0, 30)
	watch_signals(magic)

	var ok := magic.try_cast(ability, func() -> bool: return false)

	assert_false(ok)
	assert_eq(well.current(), 100.0, "failed effect refunds nothing because nothing was spent")
	assert_eq(magic.cooldown_remaining(ability), 0, "no cooldown armed on failed effect")
	assert_signal_emitted_with_parameters(magic, "cast_failed", [ability, &"no_effect"])


func test_effect_false_then_true_succeeds_immediately() -> void:
	var clock := FakeClock.new()
	var well := _full_well(100.0)
	var magic := MagicSystem.new(well, clock.now)
	var ability := _ability(&"burst", 25.0, 30)

	assert_false(magic.try_cast(ability, func() -> bool: return false))
	# No cooldown armed, so a successful effect on the same tick goes through.
	assert_true(magic.try_cast(ability, func() -> bool: return true))
	assert_eq(well.current(), 75.0)


# ---------------------------------------------------------------------------
# Independent per-ability cooldowns
# ---------------------------------------------------------------------------


func test_abilities_have_independent_cooldowns() -> void:
	var clock := FakeClock.new()
	var well := _full_well(100.0)
	var magic := MagicSystem.new(well, clock.now)
	var burst := _ability(&"burst", 10.0, 30, &"shape_burst")
	var bloom := _ability(&"bloom", 10.0, 20, &"lumen_bloom")

	assert_true(magic.try_cast(burst, func() -> bool: return true))
	# Different ability is unaffected by burst's cooldown.
	assert_true(magic.try_cast(bloom, func() -> bool: return true))

	assert_eq(magic.cooldown_remaining(burst), 30)
	assert_eq(magic.cooldown_remaining(bloom), 20)
