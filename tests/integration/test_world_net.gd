extends GutTest

# ---------------------------------------------------------------------------
# Integration: Phase 7 networking wiring (contract #9 — integrator composition).
#
# Boots world.tscn and asserts the net layer is composed and OFFLINE by default:
# the NetworkSession is present and inactive, the CommandRouter is the seam every
# player-intent flows through (a dig via the router mutates nothing networked yet
# still raises music intensity, proving offline routes to the bus), and
# rebuild_for_session reseeds + rebuilds the world cleanly from an empty log.
#
# Terrain streaming is async and does not complete headless, so dig is asserted
# via its observable side effect (intensity) rather than voxel mutation.
# ---------------------------------------------------------------------------

const WORLD_SCENE := "res://scenes/world/world.tscn"


func _boot() -> World:
	var world: World = load(WORLD_SCENE).instantiate()
	add_child_autofree(world)
	return world


func test_session_present_and_offline() -> void:
	var world := _boot()
	var sess := world.session()
	assert_not_null(sess, "session() must return a NetworkSession")
	assert_true(sess is NetworkSession, "session() must be a NetworkSession")
	assert_false(sess.is_active(), "the world must default to OFFLINE")
	assert_true(sess.has_authority(), "offline must count as authoritative (solo host)")


func test_router_and_log_present() -> void:
	var world := _boot()
	assert_not_null(world.router(), "router() must return a CommandRouter")
	assert_true(world.router() is CommandRouter, "router() must be a CommandRouter")
	assert_not_null(world.command_log(), "command_log() must return a CommandLog")
	assert_true(world.command_log() is CommandLog, "command_log() must be a CommandLog")


func test_remote_players_container_present() -> void:
	var world := _boot()
	var container := world.get_node_or_null("RemotePlayers")
	assert_not_null(container, "a RemotePlayers container must exist for avatars")


func test_player_sync_present() -> void:
	var world := _boot()
	var sync := world.get_node_or_null("PlayerSync")
	assert_not_null(sync, "a PlayerSync node must be wired under World")
	assert_true(sync is PlayerSync, "PlayerSync node must be a PlayerSync")


func test_session_panel_in_hud() -> void:
	var world := _boot()
	var panel := world.hud().get_node_or_null("SessionPanel")
	assert_not_null(panel, "the SessionPanel must live under the HUD layer")
	assert_true(panel is SessionPanel, "the HUD child must be a SessionPanel")


func test_player_intents_route_through_router() -> void:
	# Every replicable intent handler must route to a World handler (which calls
	# router.submit). We assert the dig/place/harvest connections target World.
	var world := _boot()
	var p := world.player()
	for sig in [p.dig_requested, p.place_requested, p.harvest_requested]:
		var routed := false
		for conn in sig.get_connections():
			if conn["callable"].get_object() == world:
				routed = true
		assert_true(routed, "intent must route to a World handler (router seam)")


func test_offline_submit_routes_to_bus_and_raises_intensity() -> void:
	# Offline, router.submit must reach the bus, which emits command_executed and
	# raises music intensity. We route a HarvestCommand with a null target (like
	# the music test) rather than a live DigCommand: a real dig calls the voxel
	# tool whose chunks have not streamed in headless. Harvest shares the identical
	# command_executed path but is side-effect free with no target.
	var world := _boot()
	var before: float = world.intensity().level()
	var no_drops: Array[ItemAmount] = []
	world.router().submit(HarvestCommand.new(null, no_drops))
	var after: float = world.intensity().level()
	assert_gt(after, before, "an offline submit via the router must raise intensity")
	# Offline host does not log (only the online host appends to the log).
	assert_eq(world.command_log().size(), 0, "offline must not populate the command log")


func test_rebuild_for_session_reseeds_and_rebuilds_cleanly() -> void:
	# A late-join rebuild with an empty log must reseed the world, rebuild the
	# terrain node fresh, and leave the subsystem graph intact.
	var world := _boot()
	var old_seed: int = world.seed_value
	var new_seed := old_seed + 4242
	world.rebuild_for_session(new_seed, [])
	assert_eq(world.seed_value, new_seed, "rebuild must adopt the new seed")
	var vw := world.voxel_world()
	assert_not_null(vw, "rebuild must re-create the voxel world")
	assert_true(vw is VoxelWorld, "rebuilt terrain must be a VoxelWorld")
	assert_true(vw.is_inside_tree(), "rebuilt terrain must be in the scene tree")
	assert_eq(vw.seed_value, new_seed, "rebuilt terrain must carry the new seed")
	# Flora / blocks containers survive the rebuild (children cleared, node kept).
	assert_not_null(world.flora(), "flora node must survive a rebuild")
	assert_not_null(world.blocks_container(), "blocks container must survive a rebuild")
