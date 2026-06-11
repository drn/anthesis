extends GutTest

# ---------------------------------------------------------------------------
# Integration boot test for Phase 4 combat wiring (contract #11).
#
# Loads world.tscn and asserts the combat substrate is fully wired into the
# integrator: the CombatService is present and on the command context, the
# player's Health is owned by World and registered under the player id, the
# Umbrals container exists, the creature registry has loaded its defs, the
# spawn planner's tuning is reachable, and the player's strike intent routes to
# a World handler. Spawning itself is tick-driven and async, so we assert the
# static wiring rather than live creature instances.
# ---------------------------------------------------------------------------

const WORLD_SCENE := "res://scenes/world/world.tscn"


func _boot() -> World:
	var world: World = load(WORLD_SCENE).instantiate()
	add_child_autofree(world)
	return world


func test_combat_service_present() -> void:
	var world := _boot()
	var c := world.combat()
	assert_not_null(c, "combat() must return a CombatService")
	assert_true(c is CombatService, "combat() must be a CombatService")


func test_context_carries_combat_service() -> void:
	var world := _boot()
	var ctx: WorldContext = world.command_bus().get("_ctx")
	assert_true(ctx.combat is CombatService, "context must carry the CombatService")


func test_player_health_registered() -> void:
	var world := _boot()
	var hp := world.player_health()
	assert_not_null(hp, "player_health() must return a Health")
	assert_true(hp is Health, "player_health() must be a Health")
	assert_eq(hp.max_health(), 40.0, "the player must start with 40 max health")
	assert_eq(hp.current(), 40.0, "the player must start at full health")
	# The same Health must be registered in the combat service under the player id.
	var registered := world.combat().health_of(world.player().get_instance_id())
	assert_eq(registered, hp, "player Health must be registered under the player instance id")


func test_umbrals_container_present() -> void:
	var world := _boot()
	var umbrals := world.get_node_or_null("Umbrals")
	assert_not_null(umbrals, "an Umbrals container must exist for spawned creatures")
	assert_eq(umbrals.get_child_count(), 0, "no Umbrals should be spawned at boot")


func test_creature_registry_loaded() -> void:
	var world := _boot()
	var reg := world.creatures()
	assert_not_null(reg, "creatures() must return a CreatureRegistry")
	assert_true(reg is CreatureRegistry, "creatures() must be a CreatureRegistry")
	assert_gt(reg.creature_ids().size(), 0, "the creature registry must load Umbral defs")
	assert_not_null(reg.creature(&"voidmoth"), "registry must resolve the voidmoth def")
	assert_not_null(reg.creature(&"shardling"), "registry must resolve the shardling def")


func test_spawn_system_constants_reachable() -> void:
	# Sanity that the pure spawn planner's tuning is the pinned contract.
	assert_eq(SpawnSystem.SPAWN_INTERVAL_TICKS, 40, "spawn interval must be 40 ticks")
	assert_eq(SpawnSystem.POPULATION_CAP, 6, "population cap must be 6")


func test_player_strike_signal_connected() -> void:
	var world := _boot()
	var p := world.player()
	var connections := p.strike_requested.get_connections()
	var routed_to_world := false
	for conn in connections:
		if conn["callable"].get_object() == world:
			routed_to_world = true
	assert_true(routed_to_world, "strike_requested must route to a World handler")
