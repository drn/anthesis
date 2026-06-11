extends GutTest

## Covers [CastCommand] routing through the [MagicSystem] rule gate and the
## [HarvestCommand] Lumen-gathering hook. Split from test_commands.gd to keep
## each test class under gdlint's 20-public-method ceiling.


## Records the (ability, target) of each effect invocation and its return value.
class EffectSpy:
	extends RefCounted

	var calls: Array = []
	var result := true

	func run(ability: AbilityDef, target: Vector3) -> bool:
		calls.append({"ability": ability, "target": target})
		return result


## Records amounts handed to a lumen_gain Callable.
class LumenSink:
	extends RefCounted

	var amounts: Array[float] = []

	func add(amount: float) -> void:
		amounts.append(amount)


func _ability(id: StringName, kind: StringName, cost := 10.0, cooldown := 20) -> AbilityDef:
	var a := AbilityDef.new()
	a.id = id
	a.kind = kind
	a.lumen_cost = cost
	a.cooldown_ticks = cooldown
	return a


func _magic_context() -> WorldContext:
	# The well starts empty by design (lumen is gathered, not free); fill it so
	# cast tests exercise the effect/cooldown paths rather than the cost gate.
	# A constant tick Callable keeps the clock self-contained (no object to free).
	var well := LumenWell.new(100.0)
	well.add(100.0)
	var ctx := WorldContext.new()
	ctx.magic = MagicSystem.new(well, func() -> int: return 0)
	return ctx


func _prop_with_lumen(amount: float) -> Node:
	var prop := Node.new()
	var harvestable := Harvestable.new()
	harvestable.name = "Harvestable"
	harvestable.lumen = amount
	prop.add_child(harvestable)
	return prop


# ---------------------------------------------------------------------------
# CastCommand — routing through the rule gate
# ---------------------------------------------------------------------------


func test_cast_runs_registered_effect_with_ability_and_target() -> void:
	var ctx := _magic_context()
	var spy := EffectSpy.new()
	ctx.ability_effects = {&"shape_burst": spy.run}
	var ability := _ability(&"burst", &"shape_burst", 25.0, 30)
	watch_signals(ctx.magic)

	CastCommand.new(ability, Vector3(1, 2, 3)).apply(ctx)

	assert_eq(spy.calls.size(), 1)
	assert_eq(spy.calls[0]["ability"], ability)
	assert_eq(spy.calls[0]["target"], Vector3(1, 2, 3))
	assert_signal_emitted(ctx.magic, "cast_succeeded")


func test_cast_no_effect_when_kind_unregistered() -> void:
	var ctx := _magic_context()
	# Empty ability_effects => no_effect path; nothing spent.
	var ability := _ability(&"burst", &"shape_burst", 25.0, 30)
	watch_signals(ctx.magic)

	CastCommand.new(ability, Vector3.ZERO).apply(ctx)

	assert_signal_emitted_with_parameters(ctx.magic, "cast_failed", [ability, &"no_effect"])


func test_cast_effect_false_emits_no_effect_and_spends_nothing() -> void:
	var ctx := _magic_context()
	var spy := EffectSpy.new()
	spy.result = false
	ctx.ability_effects = {&"shape_burst": spy.run}
	var ability := _ability(&"burst", &"shape_burst", 25.0, 30)
	watch_signals(ctx.magic)

	CastCommand.new(ability, Vector3.ZERO).apply(ctx)

	assert_eq(spy.calls.size(), 1)
	assert_signal_emitted_with_parameters(ctx.magic, "cast_failed", [ability, &"no_effect"])


func test_cast_noop_when_magic_null() -> void:
	var ctx := WorldContext.new()  # no magic wired
	var ability := _ability(&"burst", &"shape_burst")
	# Must not crash.
	CastCommand.new(ability, Vector3.ZERO).apply(ctx)
	assert_true(true)


func test_cast_routes_through_command_bus() -> void:
	var ctx := _magic_context()
	var spy := EffectSpy.new()
	ctx.ability_effects = {&"skyward": spy.run}
	var bus := CommandBus.new(ctx)
	var ability := _ability(&"step", &"skyward", 10.0, 15)

	bus.execute(CastCommand.new(ability, Vector3.UP))

	assert_eq(spy.calls.size(), 1)


