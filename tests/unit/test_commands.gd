extends GutTest


## A [TerrainEditService] subclass that records calls instead of editing.
class RecordingEditService:
	extends TerrainEditService

	var calls: Array = []

	func dig_sphere(center: Vector3, radius: float) -> void:
		calls.append({"op": "dig", "center": center, "radius": radius})

	func place_sphere(center: Vector3, radius: float) -> void:
		calls.append({"op": "place", "center": center, "radius": radius})


## Minimal stub [CraftingService] that records calls and controls return value.
class StubCraftingService:
	extends CraftingService

	var craft_calls: Array = []
	var craft_return := true

	func _init() -> void:
		super(ItemRegistry.new("", ""))

	func can_craft(_inv: Inventory, _recipe: Recipe) -> bool:
		return craft_return

	func craft(inv: Inventory, recipe: Recipe) -> bool:
		craft_calls.append({"inv": inv, "recipe": recipe})
		return craft_return


## Minimal stub [LootService] that records calls.
class StubLootService:
	extends LootService

	var dig_calls: Array = []
	var harvest_calls: Array = []

	func _init() -> void:
		super(WorldSeed.new(0), Inventory.new(4))

	func award_dig_loot(center: Vector3, radius: float) -> Array[ItemAmount]:
		dig_calls.append({"center": center, "radius": radius})
		return []

	func award_harvest_loot(drops: Array[ItemAmount]) -> void:
		harvest_calls.append(drops.duplicate())


func _make_context() -> WorldContext:
	var ctx := WorldContext.new()
	ctx.terrain_edit = RecordingEditService.new()
	return ctx


func _make_full_context() -> WorldContext:
	var ctx := _make_context()
	ctx.inventory = Inventory.new(24)
	ctx.crafting = StubCraftingService.new()
	ctx.loot = StubLootService.new()
	return ctx


# ---------------------------------------------------------------------------
# Existing tests (unchanged)
# ---------------------------------------------------------------------------


func test_dig_command_routes_to_dig_sphere() -> void:
	var ctx := _make_context()
	var recorder: RecordingEditService = ctx.terrain_edit

	DigCommand.new(Vector3(1, 2, 3), 1.6).apply(ctx)

	assert_eq(recorder.calls.size(), 1)
	assert_eq(recorder.calls[0]["op"], "dig")
	assert_eq(recorder.calls[0]["center"], Vector3(1, 2, 3))
	assert_eq(recorder.calls[0]["radius"], 1.6)


func test_place_command_routes_to_place_sphere() -> void:
	var ctx := _make_context()
	var recorder: RecordingEditService = ctx.terrain_edit

	PlaceCommand.new(Vector3(4, 5, 6), 2.5).apply(ctx)

	assert_eq(recorder.calls.size(), 1)
	assert_eq(recorder.calls[0]["op"], "place")
	assert_eq(recorder.calls[0]["center"], Vector3(4, 5, 6))
	assert_eq(recorder.calls[0]["radius"], 2.5)


func test_command_bus_applies_command() -> void:
	var ctx := _make_context()
	var recorder: RecordingEditService = ctx.terrain_edit
	var bus := CommandBus.new(ctx)

	bus.execute(DigCommand.new(Vector3.ZERO, 1.0))

	assert_eq(recorder.calls.size(), 1)
	assert_eq(recorder.calls[0]["op"], "dig")


func test_command_bus_emits_command_executed() -> void:
	var ctx := _make_context()
	var bus := CommandBus.new(ctx)
	watch_signals(bus)

	var cmd := PlaceCommand.new(Vector3.ONE, 1.0)
	bus.execute(cmd)

	assert_signal_emitted(bus, "command_executed")
	assert_signal_emitted_with_parameters(bus, "command_executed", [cmd])


# ---------------------------------------------------------------------------
# DigCommand — loot integration
# ---------------------------------------------------------------------------


func test_dig_command_awards_loot_when_ctx_loot_set() -> void:
	var ctx := _make_full_context()
	var loot_stub: StubLootService = ctx.loot

	DigCommand.new(Vector3(10, 0, 10), 2.0).apply(ctx)

	assert_eq(loot_stub.dig_calls.size(), 1)
	assert_eq(loot_stub.dig_calls[0]["center"], Vector3(10, 0, 10))
	assert_eq(loot_stub.dig_calls[0]["radius"], 2.0)


