## The player's finite reservoir of Lumen — the luminous investiture of Anthesis.
##
## Lumen is gathered by harvesting living bioluminescent flora and spent to fuel
## magic abilities. The well is deliberately small (default capacity 100): the
## Sanderson-style limitation is that power is scarce and must be replenished by
## interacting with the world, never conjured for free.
##
## All mutations are explicit and total: [method add] clamps at capacity and
## reports overflow, [method spend] is all-or-nothing (a partial spend is never
## allowed). The [signal changed] signal fires only when the stored amount
## actually moves, so listeners (the HUD lumen bar) never repaint on no-ops.
class_name LumenWell
extends RefCounted

## Emitted whenever the stored amount changes. Carries the new current value and
## the (fixed) capacity for convenient one-shot HUD binding.
signal changed(current: float, capacity: float)

var _capacity: float
var _current: float


## Construct a well with the given [param capacity], starting full-empty at 0.
func _init(capacity := 100.0) -> void:
	_capacity = max(0.0, capacity)
	_current = 0.0


## The maximum amount this well can hold.
func capacity() -> float:
	return _capacity


## The amount currently stored.
func current() -> float:
	return _current


## Add [param amount] of Lumen, clamping at capacity.
##
## Returns the overflow — the portion of [param amount] that did not fit (0.0
## when it all fit). Non-positive amounts are no-ops that return 0.0 and emit
## nothing. [signal changed] fires only when the stored amount actually moves
## (i.e. not when already full).
func add(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var before := _current
	_current = min(_capacity, _current + amount)
	var accepted := _current - before
	if accepted > 0.0:
		changed.emit(_current, _capacity)
	return amount - accepted


## Attempt to spend [param amount] of Lumen, all-or-nothing.
##
## Returns [code]true[/code] and deducts the amount only if the well can afford
## it; otherwise returns [code]false[/code] and leaves the well untouched.
## Non-positive amounts succeed trivially without changing or emitting.
func spend(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if not can_afford(amount):
		return false
	_current -= amount
	changed.emit(_current, _capacity)
	return true


## Whether the well currently holds at least [param amount].
##
## Exactly-equal amounts are affordable. Non-positive amounts are always
## affordable.
func can_afford(amount: float) -> bool:
	if amount <= 0.0:
		return true
	return _current >= amount