# ---------------------------------------------------------------------------
# HarvestCommand — Lumen gathering hook
# ---------------------------------------------------------------------------


func test_harvest_credits_lumen_via_lumen_gain() -> void:
	var ctx := _magic_context()
	var sink := LumenSink.new()
	ctx.lumen_gain = sink.add

	var prop := _prop_with_lumen(10.0)
	HarvestCommand.new(prop, [] as Array[ItemAmount]).apply(ctx)

	assert_eq(sink.amounts.size(), 1)
	assert_eq(sink.amounts[0], 10.0)
	prop.free()


func test_harvest_skips_lumen_when_magic_null() -> void:
	## Backward compat: no magic wired => no lumen credited, no crash.
	var ctx := WorldContext.new()
	var sink := LumenSink.new()
	ctx.lumen_gain = sink.add

	var prop := _prop_with_lumen(10.0)
	HarvestCommand.new(prop, [] as Array[ItemAmount]).apply(ctx)

	assert_eq(sink.amounts.size(), 0)
	prop.free()


func test_harvest_skips_lumen_when_gain_invalid() -> void:
	var ctx := _magic_context()
	# Leave ctx.lumen_gain as the default invalid Callable.
	var prop := _prop_with_lumen(10.0)
	# Must not crash.
	HarvestCommand.new(prop, [] as Array[ItemAmount]).apply(ctx)
	assert_true(true)
	prop.free()


func test_harvest_skips_lumen_when_no_harvestable_child() -> void:
	var ctx := _magic_context()
	var sink := LumenSink.new()
	ctx.lumen_gain = sink.add

	var bare := Node.new()  # no Harvestable child
	HarvestCommand.new(bare, [] as Array[ItemAmount]).apply(ctx)

	assert_eq(sink.amounts.size(), 0)
	bare.free()


func test_harvest_skips_lumen_when_lumen_zero() -> void:
	var ctx := _magic_context()
	var sink := LumenSink.new()
	ctx.lumen_gain = sink.add

	var prop := _prop_with_lumen(0.0)
	HarvestCommand.new(prop, [] as Array[ItemAmount]).apply(ctx)

	assert_eq(sink.amounts.size(), 0)
	prop.free()


# ---------------------------------------------------------------------------
# CastCommand — metal-reserve auto-top-up before cost gate
# ---------------------------------------------------------------------------


## Minimal fake for MetalReserves that records ensure_for_cost calls.
class MetalReservesSpy:
	extends RefCounted

	var calls: Array = []
	var result := true

	func ensure_for_cost(ability: AbilityDef, inventory: Object) -> bool:
		calls.append({"ability": ability, "inventory": inventory})
		return result


func test_cast_auto_tops_up_metal_before_cost_gate() -> void:
	## When metal_reserves is wired, ensure_for_cost is called before the magic
	## rule gate so flakes in the inventory can fund the cast.
	var ctx := _magic_context()
	var spy := EffectSpy.new()
	ctx.ability_effects = {&"iron": spy.run}
	var reserves_spy := MetalReservesSpy.new()
	ctx.metal_reserves = reserves_spy
	ctx.inventory = Inventory.new(24, null)
	var ability := _ability(&"ferro_pull", &"iron", 12.0, 8)
	watch_signals(ctx.magic)

	CastCommand.new(ability, Vector3.ZERO).apply(ctx)

	assert_eq(reserves_spy.calls.size(), 1)
	assert_eq(reserves_spy.calls[0]["ability"], ability)
	assert_eq(reserves_spy.calls[0]["inventory"], ctx.inventory)


func test_cast_skips_top_up_when_metal_reserves_null() -> void:
	## Null metal_reserves: must not crash; the magic gate runs as before.
	var ctx := _magic_context()
	var spy := EffectSpy.new()
	ctx.ability_effects = {&"shape_burst": spy.run}
	var ability := _ability(&"burst", &"shape_burst", 25.0, 30)
	watch_signals(ctx.magic)

	CastCommand.new(ability, Vector3.ZERO).apply(ctx)

	assert_eq(spy.calls.size(), 1)
	assert_signal_emitted(ctx.magic, "cast_succeeded")
