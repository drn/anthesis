## The rule gate for all magic casts — Sanderson's First Law made executable.
##
## MagicSystem owns the deterministic cost/cooldown contract every ability obeys.
## A cast is gated in a fixed order: cooldown first, then affordability, then the
## effect itself. The effect [Callable] reports whether it actually did anything;
## only a truthy effect spends lumen and records the cooldown. Because nothing is
## spent until the effect succeeds, a failed effect refunds nothing — there is
## nothing to refund. This keeps casts consistent and replayable: same tick, same
## well, same ability always yields the same outcome.
##
## Cooldowns are keyed by [member AbilityDef.id] and measured in simulation ticks
## supplied by an injected [Callable] (the [SimulationClock]'s current tick), so
## the system never reads wall-clock time and stays deterministic under replay.
class_name MagicSystem
extends RefCounted

## Emitted after a cast fully succeeds (effect ran, lumen spent, cooldown armed).
signal cast_succeeded(ability: AbilityDef)
## Emitted when a cast is rejected. [param reason] is one of
## &"cooldown", &"cost", or &"no_effect".
signal cast_failed(ability: AbilityDef, reason: StringName)

var _well: LumenWell
var _clock_tick: Callable
## Maps ability id -> the tick at which it was last cast successfully.
var _last_cast: Dictionary = {}


## Construct with the lumen [param well] and a [param clock_tick] Callable that
## returns the current simulation tick as an int.
func _init(well: LumenWell, clock_tick: Callable) -> void:
	_well = well
	_clock_tick = clock_tick


## True when [param ability] is off cooldown and the well can afford its cost.
func can_cast(ability: AbilityDef) -> bool:
	return cooldown_remaining(ability) <= 0 and _well.can_afford(ability.lumen_cost)


## Ticks remaining before [param ability] may be cast again; 0 when ready.
##
## Returns 0 if the ability has never been cast. The result is clamped at 0 so a
## long-idle ability never reports a negative cooldown.
func cooldown_remaining(ability: AbilityDef) -> int:
	if not _last_cast.has(ability.id):
		return 0
	var elapsed: int = _current_tick() - int(_last_cast[ability.id])
	var remaining: int = ability.cooldown_ticks - elapsed
	return maxi(remaining, 0)


## Attempt to cast [param ability], running [param effect] only if the rules pass.
##
## Order is fixed and deterministic:
## 1. cooldown — if still cooling down, emit cast_failed(&"cooldown") and stop;
## 2. cost — if the well cannot afford it, emit cast_failed(&"cost") and stop;
## 3. effect — call [param effect]; it returns whether it actually acted.
##    On a falsey result, emit cast_failed(&"no_effect") and spend nothing.
##    On a truthy result, spend the lumen, record the cast tick, and emit
##    cast_succeeded.
##
## Returns true only when the cast fully succeeds.
func try_cast(ability: AbilityDef, effect: Callable) -> bool:
	if cooldown_remaining(ability) > 0:
		cast_failed.emit(ability, &"cooldown")
		return false
	if not _well.can_afford(ability.lumen_cost):
		cast_failed.emit(ability, &"cost")
		return false
	var acted: bool = bool(effect.call())
	if not acted:
		cast_failed.emit(ability, &"no_effect")
		return false
	_well.spend(ability.lumen_cost)
	_last_cast[ability.id] = _current_tick()
	cast_succeeded.emit(ability)
	return true


func _current_tick() -> int:
	return int(_clock_tick.call())
