## Phase 9 tempest/weather wiring extracted from [World] to keep that integrator
## hub under its line ceiling, mirroring [FerromancyRig]'s pattern.
##
## The rig owns the realized behaviour of the Resonance Storm systems: it stands
## up the [WeatherSystem] scheduler, the [TempestLight] held-light pool, and the
## [StormVisuals] presentation layer; routes the storm-pulse economy (sky-exposure
## raycasts → player exposure damage + storm-catcher charging); and realizes the
## two Tempestlight ability effects (Skylash, Bondlash). It holds no state beyond
## references to the World-owned collaborators it drives.
##
## World composes one rig in its build phase, calls [method build] once the
## player, clock, status tracker, health pool, router, session, intensity model
## and HUD all exist, then registers [method sky_lash] / [method bond_lash] as
## ability effects and publishes [method weather] / [method tempest] on the
## [WorldContext]. Closures read the player lazily where they can, tolerating a
## headless run with no environment rig.
class_name TempestRig
extends RefCounted

## Storm exposure damage dealt to the player per storm pulse while sky-exposed.
const STORM_EXPOSURE_DAMAGE := 3.0
## Range (metres) for the speed boon entry the tempest status drives.
const TEMPEST_SPEED_MOD_ID := &"tempest"
## How far up the sky-exposure ray is cast from a node's origin (metres).
const SKY_RAY_LIFT := 0.5
const SKY_RAY_HEIGHT := 200.0
## OmniLight range on the player's tempest glow (metres).
const GLOW_RANGE := 7.0
## Bondlash search radius (metres) for an Umbral near the cast target.
const BOND_LASH_RANGE := 2.0

var _world: World
var _clock: SimulationClock
var _player: Player
var _status: StatusEffectSystem
var _player_health: Health
var _router: CommandRouter
var _session: NetworkSession
var _intensity: IntensityModel
var _hud: Object

var _weather: WeatherSystem
var _tempest: TempestLight
var _storm_visuals: StormVisuals
var _glow: OmniLight3D


## Stand up and wire every Phase 9 weather/tempest subsystem.
##
## [param world] is the integrator hub; the rig pulls the player, router, session,
## intensity model, player health and HUD from its public getters. [param clock]
## drives the per-tick economy; [param status] backs the tempest/rooted statuses;
## [param env_rig] is the [code]Environment_Rig[/code] node the [StormVisuals]
## tweens; [param context] is published onto (tempest, weather, the two lash
## effects); [param speed_modifier] is World's speed-mod table seam.
func build(
	world: World,
	clock: SimulationClock,
	world_seed: WorldSeed,
	status: StatusEffectSystem,
	env_rig: Node,
	context: WorldContext,
	speed_modifier: Callable
) -> void:
	_world = world
	_clock = clock
	_player = world.player()
	_status = status
	_player_health = world.player_health()
	_router = world.router()
	_session = world.session()
	_intensity = world.intensity()
	_hud = world.hud()

	_build_weather(world_seed)
	_build_tempest(speed_modifier)
	_build_storm_visuals(env_rig)

	# Publish onto the context + register the lash effects (MagicSystem resolves
	# ability_effects lazily) + bind the HUD meter.
	context.tempest = _tempest
	context.weather = _weather
	context.ability_effects[&"sky_lash"] = sky_lash
	context.ability_effects[&"bond_lash"] = bond_lash
	if _hud != null and _hud.has_method("bind_tempest"):
		_hud.bind_tempest(_tempest)


## The weather state machine (drives storm scheduling). Published on WorldContext.
func weather() -> WeatherSystem:
	return _weather


## The held-light pool (drives inhale, leak, regen, speed/glow). On WorldContext.
func tempest() -> TempestLight:
	return _tempest


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------


func _build_weather(world_seed: WorldSeed) -> void:
	_weather = WeatherSystem.new()
	_weather.name = "Weather"
	_world.add_child(_weather)
	_weather.setup(world_seed.derive("weather"))
	_clock.ticked.connect(_weather.on_tick)
	_weather.weather_changed.connect(_on_weather_changed)
	_weather.storm_pulse.connect(_on_storm_pulse)


func _build_tempest(speed_modifier: Callable) -> void:
	_tempest = TempestLight.new()
	_tempest.name = "Tempest"
	_world.add_child(_tempest)

	# A glow parented to the player, driven by the pool's fill ratio.
	_glow = OmniLight3D.new()
	_glow.name = "TempestGlow"
	_glow.light_color = Color(0.85, 0.78, 1.0, 1.0)
	_glow.omni_range = GLOW_RANGE
	_glow.light_energy = 0.0
	_glow.shadow_enabled = false
	_player.add_child(_glow)

	# The status apply/expire drive World's speed-mod table for the &"tempest"
	# entry: active → SPEED_BONUS, cleared → 1.0.
	var tempest_speed := func(active: bool) -> void:
		if speed_modifier.is_valid():
			speed_modifier.call(TEMPEST_SPEED_MOD_ID, TempestLight.SPEED_BONUS if active else 1.0)
	_tempest.setup(
		_status,
		_player_health,
		func() -> int: return _player.get_instance_id(),
		_glow,
		tempest_speed
	)
	_clock.ticked.connect(_tempest.on_tick)


