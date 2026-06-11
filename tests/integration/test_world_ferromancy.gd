extends GutTest

# ---------------------------------------------------------------------------
# Integration boot test for Phase 8 ferromancy wiring (contract #12).
#
# Loads world.tscn and asserts the integrator stood up the metallurgy stack:
# the StatusEffects + Channels nodes exist and tick off the clock, the command
# context carries the new services, the metal reserves resolve through the magic
# gate, the channel defs are installed, and the gameplay seams work end-to-end —
# granting flakes then casting Ferropush at a spawned deposit moves the player,
# and toggling Vigor sets the player's speed_scale through the command bus.
# ---------------------------------------------------------------------------

const WORLD_SCENE := "res://scenes/world/world.tscn"


func _boot() -> World:
	var world: World = load(WORLD_SCENE).instantiate()
	add_child_autofree(world)
	return world


func _context(world: World) -> WorldContext:
	return world.command_bus().get("_ctx")


func test_status_and_channel_nodes_present() -> void:
	var world := _boot()
	var status := world.get_node_or_null("StatusEffects")
	var channels := world.get_node_or_null("Channels")
	assert_not_null(status, "a StatusEffects node must exist")
	assert_not_null(channels, "a Channels node must exist")
	assert_true(status is StatusEffectSystem, "StatusEffects must be a StatusEffectSystem")
	assert_true(channels is ChannelSystem, "Channels must be a ChannelSystem")


func test_context_carries_ferromancy_services() -> void:
	var world := _boot()
	var ctx := _context(world)
	assert_true(ctx.status is StatusEffectSystem, "context must carry the StatusEffectSystem")
	assert_true(ctx.channels is ChannelSystem, "context must carry the ChannelSystem")
	assert_true(ctx.metal_reserves is MetalReserves, "context must carry the MetalReserves")
	assert_true(ctx.coin_spawn.is_valid(), "context must carry a valid coin_spawn Callable")


func test_metal_reserves_track_four_kinds() -> void:
	var world := _boot()
	var reserves: MetalReserves = _context(world).metal_reserves
	assert_eq(reserves.kinds(), [&"iron", &"pewter", &"steel", &"tin"], "four metal kinds tracked")
	for kind in [&"iron", &"steel", &"pewter", &"tin"]:
		assert_eq(reserves.well(kind).current(), 0.0, "%s starts empty" % kind)


func test_channels_tick_off_clock() -> void:
	var world := _boot()
	var clock: SimulationClock = world.get_node("SimulationClock")
	var channels: ChannelSystem = world.get_node("Channels")
	var status: StatusEffectSystem = world.get_node("StatusEffects")
	# Both per-tick subsystems must be connected to the clock.
	assert_true(clock.ticked.is_connected(channels.on_tick), "Channels must tick off the clock")
	assert_true(clock.ticked.is_connected(status.on_tick), "StatusEffects must tick off the clock")


func test_vigor_toggle_through_bus_sets_speed_scale() -> void:
	var world := _boot()
	var ctx := _context(world)
	# Grant pewter flakes so the channel can ensure its first tick of drain.
	world.inventory().add(&"pewter_flakes", 4)
	assert_eq(world.player().speed_scale, 1.0, "player starts at base speed")
	world.command_bus().execute(ToggleChannelCommand.new(&"vigor"))
	assert_true(ctx.channels.is_active(&"vigor"), "vigor channel is lit after toggle")
	assert_eq(world.player().speed_scale, 1.4, "vigor raises player speed_scale to 1.4")
	assert_true(
		ctx.status.has(world.player().get_instance_id(), &"vigor"),
		"player carries the vigor status",
	)
	# Toggling off restores base speed.
	world.command_bus().execute(ToggleChannelCommand.new(&"vigor"))
	assert_false(ctx.channels.is_active(&"vigor"), "vigor channel closes on second toggle")
	assert_eq(world.player().speed_scale, 1.0, "speed restored after vigor closes")


func test_ferro_push_at_deposit_moves_player() -> void:
	var world := _boot()
	# Spawn a heavy anchored deposit dead ahead of the player's camera so the
	# resolve maps to a player impulse (anchored source pushes the Ferromancer).
	var player := world.player()
	player.global_position = Vector3.ZERO
	var camera := player.get_node("Camera3D") as Camera3D
	var forward := -camera.global_transform.basis.z
	var deposit := load("res://scenes/props/metal_deposit_lodestone.tscn").instantiate()
	world.add_child(deposit)
	deposit.global_position = camera.global_position + forward * 6.0
	# Grant steel flakes so Ferropush can pay its cost from the reserve.
	world.inventory().add(&"steel_flakes", 4)
	var push := AbilityRegistry.new().ability(&"ferro_push")
	assert_not_null(push, "ferro_push ability must load")
	player.velocity = Vector3.ZERO
	world.command_bus().execute(CastCommand.new(push, Vector3.ZERO))
	assert_gt(player.velocity.length(), 0.0, "Ferropush off an anchor moves the player")
	deposit.queue_free()


func test_ferro_push_with_no_source_is_inert() -> void:
	var world := _boot()
	# No metal sources near the player: the cast finds nothing and spends nothing.
	world.player().global_position = Vector3(500.0, 500.0, 500.0)
	world.inventory().add(&"steel_flakes", 4)
	var reserves: MetalReserves = _context(world).metal_reserves
	var push := AbilityRegistry.new().ability(&"ferro_push")
	world.player().velocity = Vector3.ZERO
	world.command_bus().execute(CastCommand.new(push, Vector3.ZERO))
	assert_eq(world.player().velocity.length(), 0.0, "no source -> player does not move")
	# The cast failed on no_effect, so nothing was spent: the well still holds the
	# single flake's charge (30) the cost-gate top-up swallowed before the effect.
	assert_eq(reserves.well(&"steel").current(), 30.0, "topped-up steel reserve unspent")
