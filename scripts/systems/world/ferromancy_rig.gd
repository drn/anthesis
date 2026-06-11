## Phase 8 ferromancy wiring extracted from [World] to keep that integrator hub
## lean. The rig owns the realized behaviour of the metallurgy systems: the two
## sustained-burn channel definitions (Vigor, Keensight) and the Ferropull /
## Ferropush ability effects. It holds no state of its own beyond references to
## the World-owned collaborators it drives.
##
## World composes one rig in its build phase, registers [method ferro_pull] /
## [method ferro_push] as ability effects, and calls [method install_channels].
## Closures read the player lazily (it may not exist at install time) and tolerate
## a headless run with no [WorldEnvironment].
class_name FerromancyRig
extends RefCounted

## Player movement multiplier while Vigor (pewter) burns.
const VIGOR_SPEED_SCALE := 1.4
## Drain (charge / tick) for each channel.
const VIGOR_DRAIN := 0.25
const KEENSIGHT_DRAIN := 0.1
## Over-burn crash: a slow after Vigor depletes mid-burn, in ticks + its scale.
const PEWTER_DRAG_TICKS := 100
const PEWTER_DRAG_SPEED_SCALE := 0.6
## Keensight (tin) brightens the world's ambient light by this factor while lit.
const KEENSIGHT_AMBIENT_BOOST := 1.6
## Upward lift added to a Ferropull player impulse so ground friction can't eat it.
const FERRO_PULL_LIFT := 2.0

var _world: Node3D
var _status: StatusEffectSystem
var _combat: CombatService


## Bind the World-owned collaborators the rig drives. [param world] supplies the
## scene tree (group queries, environment lookup) and the live player via
## [method player].
func setup(world: Node3D, status: StatusEffectSystem, combat: CombatService) -> void:
	_world = world
	_status = status
	_combat = combat


## Install the Vigor and Keensight channel definitions into [param channels].
func install_channels(channels: ChannelSystem) -> void:
	(
		channels
		. install(
			&"vigor",
			{
				"resource_kind": &"pewter",
				"drain_per_tick": VIGOR_DRAIN,
				"on_start": _vigor_on_start,
				"on_stop": _vigor_on_stop,
			}
		)
	)
	(
		channels
		. install(
			&"keensight",
			{
				"resource_kind": &"tin",
				"drain_per_tick": KEENSIGHT_DRAIN,
				"on_start": _keensight_on_start,
				"on_stop": _keensight_on_stop,
			}
		)
	)


## Ferropull ability effect — Callable(ability, target) -> bool for World to wire.
func ferro_pull(ability: AbilityDef, _target: Vector3) -> bool:
	return _resolve_ferro(ability.magnitude, true)


## Ferropush ability effect — Callable(ability, target) -> bool for World to wire.
func ferro_push(ability: AbilityDef, _target: Vector3) -> bool:
	return _resolve_ferro(ability.magnitude, false)


# ---------------------------------------------------------------------------
# Channel boons / teardowns
# ---------------------------------------------------------------------------


func _player() -> Player:
	return _world.get_node_or_null("Player") as Player if _world != null else null


## Vigor lit: hold an indefinite vigor status and scale the player faster.
func _vigor_on_start() -> void:
	var p := _player()
	if p == null:
		return
	_status.apply(
		p.get_instance_id(),
		&"vigor",
		0,
		func() -> void: p.speed_scale = VIGOR_SPEED_SCALE,
		func() -> void: p.speed_scale = 1.0,
	)


## Vigor closed: drop the vigor status. A depletion (vs a manual toggle-off)
## crashes the player with a timed "pewter drag" slow.
func _vigor_on_stop(reason: StringName) -> void:
	var p := _player()
	if p == null:
		return
	_status.clear(p.get_instance_id(), &"vigor")
	if reason == &"depleted":
		_status.apply(
			p.get_instance_id(),
			&"pewter_drag",
			PEWTER_DRAG_TICKS,
			func() -> void: p.speed_scale = PEWTER_DRAG_SPEED_SCALE,
			func() -> void: p.speed_scale = 1.0,
		)


## Keensight lit: hold an indefinite keensight status and brighten the world.
func _keensight_on_start() -> void:
	var p := _player()
	if p == null:
		return
	_status.apply(
		p.get_instance_id(),
		&"keensight",
		0,
		func() -> void: _set_ambient_scale(KEENSIGHT_AMBIENT_BOOST),
		func() -> void: _set_ambient_scale(1.0 / KEENSIGHT_AMBIENT_BOOST),
	)


## Keensight closed: drop the keensight status (its on_expire restores ambient).
func _keensight_on_stop(_reason: StringName) -> void:
	var p := _player()
	if p == null:
		return
	_status.clear(p.get_instance_id(), &"keensight")


## Multiply the world's ambient light energy, tolerating a headless run with no
## WorldEnvironment (the lookup simply finds nothing and the call is a no-op).
func _set_ambient_scale(factor: float) -> void:
	var env := _find_world_environment()
	if env == null or env.environment == null:
		return
	env.environment.ambient_light_energy *= factor


## Find the first [WorldEnvironment] under the world subtree, or null.
func _find_world_environment() -> WorldEnvironment:
	if _world == null:
		return null
	for child in _world.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
		var nested := child.find_children("", "WorldEnvironment", true, false)
		if not nested.is_empty():
			return nested[0] as WorldEnvironment
	return null


# ---------------------------------------------------------------------------
# Ferropull / Ferropush physics application
# ---------------------------------------------------------------------------


## Shared Ferropull/Ferropush body: aim from the player's camera, pick the metal
## source in the cone, resolve impulses, and apply them. Returns false (spends
## nothing) when nothing is in the cone, so the rule gate refunds the cast.
func _resolve_ferro(magnitude: float, pull: bool) -> bool:
	var p := _player()
	if p == null:
		return false
	var camera := p.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return false
	var origin := camera.global_position
	var aim := -camera.global_transform.basis.z
	var candidates := _world.get_tree().get_nodes_in_group(&"metal_sources")
	var source := FerroKinetics.select_source(origin, aim, candidates)
	if source == null:
		return false
	var mass: float = source.metal_mass if "metal_mass" in source else 1.0
	var anchored: bool = source.has_method("is_metal_anchored") and source.is_metal_anchored()
	var result := FerroKinetics.resolve(
		origin, source.global_position, mass, anchored, magnitude, pull
	)
	var player_impulse: Vector3 = result["player_impulse"]
	var source_impulse: Vector3 = result["source_impulse"]
	if player_impulse != Vector3.ZERO:
		if pull:
			player_impulse += Vector3.UP * FERRO_PULL_LIFT
		p.velocity += player_impulse
	if source_impulse != Vector3.ZERO:
		_apply_source_impulse(source, source_impulse)
	return true


## Route a source impulse to the right body type: a RigidBody3D coin takes a
## direct central impulse; a registered CharacterBody3D Umbral takes the impulse
## as knockback through the combat service (zero damage — this is a shove).
func _apply_source_impulse(source: Node3D, impulse: Vector3) -> void:
	if source is RigidBody3D:
		(source as RigidBody3D).apply_central_impulse(impulse)
	elif source is CharacterBody3D:
		_combat.apply_damage(source.get_instance_id(), 0.0, impulse)
