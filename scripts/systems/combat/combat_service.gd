## Registry and damage router for every combatant in the world.
##
## CombatService is the seam between combat commands (which name a target by id)
## and the [Health] pools plus scene nodes that realize them. Systems register a
## combatant with its instance id, a [Health], and an optional [Node3D];
## [DamageCommand] then routes hits here by id. Keeping the id→(health, node)
## map in one service means commands never reach into the scene tree, matching
## the project's command-layer rule for world mutations.
##
## IDs follow the [code]node.get_instance_id()[/code] convention so callers can
## resolve a collider hit straight to its combatant. Unknown ids are tolerated
## everywhere (a combatant may despawn between a hit being queued and applied),
## so every lookup and damage call is a safe no-op when the id is absent.
class_name CombatService
extends RefCounted

## Emitted after damage is applied to a registered combatant. Reports the
## target id and the damage actually dealt (post-clamp), so presentation can
## flash cores or play hit reactions without re-deriving the amount.
signal damage_applied(target_id: int, amount: float)

var _health_by_id: Dictionary = {}
var _node_by_id: Dictionary = {}


## Register a combatant under [param id] with its [param health] and optional
## [param node]. Re-registering the same id overwrites the prior entry.
func register(id: int, health: Health, node: Node3D = null) -> void:
	_health_by_id[id] = health
	if node != null:
		_node_by_id[id] = node


## Remove the combatant registered under [param id]. Safe if [param id] is
## unknown.
func unregister(id: int) -> void:
	_health_by_id.erase(id)
	_node_by_id.erase(id)


## The [Health] registered for [param id], or null when unknown.
func health_of(id: int) -> Health:
	return _health_by_id.get(id, null)


## The [Node3D] registered for [param id], or null when none was provided.
func node_of(id: int) -> Node3D:
	return _node_by_id.get(id, null)


## Apply [param amount] of damage to the combatant [param target_id], returning
## the damage actually dealt.
##
## A no-op returning 0.0 when [param target_id] is unknown. Otherwise damages
## the [Health], and — when a registered node is a [CharacterBody3D] — adds the
## [param knockback] vector to its velocity so hits both hurt and shove. Emits
## [signal damage_applied] with the dealt amount when any damage landed.
func apply_damage(target_id: int, amount: float, knockback: Vector3 = Vector3.ZERO) -> float:
	var health: Health = _health_by_id.get(target_id, null)
	if health == null:
		return 0.0
	var dealt := health.take_damage(amount)
	if knockback != Vector3.ZERO:
		var node: Node3D = _node_by_id.get(target_id, null)
		if node is CharacterBody3D:
			(node as CharacterBody3D).velocity += knockback
	if dealt > 0.0:
		damage_applied.emit(target_id, dealt)
	return dealt
