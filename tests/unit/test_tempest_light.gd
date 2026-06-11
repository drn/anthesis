extends GutTest

## Exercises [TempestLight] with the real [StatusEffectSystem], [Health], and
## [Inventory]: the inhale gem exchange, per-tick leak draining to zero with the
## holding edge signals, the healing regen math + cadence, and the
## speed_modifier closure firing exactly on the holding edges.

const CHARGED := &"charged_gem"
const DUN := &"dun_gem"


## Records speed_modifier(active) calls so we can assert edge behaviour.
class SpeedSpy:
	extends RefCounted

	var calls: Array = []

	func on_speed(active: bool) -> void:
		calls.append(active)


## A stand-in player whose instance id the status keys on.
class FakeTarget:
	extends RefCounted


func _status() -> StatusEffectSystem:
	var s := StatusEffectSystem.new()
	add_child_autofree(s)
	return s


func _build(
	status: StatusEffectSystem, health: Health, target: RefCounted, spy: SpeedSpy
) -> TempestLight:
	var t := TempestLight.new()
	add_child_autofree(t)
	t.setup(status, health, func() -> int: return target.get_instance_id(), null, spy.on_speed)
	return t


func test_well_starts_empty_at_capacity() -> void:
	var t := _build(_status(), Health.new(20.0), FakeTarget.new(), SpeedSpy.new())
	assert_eq(t.well().capacity(), TempestLight.CAPACITY)
	assert_eq(t.well().current(), 0.0)


func test_inhale_exchanges_charged_for_dun_and_fills() -> void:
	var inv := Inventory.new(24, null)
	inv.add(CHARGED, 2)
	var t := _build(_status(), Health.new(20.0), FakeTarget.new(), SpeedSpy.new())

	assert_true(t.inhale(inv))
	assert_eq(inv.count_of(CHARGED), 1, "one charged gem consumed")
	assert_eq(inv.count_of(DUN), 1, "one dun gem returned")
	assert_almost_eq(t.well().current(), TempestLight.INHALE_CHARGE, 0.0001)


func test_inhale_without_charged_gems_is_false() -> void:
	var inv := Inventory.new(24, null)
	var t := _build(_status(), Health.new(20.0), FakeTarget.new(), SpeedSpy.new())
	assert_false(t.inhale(inv))
	assert_eq(t.well().current(), 0.0)


func test_inhale_null_inventory_is_false() -> void:
	var t := _build(_status(), Health.new(20.0), FakeTarget.new(), SpeedSpy.new())
	assert_false(t.inhale(null))


func test_inhale_emits_holding_and_calls_speed_modifier() -> void:
	var inv := Inventory.new(24, null)
	inv.add(CHARGED, 1)
	var spy := SpeedSpy.new()
	var t := _build(_status(), Health.new(20.0), FakeTarget.new(), spy)
	watch_signals(t)

	t.inhale(inv)

	assert_signal_emitted_with_parameters(t, "holding_changed", [true])
	assert_eq(spy.calls, [true], "speed modifier engaged on the rising edge")


func test_leak_drains_one_tenth_per_tick() -> void:
	var inv := Inventory.new(24, null)
	inv.add(CHARGED, 1)
	var t := _build(_status(), Health.new(20.0), FakeTarget.new(), SpeedSpy.new())
	t.inhale(inv)  # 40.0

	t.on_tick(1)
	assert_almost_eq(t.well().current(), 40.0 - TempestLight.LEAK_PER_TICK, 0.0001)


func test_leak_to_zero_fires_falling_edge_and_clears_speed() -> void:
	var status := _status()
	var target := FakeTarget.new()
	var spy := SpeedSpy.new()
	var t := _build(status, Health.new(20.0), target, spy)
	# Seed a tiny amount so a single leak tick empties it.
	t.well().add(0.05)
	t._reconcile()  # rising edge (engages the speed modifier)
	spy.calls.clear()  # discard the rising-edge call; assert only the falling edge
	watch_signals(t)

	t.on_tick(1)  # 0.05 -> 0.0

	assert_almost_eq(t.well().current(), 0.0, 0.0001)
	assert_signal_emitted_with_parameters(t, "holding_changed", [false])
	assert_eq(spy.calls, [false], "speed modifier cleared on the falling edge")
	assert_false(status.has(target.get_instance_id(), TempestLight.TEMPEST_STATUS))


func test_holding_status_applied_while_holding() -> void:
	var status := _status()
	var target := FakeTarget.new()
	var t := _build(status, Health.new(20.0), target, SpeedSpy.new())
	t.well().add(50.0)
	t._reconcile()
	assert_true(status.has(target.get_instance_id(), TempestLight.TEMPEST_STATUS))


func test_regen_heals_on_interval_when_hurt() -> void:
	var health := Health.new(20.0)
	health.take_damage(10.0)  # current 10
	var t := _build(_status(), health, FakeTarget.new(), SpeedSpy.new())
	t.well().add(50.0)
	t._reconcile()

	t.on_tick(TempestLight.REGEN_INTERVAL_TICKS)  # tick 10 -> regen pulse

	assert_almost_eq(health.current(), 10.0 + TempestLight.REGEN_AMOUNT, 0.0001)
	# 50 - leak(0.1) - regen cost(2.0) = 47.9
	assert_almost_eq(
		t.well().current(), 50.0 - TempestLight.LEAK_PER_TICK - TempestLight.REGEN_COST, 0.0001
	)


func test_regen_skipped_off_interval() -> void:
	var health := Health.new(20.0)
	health.take_damage(10.0)
	var t := _build(_status(), health, FakeTarget.new(), SpeedSpy.new())
	t.well().add(50.0)
	t._reconcile()

	t.on_tick(1)  # not a multiple of REGEN_INTERVAL_TICKS
	assert_almost_eq(health.current(), 10.0, 0.0001)


func test_regen_skipped_at_full_health() -> void:
	var health := Health.new(20.0)  # full
	var t := _build(_status(), health, FakeTarget.new(), SpeedSpy.new())
	t.well().add(50.0)
	t._reconcile()

	t.on_tick(TempestLight.REGEN_INTERVAL_TICKS)
	assert_almost_eq(health.current(), 20.0, 0.0001)
	# Only the leak spent, no regen cost.
	assert_almost_eq(t.well().current(), 50.0 - TempestLight.LEAK_PER_TICK, 0.0001)


func test_regen_skipped_when_unaffordable() -> void:
	var health := Health.new(20.0)
	health.take_damage(10.0)
	var t := _build(_status(), health, FakeTarget.new(), SpeedSpy.new())
	t.well().add(1.0)  # < REGEN_COST after leak
	t._reconcile()

	t.on_tick(TempestLight.REGEN_INTERVAL_TICKS)
	assert_almost_eq(health.current(), 10.0, 0.0001, "no heal: pool cannot afford regen")


func test_glow_null_safe() -> void:
	# setup with a null glow (headless) and ticking must not error.
	var t := _build(_status(), Health.new(20.0), FakeTarget.new(), SpeedSpy.new())
	t.well().add(50.0)
	t.on_tick(1)
	pass_test("ticking with a null glow did not error")


func test_only_one_speed_edge_per_cross() -> void:
	var inv := Inventory.new(24, null)
	inv.add(CHARGED, 1)
	var spy := SpeedSpy.new()
	var t := _build(_status(), Health.new(20.0), FakeTarget.new(), spy)
	t.inhale(inv)  # rising edge -> [true]

	# Many ticks while still holding: no extra speed calls.
	for tick in range(1, 5):
		t.on_tick(tick)
	assert_eq(spy.calls, [true], "speed modifier engaged exactly once while holding")
