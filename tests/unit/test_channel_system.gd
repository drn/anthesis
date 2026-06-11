extends GutTest

## Exercises [ChannelSystem]: toggle on/off, per-tick drain, flare multiplier,
## mid-burn flake auto-swallow, depleted force-stop calling on_stop(&"depleted"),
## and install-less toggle being a safe no-op.

const VIGOR := &"vigor"
const PEWTER := &"pewter"
const FLAKE_PEWTER := &"pewter_flakes"


## Records on_start calls and on_stop reasons for a channel def.
class ChannelSpy:
	extends RefCounted

	var starts: int = 0
	var stops: Array = []

	func on_start() -> void:
		starts += 1

	func on_stop(reason: StringName) -> void:
		stops.append(reason)


func _reserves() -> MetalReserves:
	return MetalReserves.new({PEWTER: FLAKE_PEWTER})


func _channels(reserves: MetalReserves, inv: Object = null) -> ChannelSystem:
	var cs := ChannelSystem.new()
	add_child_autofree(cs)
	cs.setup(reserves, inv)
	return cs


func _vigor_def(spy: ChannelSpy, drain := 0.25) -> Dictionary:
	return {
		"resource_kind": PEWTER,
		"drain_per_tick": drain,
		"on_start": spy.on_start,
		"on_stop": spy.on_stop,
	}


func test_toggle_on_requires_reserve_and_calls_on_start() -> void:
	var r := _reserves()
	r.add(PEWTER, 10.0)
	var spy := ChannelSpy.new()
	var cs := _channels(r)
	cs.install(VIGOR, _vigor_def(spy))
	watch_signals(cs)

	assert_true(cs.toggle(VIGOR))
	assert_true(cs.is_active(VIGOR))
	assert_eq(spy.starts, 1)
	assert_signal_emitted_with_parameters(cs, "channel_changed", [VIGOR, true])


func test_toggle_on_fails_when_reserve_empty_no_flakes() -> void:
	var r := _reserves()  # empty, no inventory
	var spy := ChannelSpy.new()
	var cs := _channels(r)
	cs.install(VIGOR, _vigor_def(spy))

	assert_false(cs.toggle(VIGOR), "cannot open with nothing to burn")
	assert_false(cs.is_active(VIGOR))
	assert_eq(spy.starts, 0)


func test_toggle_off_calls_on_stop_manual() -> void:
	var r := _reserves()
	r.add(PEWTER, 10.0)
	var spy := ChannelSpy.new()
	var cs := _channels(r)
	cs.install(VIGOR, _vigor_def(spy))
	cs.toggle(VIGOR)

	assert_true(cs.toggle(VIGOR), "toggle off")
	assert_false(cs.is_active(VIGOR))
	assert_eq(spy.stops, [&"manual"])


func test_drain_per_tick() -> void:
	var r := _reserves()
	r.add(PEWTER, 10.0)
	var spy := ChannelSpy.new()
	var cs := _channels(r)
	cs.install(VIGOR, _vigor_def(spy, 0.25))
	cs.toggle(VIGOR)

	cs.on_tick(1)
	assert_almost_eq(r.well(PEWTER).current(), 9.75, 0.0001)


func test_flare_multiplies_drain() -> void:
	var r := _reserves()
	r.add(PEWTER, 10.0)
	var spy := ChannelSpy.new()
	var cs := _channels(r)
	cs.install(VIGOR, _vigor_def(spy, 0.25))
	cs.toggle(VIGOR)
	cs.set_flare(true)
	assert_true(cs.is_flaring())

	cs.on_tick(1)
	# 0.25 * FLARE_DRAIN_MULT (3.0) = 0.75 drained.
	assert_almost_eq(r.well(PEWTER).current(), 9.25, 0.0001)


func test_auto_swallow_mid_burn() -> void:
	var r := _reserves()  # empty well
	var inv := Inventory.new(24, null)
	inv.add(FLAKE_PEWTER, 1)
	var spy := ChannelSpy.new()
	var cs := _channels(r, inv)
	cs.install(VIGOR, _vigor_def(spy, 0.25))
	# Toggle on swallows the flake to cover the first tick's drain.
	assert_true(cs.toggle(VIGOR))
	assert_eq(inv.count_of(FLAKE_PEWTER), 0, "flake swallowed on toggle")
	assert_almost_eq(r.well(PEWTER).current(), MetalReserves.FLAKE_CHARGE, 0.0001)

	cs.on_tick(1)
	assert_true(cs.is_active(VIGOR), "still burning off the swallowed charge")
	assert_almost_eq(r.well(PEWTER).current(), 29.75, 0.0001)


func test_depleted_force_stop_calls_on_stop_depleted() -> void:
	var r := _reserves()
	r.add(PEWTER, 0.3)  # opens fine; not enough for two 0.25 drains, no flakes
	var spy := ChannelSpy.new()
	var cs := _channels(r)
	cs.install(VIGOR, _vigor_def(spy, 0.25))
	assert_true(cs.toggle(VIGOR))
	watch_signals(cs)

	cs.on_tick(1)  # 0.30 -> 0.05
	assert_true(cs.is_active(VIGOR))
	cs.on_tick(2)  # 0.05 < 0.25, no flakes -> force stop
	assert_false(cs.is_active(VIGOR))
	assert_eq(spy.stops, [&"depleted"])
	assert_signal_emitted_with_parameters(cs, "channel_changed", [VIGOR, false])


func test_uninstalled_toggle_is_noop() -> void:
	var r := _reserves()
	var cs := _channels(r)
	assert_false(cs.toggle(&"nope"))
	assert_false(cs.is_active(&"nope"))
	assert_eq(cs.active_channels(), [])


func test_active_channels_sorted() -> void:
	var r := MetalReserves.new({PEWTER: FLAKE_PEWTER, &"tin": &"tin_flakes"})
	r.add(PEWTER, 10.0)
	r.add(&"tin", 10.0)
	var spy := ChannelSpy.new()
	var cs := _channels(r)
	cs.install(VIGOR, _vigor_def(spy))
	cs.install(&"keensight", {"resource_kind": &"tin", "drain_per_tick": 0.1})
	cs.toggle(VIGOR)
	cs.toggle(&"keensight")
	assert_eq(cs.active_channels(), [&"keensight", VIGOR])
