## Casts a magic ability through the [MagicSystem] rule gate.
##
## CastCommand is the authoritative entry point for casting. It never applies an
## effect directly; instead it looks up the effect [Callable] registered for the
## ability's [member AbilityDef.kind] in [member WorldContext.ability_effects] and
## hands it to [method MagicSystem.try_cast], which enforces cooldown and cost.
##
## When no effect is installed for the ability's kind, the cast is still routed
## through the rule gate with an effect that reports failure, so the well is never
## charged and [MagicSystem] emits cast_failed(&"no_effect"). When [member
## WorldContext.magic] is null (legacy / unit-test contexts) the command is a
## silent no-op.
class_name CastCommand
extends WorldCommand

var _ability: AbilityDef
var _target: Vector3


## Capture the [param ability] to cast and its world-space [param target].
func _init(ability: AbilityDef, target: Vector3) -> void:
	_ability = ability
	_target = target


## Route the cast through [member WorldContext.magic].
##
## Silently does nothing when no magic system is wired. Looks up the effect for
## the ability's kind; if absent, the rule gate still runs with a failing effect
## so the no_effect path is deterministic and nothing is spent.
##
## When [member WorldContext.metal_reserves] is wired and the ability spends a
## metal kind, auto-swallows flakes from inventory to top up reserves before the
## cost gate runs, so a player with flakes but low reserves can still cast.
func apply(ctx: WorldContext) -> void:
	if ctx.metal_reserves != null and _ability != null:
		ctx.metal_reserves.ensure_for_cost(_ability, ctx.inventory)
	if ctx.magic == null:
		return
	if _ability == null:
		return
	var effect: Variant = ctx.ability_effects.get(_ability.kind, null)
	if effect == null or not (effect is Callable) or not (effect as Callable).is_valid():
		ctx.magic.try_cast(_ability, func() -> bool: return false)
		return
	var bound_effect: Callable = effect
	ctx.magic.try_cast(_ability, func() -> bool: return bool(bound_effect.call(_ability, _target)))
