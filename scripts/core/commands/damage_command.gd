## Deals damage to a combatant through the [CombatService].
##
## DamageCommand is the authoritative entry point for any hit — a player strike,
## an Umbral's contact attack, or a future spell. It never touches a [Health] or
## scene node directly; it carries a target id, an amount, and an optional
## knockback, and routes them through [member WorldContext.combat] so all combat
## mutations pass through the command layer like every other world change.
##
## When the target currently holds the [code]&"vigor"[/code] status effect
## (pewter burning), incoming damage is reduced by [constant VIGOR_DAMAGE_MULT]
## before being forwarded to combat. Knockback is unaffected.
##
## When no [CombatService] is wired (legacy / unit-test contexts) the command is
## a silent no-op, mirroring the other commands' tolerance of a sparse context.
class_name DamageCommand
extends WorldCommand

## Incoming damage multiplier applied when the target is burning pewter (vigor).
const VIGOR_DAMAGE_MULT := 0.7

var _target_id: int
var _amount: float
var _knockback: Vector3


## Capture the [param target_id] to hit, the [param amount] of damage, and an
## optional [param knockback] impulse to add to the target's velocity.
func _init(target_id: int, amount: float, knockback := Vector3.ZERO) -> void:
	_target_id = target_id
	_amount = amount
	_knockback = knockback


## Route the hit through [member WorldContext.combat].
##
## Silently does nothing when no combat service is wired. Reduces damage by
## [constant VIGOR_DAMAGE_MULT] when the target holds the [code]&"vigor"[/code]
## status effect; knockback is unaffected.
func apply(ctx: WorldContext) -> void:
	if ctx.combat == null:
		return
	var amount := _amount
	if ctx.status != null and ctx.status.has(_target_id, &"vigor"):
		amount *= VIGOR_DAMAGE_MULT
	ctx.combat.apply_damage(_target_id, amount, _knockback)