func test_dig_command_no_loot_when_ctx_loot_null() -> void:
	## Backward-compat: a context without loot should still dig without errors.
	var ctx := _make_context()
	var recorder: RecordingEditService = ctx.terrain_edit

	# ctx.loot is null — must not crash.
	DigCommand.new(Vector3.ZERO, 1.0).apply(ctx)

	assert_eq(recorder.calls.size(), 1)
	assert_eq(recorder.calls[0]["op"], "dig")


func test_dig_command_still_digs_when_loot_set() -> void:
	## Terrain edit still happens even when loot service is wired.
	var ctx := _make_full_context()
	var recorder: RecordingEditService = ctx.terrain_edit

	DigCommand.new(Vector3(5, 5, 5), 1.5).apply(ctx)

	assert_eq(recorder.calls.size(), 1)
	assert_eq(recorder.calls[0]["op"], "dig")


# ---------------------------------------------------------------------------
# CraftCommand
# ---------------------------------------------------------------------------


func test_craft_command_delegates_to_crafting_service() -> void:
	var ctx := _make_full_context()
	var crafting_stub: StubCraftingService = ctx.crafting

	var recipe := Recipe.new()
	recipe.id = &"test_recipe"
	CraftCommand.new(recipe).apply(ctx)

	assert_eq(crafting_stub.craft_calls.size(), 1)
	assert_eq(crafting_stub.craft_calls[0]["recipe"], recipe)
	assert_eq(crafting_stub.craft_calls[0]["inv"], ctx.inventory)


func test_craft_command_noop_when_crafting_null() -> void:
	var ctx := _make_context()
	# ctx.crafting is null — must not crash.
	var recipe := Recipe.new()
	CraftCommand.new(recipe).apply(ctx)
	# No assertion needed beyond no crash.
	assert_true(true)


func test_craft_command_noop_when_inventory_null() -> void:
	var ctx := _make_context()
	ctx.crafting = StubCraftingService.new()
	# ctx.inventory is null — must not crash.
	var recipe := Recipe.new()
	CraftCommand.new(recipe).apply(ctx)
	assert_true(true)


# ---------------------------------------------------------------------------
# HarvestCommand
# ---------------------------------------------------------------------------


func test_harvest_command_awards_drops() -> void:
	var ctx := _make_full_context()
	var loot_stub: StubLootService = ctx.loot

	var drops: Array[ItemAmount] = []
	var drop := ItemAmount.new()
	drop.item_id = &"glow_spore"
	drop.count = 2
	drops.append(drop)

	var fake_node := Node.new()
	HarvestCommand.new(fake_node, drops).apply(ctx)

	assert_eq(loot_stub.harvest_calls.size(), 1)
	assert_eq(loot_stub.harvest_calls[0].size(), 1)
	assert_eq(loot_stub.harvest_calls[0][0].item_id, &"glow_spore")
	assert_eq(loot_stub.harvest_calls[0][0].count, 2)
	fake_node.free()


func test_harvest_command_calls_flora_harvest_callable() -> void:
	var ctx := _make_full_context()

	var freed_nodes: Array = []
	ctx.flora_harvest = func(node: Node) -> void: freed_nodes.append(node)

	var fake_node := Node.new()
	var drops: Array[ItemAmount] = []
	HarvestCommand.new(fake_node, drops).apply(ctx)

	assert_eq(freed_nodes.size(), 1)
	assert_eq(freed_nodes[0], fake_node)
	fake_node.free()


func test_harvest_command_skips_harvest_when_loot_null() -> void:
	var ctx := _make_context()
	# ctx.loot is null — must not crash; drops are silently skipped.
	var drops: Array[ItemAmount] = []
	var drop := ItemAmount.new()
	drop.item_id = &"soil"
	drop.count = 1
	drops.append(drop)

	var fake_node := Node.new()
	HarvestCommand.new(fake_node, drops).apply(ctx)
	# No crash is the assertion.
	assert_true(true)
	fake_node.free()


func test_harvest_command_skips_flora_harvest_when_callable_invalid() -> void:
	var ctx := _make_full_context()
	# Leave ctx.flora_harvest as the default invalid Callable.

	var fake_node := Node.new()
	var drops: Array[ItemAmount] = []
	# Must not crash when flora_harvest is invalid.
	HarvestCommand.new(fake_node, drops).apply(ctx)
	assert_true(true)
	fake_node.free()
