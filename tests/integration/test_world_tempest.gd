extends GutTest

# ---------------------------------------------------------------------------
# Integration boot test for Phase 9 tempest / weather wiring (contract #6).
#
# Loads world.tscn and asserts the integrator stood up the Resonance Storm
# stack: the Weather + Tempest nodes exist and tick off the clock, the command
# context carries both, the tempest well resolves through the magic gate, and
# the gameplay seams work end-to-end — force_storm + ticking transitions states
# and a storm pulse charges an exposed catcher; inhale converts a charged gem
# and fills the well; Skylash flips the player's gravity_dir and restores it
# after the status expires; Bondlash roots an Umbral.
# ---------------------------------------------------------------------------

const WORLD_SCENE := "res://scenes/world/world.tscn"


func _boot() -> World:
	var world: World = load(WORLD_SCENE).instantiate()
	add_child_autofree(world)
	return world


func _context(world: World) -> WorldContext:
	return world.command_bus().get("_ctx")


func test_weather_and_tempest_nodes_present() -> void:
	var world := _boot()
	var weather := world.get_node_or_null("Weather")
	var tempest := world.get_node_or_null("Tempest")
	assert_not_null(weather, "a Weather node must exist")
	assert_not_null(tempest, "a Tempest node must exist")
	assert_true(weather is WeatherSystem, "Weather must be a WeatherSystem")
	assert_true(tempest is TempestLight, "Tempest must be a TempestLight")


func test_context_carries_tempest_and_weather() -> void:
	var world := _boot()
	var ctx := _context(world)
	assert_true(ctx.tempest is TempestLight, "context must carry the TempestLight")
	assert_true(ctx.weather is WeatherSystem, "context must carry the WeatherSystem")


func test_weather_and_tempest_tick_off_clock() -> void:
	var world := _boot()
	var clock: SimulationClock = world.get_node("SimulationClock")
	var weather: WeatherSystem = world.get_node("Weather")
	var tempest: TempestLight = world.get_node("Tempest")
	assert_true(clock.ticked.is_connected(weather.on_tick), "Weather must tick off the clock")
	assert_true(clock.ticked.is_connected(tempest.on_tick), "Tempest must tick off the clock")


func test_tempest_well_resolves_through_magic_gate() -> void:
	var world := _boot()
	var ctx := _context(world)
	var sky := AbilityRegistry.new().ability(&"sky_lash")
	assert_not_null(sky, "sky_lash ability must load")
	# Empty well: the gate refuses the cast (cannot afford the tempest cost).
	assert_false(ctx.magic.can_cast(sky), "empty tempest well cannot afford a lash")
	ctx.tempest.well().add(TempestLight.CAPACITY)
	assert_true(ctx.magic.can_cast(sky), "a full tempest well affords a lash")


func test_force_storm_pulse_charges_exposed_catcher() -> void:
	var world := _boot()
	var weather: WeatherSystem = world.get_node("Weather")
	# A catcher with one dun gem, placed high in open air so the sky-exposure ray
	# hits nothing (no terrain above it).
	var catcher: StormCatcher = load("res://scenes/props/storm_catcher.tscn").instantiate()
	world.add_child(catcher)
	catcher.global_position = Vector3(0.0, 400.0, 0.0)
	catcher.deposit(1)
	assert_eq(catcher.dun_count(), 1, "catcher holds one dun gem")

	# Drive the weather machine into a storm and fire one pulse.
	weather.force_storm()
	# 1 calm tick -> warning(10), 10 warning ticks -> storm, then storm pulses
	# every PULSE_INTERVAL ticks; run enough to clear the first pulse.
	for t in range(1, 1 + 10 + WeatherSystem.PULSE_INTERVAL + 1):
		weather.on_tick(t)
	assert_eq(weather.state(), &"storm", "weather entered the storm")
	assert_eq(catcher.charged_count(), 1, "an exposed catcher charged one gem on the pulse")
	assert_eq(catcher.dun_count(), 0, "the dun gem was converted")
	catcher.queue_free()


func test_inhale_converts_gem_and_fills_well() -> void:
	var world := _boot()
	var ctx := _context(world)
	world.inventory().add(&"charged_gem", 1)
	var before := ctx.tempest.well().current()
	world.command_bus().execute(InhaleCommand.new())
	assert_eq(world.inventory().count_of(&"charged_gem"), 0, "the charged gem was consumed")
	assert_eq(world.inventory().count_of(&"dun_gem"), 1, "a spent dun gem returned")
	assert_almost_eq(
		ctx.tempest.well().current(),
		before + TempestLight.INHALE_CHARGE,
		0.001,
	)


func test_sky_lash_flips_gravity_then_restores() -> void:
	var world := _boot()
	var ctx := _context(world)
	var player := world.player()
	assert_eq(player.gravity_dir, Vector3.DOWN, "player starts under normal gravity")
	ctx.tempest.well().add(TempestLight.CAPACITY)
	var sky := AbilityRegistry.new().ability(&"sky_lash")
	world.command_bus().execute(CastCommand.new(sky, Vector3.ZERO))
	assert_ne(player.gravity_dir, Vector3.DOWN, "Skylash redirected the player's gravity")
	assert_eq(player.up_direction, -player.gravity_dir, "up_direction tracks gravity_dir")

	# Tick past the lash duration (magnitude seconds * 10 ticks/s) so the status
	# expires and gravity restores.
	var status: StatusEffectSystem = world.get_node("StatusEffects")
	var duration := int(sky.magnitude * 10.0)
	for t in range(1, duration + 2):
		status.on_tick(t)
	assert_eq(player.gravity_dir, Vector3.DOWN, "gravity restores after the lash expires")


func test_bond_lash_roots_a_nearby_umbral() -> void:
	var world := _boot()
	var ctx := _context(world)
	var status: StatusEffectSystem = world.get_node("StatusEffects")
	var clock: SimulationClock = world.get_node("SimulationClock")
	# Spawn an Umbral right at the player's feet so it sits inside bond_lash range.
	var player := world.player()
	player.global_position = Vector3.ZERO
	var umbral: Umbral = load("res://scenes/creatures/umbral.tscn").instantiate()
	world.add_child(umbral)
	var def := CreatureRegistry.new().creatures()[0]
	umbral.setup(def, clock, RandomNumberGenerator.new(), player)
	umbral.global_position = Vector3(0.5, 0.0, 0.0)

	ctx.tempest.well().add(TempestLight.CAPACITY)
	var bond := AbilityRegistry.new().ability(&"bond_lash")
	world.command_bus().execute(CastCommand.new(bond, umbral.global_position))
	assert_true(
		status.has(umbral.get_instance_id(), &"rooted"), "Bondlash rooted the nearby Umbral"
	)
	umbral.queue_free()
