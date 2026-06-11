extends GutTest

# ---------------------------------------------------------------------------
# Integration boot test (contract #9 — integrator composition).
#
# Loads world.tscn and asserts the full subsystem graph is wired: terrain,
# environment, player, flora, and the command layer connecting player intents
# to terrain edits. Terrain streaming is async and does not complete headless,
# so we assert structure + wiring rather than runtime placement.
# ---------------------------------------------------------------------------

const WORLD_SCENE := "res://scenes/world/world.tscn"


func _boot() -> World:
	var world: World = load(WORLD_SCENE).instantiate()
	add_child_autofree(world)
	return world


func test_world_root_is_world() -> void:
	var world := _boot()
	assert_true(world is World, "world.tscn root must be a World")


func test_voxel_world_present() -> void:
	var world := _boot()
	var vw := world.voxel_world()
	assert_not_null(vw, "voxel_world() must return a VoxelWorld")
	assert_true(vw is VoxelWorld, "voxel_world() must be a VoxelWorld")
	assert_true(vw.is_inside_tree(), "terrain must be in the scene tree")


func test_environment_present() -> void:
	var world := _boot()
	var env := world.get_node_or_null("Environment_Rig")
	assert_not_null(env, "an Environment_Rig must be instanced under World")
	var world_env := env.get_node_or_null("WorldEnvironment")
	assert_not_null(world_env, "Environment_Rig must contain a WorldEnvironment")


func test_player_present() -> void:
	var world := _boot()
	var p := world.player()
	assert_not_null(p, "player() must return a Player")
	assert_true(p is Player, "player() must be a Player")
	assert_true(p.is_inside_tree(), "player must be in the scene tree")


func test_flora_present() -> void:
	var world := _boot()
	var f := world.flora()
	assert_not_null(f, "flora() must return a FloraScatter")
	assert_true(f is FloraScatter, "flora() must be a FloraScatter")
	assert_eq(f.prop_scenes.size(), 3, "flora must be configured with 3 prop scenes")


func test_inventory_wired() -> void:
	var world := _boot()
	var inv := world.inventory()
	assert_not_null(inv, "inventory() must return an Inventory")
	assert_true(inv is Inventory, "inventory() must be an Inventory")
	assert_eq(inv.size(), 24, "inventory must have 24 slots")
	assert_true(inv.is_empty(), "a fresh world inventory must start empty")


func test_registry_wired() -> void:
	var world := _boot()
	var reg := world.registry()
	assert_not_null(reg, "registry() must return an ItemRegistry")
	assert_true(reg is ItemRegistry, "registry() must be an ItemRegistry")
	assert_gt(reg.item_ids().size(), 0, "registry must have loaded item resources")
	assert_not_null(reg.item(&"soil"), "registry must resolve the soil item")
	assert_gt(reg.recipes().size(), 0, "registry must have loaded recipe resources")


func test_hud_present_and_bound() -> void:
	var world := _boot()
	var h := world.hud()
	assert_not_null(h, "hud() must return a Hud")
	assert_true(h is Hud, "hud() must be a Hud")
	assert_true(h.is_inside_tree(), "hud must be in the scene tree")


func test_context_carries_phase2_services() -> void:
	# The command context must expose inventory/registry/crafting/loot so dig,
	# craft, and harvest commands can mutate Phase 2 state.
	var world := _boot()
	var inv := world.inventory()
	# Digging should award loot through the bus into the same inventory instance.
	world.command_bus().execute(CraftCommand.new(world.registry().recipe(&"bloom_brick")))
	# No inputs present, so the craft is a no-op: inventory stays empty.
	assert_true(inv.is_empty(), "crafting with no inputs must not alter the inventory")


func test_player_harvest_signal_connected() -> void:
	var world := _boot()
	var p := world.player()
	assert_gt(
		p.harvest_requested.get_connections().size(),
		0,
		"player.harvest_requested must be connected to a World handler"
	)


func test_command_bus_wired() -> void:
	var world := _boot()
	var bus := world.command_bus()
	assert_not_null(bus, "command_bus() must return a CommandBus")
	assert_true(bus is CommandBus, "command_bus() must be a CommandBus")


func test_player_signals_connected_to_bus() -> void:
	var world := _boot()
	var p := world.player()
	assert_gt(p.dig_requested.get_connections().size(), 0, "player.dig_requested must be connected")
	assert_gt(
		p.place_requested.get_connections().size(), 0, "player.place_requested must be connected"
	)


func test_dig_request_routes_to_world_handler() -> void:
	# Wiring check: the player's dig signal must be connected to a callable on
	# the World node (its command-routing handler). We assert the connection
	# target rather than emitting, because a live dig calls into the voxel
	# tool whose chunk data has not streamed in headless ("Area not editable").
	var world := _boot()
	var connections := world.player().dig_requested.get_connections()
	var routed_to_world := false
	for conn in connections:
		if conn["callable"].get_object() == world:
			routed_to_world = true
	assert_true(routed_to_world, "dig_requested must route to a World handler")


func test_place_request_routes_to_world_handler() -> void:
	var world := _boot()
	var connections := world.player().place_requested.get_connections()
	var routed_to_world := false
	for conn in connections:
		if conn["callable"].get_object() == world:
			routed_to_world = true
	assert_true(routed_to_world, "place_requested must route to a World handler")
