## A shadow-wisp enemy — the physical Umbral that wraps an [UmbralAI] brain.
##
## The Umbral is a [CharacterBody3D] that condenses out of the dark. Its visual
## identity is built procedurally in [method setup]: a dark, translucent blob
## body with a bright glowing core (coloured per [CreatureDef]) and an
## [OmniLight3D] so it casts its own sickly glow. It owns a [Health] pool built
## from the def, but registers nothing itself — the [World] integrator registers
## it with the [CombatService] and wires its signals.
##
## Behaviour is split cleanly: the pure [UmbralAI] decides what to do each
## simulation tick (cached from the [SimulationClock]'s [signal ticked]), and
## this node merely applies that decision — gravity and movement in
## [method _physics_process], strikes via [signal attack_landed]. On death it
## plays a short dissolve (core flash + shrink) and then frees itself, announcing
## [signal perished] so the world can award drops and lumen.
class_name Umbral
extends CharacterBody3D

## Emitted on a tick the AI lands an attack while still within attack range.
## [param damage] is the configured [member CreatureDef.attack_damage].
signal attack_landed(damage: float)

## Emitted once the dissolve completes and the node is about to free, so the
## world can award [param def] drops/lumen at the death [param at] position.
signal perished(def: CreatureDef, at: Vector3)

## Seconds the death dissolve (core flash + shrink to zero) takes.
const DISSOLVE_TIME := 0.6
## Body sphere radius before [member CreatureDef.body_scale] is applied.
const BODY_RADIUS := 0.55
## Acceleration blend factor applied to horizontal velocity per physics frame.
const ACCEL := 10.0

## Ferromantic mass exposed to the metal-source protocol (Contract #7).
var metal_mass: float = 0.0

## When true the Umbral holds position (zero horizontal velocity) but keeps
## attacking if the player is in reach. Set via [method set_rooted].
var _rooted: bool = false

var _def: CreatureDef
var _clock: SimulationClock
var _target: Node3D
var _ai: UmbralAI
var _health: Health

## Cached AI decision from the most recent simulation tick.
var _move_dir := Vector3.ZERO
var _wants_attack := false
var _dying := false

# Procedural body parts, built in setup() / _ready().
var _body_mesh: MeshInstance3D
var _core_mesh: MeshInstance3D
var _light: OmniLight3D
var _collision: CollisionShape3D


func _ready() -> void:
	add_to_group("umbrals")


## Configure this Umbral from [param def], wiring its AI, health, and visuals.
##
## [param clock] drives AI decisions (one per [signal SimulationClock.ticked]);
## [param rng] seeds the AI's wander randomness; [param target] is the node the
## wisp hunts (the player). Safe to call before or after the node enters the
## tree — the body is (re)built immediately and the group is ensured.
func setup(
	def: CreatureDef, clock: SimulationClock, rng: RandomNumberGenerator, target: Node3D
) -> void:
	_def = def
	_clock = clock
	_target = target
	_ai = UmbralAI.new(def, rng)
	_health = Health.new(def.max_health)
	_health.died.connect(_on_died)
	if not is_in_group("umbrals"):
		add_to_group("umbrals")
	if def.metal_mass > 0.0:
		metal_mass = def.metal_mass
		if not is_in_group(&"metal_sources"):
			add_to_group(&"metal_sources")
	_build_body()
	if _clock != null and not _clock.ticked.is_connected(_on_tick):
		_clock.ticked.connect(_on_tick)


## The [Health] pool owned by this Umbral (built in [method setup]).
func health() -> Health:
	return _health


## Metal-source protocol (#7): Umbrals are never anchored — they can be flung.
func is_metal_anchored() -> bool:
	return false


## Root or unroot this Umbral (Phase 9 bond_lash status effect).
##
## While rooted the Umbral's movement logic holds position — horizontal
## velocity is clamped to zero each physics frame — but it continues to
## attack the player if they remain within attack range.
func set_rooted(rooted: bool) -> void:
	_rooted = rooted


## The [CreatureDef] this Umbral was configured from.
func definition() -> CreatureDef:
	return _def


# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------


## Cache the AI's decision for this tick; physics applies it each frame until
## the next tick refreshes it.
func _on_tick(tick_index: int) -> void:
	if _dying or _ai == null or _target == null:
		return
	var decision := _ai.tick(global_position, _target.global_position, tick_index)
	_move_dir = decision["move_dir"]
	var attack: bool = decision["attack"]
	if attack and _within_attack_range():
		attack_landed.emit(_def.attack_damage)
	_wants_attack = attack