func _build_storm_visuals(env_rig: Node) -> void:
	_storm_visuals = StormVisuals.new()
	_storm_visuals.name = "StormVisuals"
	_world.add_child(_storm_visuals)
	_storm_visuals.setup(_weather, env_rig)


# ---------------------------------------------------------------------------
# Weather signal handlers
# ---------------------------------------------------------------------------


## A weather transition: feed the soundtrack heat and surface the HUD banner.
func _on_weather_changed(state: StringName) -> void:
	if _intensity != null:
		if state == &"warning":
			_intensity.on_event(&"storm_warning")
		elif state == &"storm":
			_intensity.on_event(&"storm")
	if _hud != null and _hud.has_method("show_storm_banner"):
		_hud.show_storm_banner(state)


## A storm pulse fired (host-authoritative): batter the player if exposed and
## charge any sky-exposed storm catcher. [param _pulse_index] is informational.
func _on_storm_pulse(_pulse_index: int) -> void:
	if _session != null and not _session.has_authority():
		return
	if _player != null and _is_sky_exposed(_player):
		_router.submit(
			DamageCommand.new(_player.get_instance_id(), STORM_EXPOSURE_DAMAGE, Vector3.ZERO)
		)
	for catcher in _world.get_tree().get_nodes_in_group(&"storm_catchers"):
		if catcher is Node3D and _is_sky_exposed(catcher):
			catcher.charge_one()


## Whether [param node] has open sky above it: cast a ray from just above its
## origin straight up; exposed when nothing is hit (the node itself excluded).
func _is_sky_exposed(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var space := node.get_world_3d().direct_space_state
	var from := node.global_position + Vector3.UP * SKY_RAY_LIFT
	var to := node.global_position + Vector3.UP * SKY_RAY_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [node.get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty()


# ---------------------------------------------------------------------------
# Ability effects (Callable(ability, target) -> bool for World to register)
# ---------------------------------------------------------------------------


## Skylash — snap the player's personal gravity to the nearest cardinal axis of
## their camera forward for [code]int(magnitude * 10)[/code] ticks, then restore.
##
## Re-casting refreshes the window: [method Player.set_gravity_dir] is called
## immediately (the status apply does not re-run on_apply for an existing effect,
## so the snap must happen here every cast).
func sky_lash(ability: AbilityDef, _target: Vector3) -> bool:
	if _player == null:
		return false
	var camera := _player.get_node_or_null("Camera3D") as Camera3D
	var aim := -camera.global_transform.basis.z if camera != null else Vector3.DOWN
	var axis := LashMath.snap_axis(aim)
	_player.set_gravity_dir(axis)
	var duration := int(ability.magnitude * 10.0)
	var pid := _player.get_instance_id()
	_status.apply(
		pid, &"sky_lash", duration, func() -> void: pass, func() -> void: _restore_gravity()
	)
	return true


## Bondlash — root the nearest Umbral within [constant BOND_LASH_RANGE] of the
## target for [code]int(magnitude * 10)[/code] ticks. Returns false (no spend)
## when no Umbral is in reach, so the rule gate refunds the cast.
func bond_lash(ability: AbilityDef, target: Vector3) -> bool:
	var umbral := _nearest_umbral(target)
	if umbral == null:
		return false
	var duration := int(ability.magnitude * 10.0)
	var uid := umbral.get_instance_id()
	_status.apply(
		uid,
		&"rooted",
		duration,
		func() -> void: _set_umbral_rooted(uid, true),
		func() -> void: _set_umbral_rooted(uid, false)
	)
	return true


# ---------------------------------------------------------------------------
# Effect helpers
# ---------------------------------------------------------------------------


func _restore_gravity() -> void:
	if _player != null and is_instance_valid(_player):
		_player.set_gravity_dir(Vector3.DOWN)


func _nearest_umbral(target: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist := BOND_LASH_RANGE
	for node in _world.get_tree().get_nodes_in_group(&"umbrals"):
		if not (node is Node3D):
			continue
		var dist := (node as Node3D).global_position.distance_to(target)
		if dist <= best_dist:
			best_dist = dist
			best = node as Node3D
	return best


## Root/unroot an Umbral by instance id, guarding against a despawned target.
func _set_umbral_rooted(umbral_id: int, rooted: bool) -> void:
	var node := instance_from_id(umbral_id)
	if node != null and is_instance_valid(node) and node.has_method("set_rooted"):
		node.set_rooted(rooted)
