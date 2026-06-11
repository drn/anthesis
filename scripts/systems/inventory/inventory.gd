## Fixed-size, slot-based item container with stacking.
##
## Inventory holds a fixed number of slots. Each slot is either empty or holds a
## stack of a single item id up to that item's [member ItemDef.max_stack]
## (falling back to 99 when no registry/definition is available). Adding fills
## existing matching stacks before consuming empty slots; removing drains across
## all matching stacks.
##
## Mutations route through [method add] / [method remove] and emit
## [signal changed] exactly once per call that actually altered state, so UI can
## refresh cheaply.
class_name Inventory
extends RefCounted

## Emitted once after any call that changed the inventory's contents.
signal changed

## Default per-stack ceiling when no item definition is known.
const DEFAULT_MAX_STACK := 99

var _size: int
var _registry: ItemRegistry
## Parallel arrays: a slot i is empty when _ids[i] == &"".
var _ids: Array[StringName] = []
var _counts: Array[int] = []


## Construct with [param size] slots, optionally backed by [param registry].
##
## The registry is consulted for per-item [member ItemDef.max_stack]; without it
## every stack uses [constant DEFAULT_MAX_STACK].
func _init(size := 24, registry: ItemRegistry = null) -> void:
	_size = maxi(0, size)
	_registry = registry
	for _i in range(_size):
		_ids.append(&"")
		_counts.append(0)


## Add [param count] of [param item_id]; return the amount that did NOT fit.
##
## Existing stacks of the same item are topped up first, then empty slots are
## consumed. A non-positive [param count] (or empty id) is a no-op returning 0.
## Emits [signal changed] only if at least one item was stored.
func add(item_id: StringName, count: int) -> int:
	if item_id == &"" or count <= 0:
		return maxi(0, count)
	var remaining := count
	var cap := _max_stack_for(item_id)
	# Pass 1: top up existing matching stacks.
	for i in range(_size):
		if remaining <= 0:
			break
		if _ids[i] == item_id and _counts[i] < cap:
			var room := cap - _counts[i]
			var moved := mini(room, remaining)
			_counts[i] += moved
			remaining -= moved
	# Pass 2: fill empty slots.
	for i in range(_size):
		if remaining <= 0:
			break
		if _ids[i] == &"":
			var moved := mini(cap, remaining)
			_ids[i] = item_id
			_counts[i] = moved
			remaining -= moved
	if remaining != count:
		changed.emit()
	return remaining


## Remove up to [param count] of [param item_id]; return the amount removed.
##
## Drains across every matching stack until satisfied or exhausted. Empties
## slots that reach zero. Emits [signal changed] only if something was removed.
func remove(item_id: StringName, count: int) -> int:
	if item_id == &"" or count <= 0:
		return 0
	var remaining := count
	for i in range(_size):
		if remaining <= 0:
			break
		if _ids[i] == item_id:
			var taken := mini(_counts[i], remaining)
			_counts[i] -= taken
			remaining -= taken
			if _counts[i] == 0:
				_ids[i] = &""
	var removed := count - remaining
	if removed > 0:
		changed.emit()
	return removed


## Return the total quantity of [param item_id] across all slots.
func count_of(item_id: StringName) -> int:
	var total := 0
	for i in range(_size):
		if _ids[i] == item_id:
			total += _counts[i]
	return total


## Return slot [param i] as [code]{}[/code] when empty, else
## [code]{"id": StringName, "count": int}[/code]. Out-of-range yields [code]{}[/code].
func slot(i: int) -> Dictionary:
	if i < 0 or i >= _size or _ids[i] == &"":
		return {}
	return {"id": _ids[i], "count": _counts[i]}


## Return the number of slots in this inventory.
func size() -> int:
	return _size


## Return [code]true[/code] when every slot is empty.
func is_empty() -> bool:
	for i in range(_size):
		if _ids[i] != &"":
			return false
	return true


## Resolve the per-stack ceiling for [param item_id] via the registry.
func _max_stack_for(item_id: StringName) -> int:
	if _registry != null:
		var def := _registry.item(item_id)
		if def != null and def.max_stack > 0:
			return def.max_stack
	return DEFAULT_MAX_STACK
