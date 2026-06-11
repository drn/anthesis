class_name StormVisuals
extends Node
## Presentation layer for Resonance Storm weather transitions.
##
## Subscribes to WeatherSystem.weather_changed and drives purely cosmetic
## changes on the environment rig: fog density, moonlight energy, sky tint,
## and a code-built GPUParticles3D wind-streak layer that emits only during a
## storm.  All mutations are presentation-only — no game-state writes.
##
## Expected rig structure (scenes/world/environment.tscn):
##   Node3D "Environment_Rig"
##     WorldEnvironment "WorldEnvironment"   (environment resource)
##     DirectionalLight3D "Moonlight"
##
## Node names are looked up at setup() time and cached.  If either is absent
## (headless / test) the corresponding visual path degrades silently to a no-op.

## Tween duration for calm<->warning and warning<->storm transitions (seconds).
const TRANSITION_SECONDS := 3.0

## Fog density multipliers relative to the calm baseline.
const FOG_MULT_WARNING := 2.5
const FOG_MULT_STORM := 5.0

## Moonlight energy multipliers relative to the calm baseline.
const MOON_MULT_WARNING := 0.6
const MOON_MULT_STORM := 0.35

## Sky nebula tint shift toward bruised violet during warning/storm.
## Applied to nebula_color_a shader parameter on the sky material.
const SKY_WARNING_TINT := Color(0.45, 0.25, 0.70, 1.0)
const SKY_STORM_TINT := Color(0.30, 0.10, 0.55, 1.0)

## GPUParticles3D wind streak settings.
const WIND_PARTICLE_COUNT := 120
const WIND_PARTICLE_LIFETIME := 0.8
const WIND_SPEED_MIN := 18.0
const WIND_SPEED_MAX := 32.0

## Cached references (null when absent from the rig).
var _world_env: WorldEnvironment = null
var _moonlight: DirectionalLight3D = null
var _env_resource: Environment = null

## Cached calm-state baselines (recorded once at setup).
var _baseline_fog_density := 0.0
var _baseline_moon_energy := 1.2
var _baseline_sky_tint := Color(0.1, 0.85, 0.9, 1.0)

## Active tween (kill before starting a new one).
var _tween: Tween = null

## Wind particle system — created in code, emitting only during storm.
var _wind_particles: GPUParticles3D = null

## Last known weather state.
var _current_state: StringName = &"calm"


## Wire to a WeatherSystem duck-typed object and the 3-D environment rig node.
## Both may be null for headless operation.
func setup(weather: Object, environment_rig: Node) -> void:
	if environment_rig != null:
		_world_env = environment_rig.get_node_or_null("WorldEnvironment") as WorldEnvironment
		_moonlight = environment_rig.get_node_or_null("Moonlight") as DirectionalLight3D

		if _world_env != null and _world_env.environment != null:
			_env_resource = _world_env.environment
			_baseline_fog_density = _env_resource.volumetric_fog_density

		if _moonlight != null:
			_baseline_moon_energy = _moonlight.light_energy

		if _env_resource != null:
			var sky_mat := _sky_shader_material()
			if sky_mat != null:
				var a = sky_mat.get_shader_parameter("nebula_color_a")
				if a != null:
					_baseline_sky_tint = a

		_build_wind_particles(environment_rig)

	if weather != null and weather.has_signal("weather_changed"):
		weather.weather_changed.connect(_on_weather_changed)


# ---------------------------------------------------------------------------
# Weather signal handler
# ---------------------------------------------------------------------------


func _on_weather_changed(state: StringName) -> void:
	_current_state = state
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)

	match state:
		&"calm":
			_tween_fog(_baseline_fog_density)
			_tween_moon(_baseline_moon_energy)
			_tween_sky(_baseline_sky_tint)
			_set_wind_emitting(false)
		&"warning":
			_tween_fog(_baseline_fog_density * FOG_MULT_WARNING)
			_tween_moon(_baseline_moon_energy * MOON_MULT_WARNING)
			_tween_sky(SKY_WARNING_TINT)
			_set_wind_emitting(false)
		&"storm":
			_tween_fog(_baseline_fog_density * FOG_MULT_STORM)
			_tween_moon(_baseline_moon_energy * MOON_MULT_STORM)
			_tween_sky(SKY_STORM_TINT)
			_set_wind_emitting(true)


# ---------------------------------------------------------------------------
# Tween helpers — each null-safe on the cached references
# ---------------------------------------------------------------------------


func _tween_fog(target_density: float) -> void:
	if _env_resource == null:
		return
	_tween.tween_method(
		func(v: float) -> void: _env_resource.volumetric_fog_density = v,
		_env_resource.volumetric_fog_density,
		target_density,
		TRANSITION_SECONDS
	)


func _tween_moon(target_energy: float) -> void:
	if _moonlight == null:
		return
	_tween.tween_property(_moonlight, "light_energy", target_energy, TRANSITION_SECONDS)


func _tween_sky(target_tint: Color) -> void:
	var sky_mat := _sky_shader_material()
	if sky_mat == null:
		return
	var from_tint: Color = _baseline_sky_tint
	_tween.tween_method(
		func(v: Color) -> void: sky_mat.set_shader_parameter("nebula_color_a", v),
		from_tint,
		target_tint,
		TRANSITION_SECONDS
	)


# ---------------------------------------------------------------------------
# Wind particles
# ---------------------------------------------------------------------------


func _build_wind_particles(parent: Node) -> void:
	if parent == null:
		return
	_wind_particles = GPUParticles3D.new()
	_wind_particles.name = "StormWindParticles"
	_wind_particles.emitting = false
	_wind_particles.amount = WIND_PARTICLE_COUNT
	_wind_particles.lifetime = WIND_PARTICLE_LIFETIME
	_wind_particles.one_shot = false
	_wind_particles.visibility_range_end = 60.0

	var pm := ParticleProcessMaterial.new()
	# Streaking quads: spawn in a wide slab above the player, hurl sideways.
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(40.0, 10.0, 40.0)
	pm.direction = Vector3(1.0, -0.15, 0.0)
	pm.spread = 12.0
	pm.initial_velocity_min = WIND_SPEED_MIN
	pm.initial_velocity_max = WIND_SPEED_MAX
	pm.gravity = Vector3(0.0, -1.5, 0.0)
	pm.scale_min = 0.04
	pm.scale_max = 0.12
	# Translucent streaks: fade in quickly, hold, then fade out at end of life.
	pm.color = Color(0.75, 0.80, 1.0, 0.55)

	_wind_particles.process_material = pm

	# Use a QuadMesh so particles render as elongated streaks.
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.05, 0.6)
	_wind_particles.draw_pass_1 = mesh

	parent.add_child(_wind_particles)


func _set_wind_emitting(active: bool) -> void:
	if _wind_particles == null:
		return
	_wind_particles.emitting = active


# ---------------------------------------------------------------------------
# Sky material accessor
# ---------------------------------------------------------------------------


func _sky_shader_material() -> ShaderMaterial:
	if _env_resource == null:
		return null
	var sky := _env_resource.sky
	if sky == null:
		return null
	return sky.sky_material as ShaderMaterial