func _physics_process(delta: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	if not is_on_floor():
		velocity.y -= gravity * delta

	if _dying:
		velocity.x = move_toward(velocity.x, 0.0, _def_speed() * delta * ACCEL)
		velocity.z = move_toward(velocity.z, 0.0, _def_speed() * delta * ACCEL)
		move_and_slide()
		return

	if _rooted:
		# Rooted: hold position (zero horizontal) but gravity + attack still apply.
		velocity.x = move_toward(velocity.x, 0.0, _def_speed() * delta * ACCEL)
		velocity.z = move_toward(velocity.z, 0.0, _def_speed() * delta * ACCEL)
		move_and_slide()
		return

	var target_xz := _move_dir * _def_speed()
	velocity.x = move_toward(velocity.x, target_xz.x, _def_speed() * delta * ACCEL)
	velocity.z = move_toward(velocity.z, target_xz.z, _def_speed() * delta * ACCEL)
	move_and_slide()


func _within_attack_range() -> bool:
	if _target == null:
		return false
	var d := _target.global_position - global_position
	return Vector2(d.x, d.z).length() <= _def.attack_range


func _def_speed() -> float:
	return _def.move_speed if _def != null else 0.0


# ---------------------------------------------------------------------------
# Death / dissolve
# ---------------------------------------------------------------------------


func _on_died() -> void:
	if _dying:
		return
	_dying = true
	if _ai != null:
		_ai.mark_dead()
	if _collision != null:
		_collision.disabled = true
	_move_dir = Vector3.ZERO
	_wants_attack = false
	_play_dissolve()


func _play_dissolve() -> void:
	var death_pos := global_position
	var tween := create_tween()
	tween.set_parallel(true)
	if _core_mesh != null:
		var core_mat := _core_mesh.get_surface_override_material(0) as StandardMaterial3D
		if core_mat != null:
			tween.tween_property(core_mat, "emission_energy_multiplier", 9.0, DISSOLVE_TIME * 0.3)
	tween.tween_property(self, "scale", Vector3.ZERO, DISSOLVE_TIME).set_trans(Tween.TRANS_BACK)
	if _light != null:
		tween.tween_property(_light, "light_energy", 0.0, DISSOLVE_TIME)
	tween.chain().tween_callback(
		func() -> void:
			perished.emit(_def, death_pos)
			queue_free()
	)


# ---------------------------------------------------------------------------
# Procedural body
# ---------------------------------------------------------------------------


## Build (or rebuild) the dark blob body, glowing core, light, and collision
## sized from [member CreatureDef.body_scale] and tinted by its core colour.
func _build_body() -> void:
	for child in [_body_mesh, _core_mesh, _light, _collision]:
		if child != null and is_instance_valid(child):
			child.queue_free()

	var s: float = _def.body_scale if _def != null else 1.0
	var core_color: Color = _def.core_color if _def != null else Color(0.7, 0.3, 1.0)

	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	var body_shape := SphereMesh.new()
	body_shape.radius = BODY_RADIUS * s
	body_shape.height = BODY_RADIUS * 1.5 * s  # squashed blob
	_body_mesh.mesh = body_shape
	_body_mesh.set_surface_override_material(0, _make_body_material(core_color))
	add_child(_body_mesh)

	_core_mesh = MeshInstance3D.new()
	_core_mesh.name = "Core"
	var core_shape := SphereMesh.new()
	core_shape.radius = BODY_RADIUS * 0.4 * s
	core_shape.height = BODY_RADIUS * 0.8 * s
	_core_mesh.mesh = core_shape
	_core_mesh.set_surface_override_material(0, _make_core_material(core_color))
	add_child(_core_mesh)

	_light = OmniLight3D.new()
	_light.name = "CoreLight"
	_light.light_color = core_color
	_light.light_energy = 0.8
	_light.omni_range = 4.0
	_light.shadow_enabled = false
	add_child(_light)

	_collision = CollisionShape3D.new()
	_collision.name = "CollisionShape3D"
	var col_shape := SphereShape3D.new()
	col_shape.radius = BODY_RADIUS * s
	_collision.shape = col_shape
	add_child(_collision)


## Near-black translucent body with a faint rim, tinted toward the core colour.
func _make_body_material(core_color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.02, 0.05, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.9
	mat.rim_enabled = true
	mat.rim = 0.6
	mat.rim_tint = 0.8
	mat.emission_enabled = true
	mat.emission = core_color
	mat.emission_energy_multiplier = 0.15
	return mat


## Bright emissive core glowing in the creature's signature colour.
func _make_core_material(core_color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = core_color
	mat.emission_enabled = true
	mat.emission = core_color
	mat.emission_energy_multiplier = 3.0
	mat.roughness = 0.1
	return mat
