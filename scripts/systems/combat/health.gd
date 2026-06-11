## A bounded hit-point pool for any combatant (player or creature).
##
## Health is pure logic: it owns a current/max value pair, clamps every change
## into [code][0, max][/code], and announces transitions through signals so
## presentation (HUD bars, hurt flashes, dissolve effects) can react without
## polling. It tracks combatants only by value — it holds no node reference and
## performs no scene-tree work, which keeps it fully unit-testable.
##
## The [signal died] signal fires exactly once, on the change that first crosses
## current to zero; subsequent damage on a dead pool is a no-op and never
## re-emits. This single-shot guarantee lets listeners wire one-time death
## sequences without their own debouncing.
class_name Health
extends RefCounted

## Emitted after any change to [member current], with the new current and max.
signal changed(current: float, max_health: float)
## Emitted once, the moment current first reaches zero.
signal died

var _max: float
var _current: float
var _dead := false


## Construct a full pool with [param max_health] hit points.
##
## A non-positive [param max_health] is clamped to a minimal positive value so
## the pool always has a valid range and never starts dead.
func _init(max_health: float) -> void:
	_max = maxf(max_health, 0.001)
	_current = _max


## The maximum hit points this pool can hold.
func max_health() -> float:
	return _max


## The current hit points, always within [code][0, max][/code].
func current() -> float:
	return _current


## Whether the pool has been depleted to zero.
func is_dead() -> bool:
	return _dead


## Apply [param amount] of damage, returning the damage actually dealt.
##
## Returns 0.0 when already dead or when [param amount] is non-positive (a
## guard, heal, or stray call). Otherwise reduces current by the portion that
## fits above zero, emits [signal changed], and — if this crosses to zero —
## emits [signal died] exactly once.
func take_damage(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var applied := minf(amount, _current)
	_current -= applied
	changed.emit(_current, _max)
	if _current <= 0.0:
		_current = 0.0
		_dead = true
		died.emit()
	return applied


## Restore [param amount] hit points, returning the amount actually healed.
##
## A no-op (returns 0.0) when dead or when [param amount] is non-positive. The
## result is clamped to [member max_health]; only the portion that fit is
## returned, and [signal changed] is emitted when any healing occurred.
func heal(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var applied := minf(amount, _max - _current)
	if applied <= 0.0:
		return 0.0
	_current += applied
	changed.emit(_current, _max)
	return applied
