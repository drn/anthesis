## Tick-driven, paired-callable status effects on game entities.
##
## A status effect is a named, time-boxed state on a target (keyed by its instance
## id): vigor, keensight, pewter_drag. Applying an effect runs its [code]on_apply[/code]
## once; when it expires — by countdown or explicit clear — its [code]on_expire[/code]
## runs once. The two callables are a matched pair, so every "turn it on" is balanced
## by exactly one "turn it off" (set speed_scale 1.4 on apply, restore 1.0 on expire).
##
## Re-applying a live effect refreshes its duration WITHOUT re-running
## [code]on_apply[/code] — holding Vigor open keeps the boon alive without re-paying
## the entry cost. A duration of 0 (or less) means indefinite: it lives until cleared.
##
## A scene-tree [Node] so its per-tick wiring is owned by the tree and survives GC.
class_name StatusEffectSystem
extends Node

## Emitted when a brand-new effect is applied (not on a refresh).
signal effect_applied(target_id: int, effect_id: StringName)
## Emitted when an effect expires — by countdown or by [method clear] / [method clear_all].
signal effect_expired(target_id: int, effect_id: StringName)

## Maps target_id -> { effect_id -> { "remaining": int, "indefinite": bool,
## "on_expire": Callable } }.
var _effects: Dictionary = {}


## Apply [param effect_id] to [param target_id] for [param duration_ticks].
##
## On a fresh effect, [param on_apply] runs once and [signal effect_applied] fires.
## On an effect already live for this target, the duration is refreshed and
## [param on_apply] does NOT run again. A [param duration_ticks] of 0 or less is
## indefinite (until [method clear] / [method clear_all]).
func apply(
	target_id: int,
	effect_id: StringName,
	duration_ticks: int,
	on_apply: Callable,
	on_expire: Callable
) -> void:
	var indefinite := duration_ticks <= 0
	if has(target_id, effect_id):
		var entry: Dictionary = _effects[target_id][effect_id]
		entry["remaining"] = duration_ticks
		entry["indefinite"] = indefinite
		entry["on_expire"] = on_expire
		return
	if not _effects.has(target_id):
		_effects[target_id] = {}
	_effects[target_id][effect_id] = {
		"remaining": duration_ticks,
		"indefinite": indefinite,
		"on_expire": on_expire,
	}
	if on_apply.is_valid():
		on_apply.call()
	effect_applied.emit(target_id, effect_id)


## Whether [param target_id] currently carries [param effect_id].
func has(target_id: int, effect_id: StringName) -> bool:
	return _effects.has(target_id) and _effects[target_id].has(effect_id)


## Clear [param effect_id] from [param target_id], running its [code]on_expire[/code].
##
## A no-op when the target does not carry the effect. Emits [signal effect_expired].
func clear(target_id: int, effect_id: StringName) -> void:
	if not has(target_id, effect_id):
		return
	var entry: Dictionary = _effects[target_id][effect_id]
	_expire_entry(entry)
	_effects[target_id].erase(effect_id)
	if _effects[target_id].is_empty():
		_effects.erase(target_id)
	effect_expired.emit(target_id, effect_id)


## Clear every effect on [param target_id], running each [code]on_expire[/code].
func clear_all(target_id: int) -> void:
	if not _effects.has(target_id):
		return
	for effect_id: StringName in _effects[target_id].keys():
		clear(target_id, effect_id)


## Per-tick countdown (wire to [signal SimulationClock.ticked]).
##
## Decrements every non-indefinite effect; an effect reaching 0 expires (its
## [code]on_expire[/code] runs and [signal effect_expired] fires).
func on_tick(_tick: int) -> void:
	for target_id: int in _effects.keys():
		for effect_id: StringName in _effects[target_id].keys():
			var entry: Dictionary = _effects[target_id][effect_id]
			if entry["indefinite"]:
				continue
			entry["remaining"] = int(entry["remaining"]) - 1
			if entry["remaining"] <= 0:
				_expire_entry(entry)
				_effects[target_id].erase(effect_id)
				effect_expired.emit(target_id, effect_id)
		if _effects.has(target_id) and _effects[target_id].is_empty():
			_effects.erase(target_id)


func _expire_entry(entry: Dictionary) -> void:
	var cb: Callable = entry.get("on_expire", Callable())
	if cb.is_valid():
		cb.call()
