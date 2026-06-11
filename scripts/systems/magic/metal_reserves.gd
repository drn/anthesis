## The burning reserves of a Ferromancer — one [LumenWell] per ingested metal.
##
## Where the [LumenWell] holds Lumen, MetalReserves holds the metals a Ferromancer
## has swallowed and can burn: iron, steel, pewter, tin. Each kind is its own small
## well, all starting empty (a Ferromancer must eat metal flakes before burning).
## Burning a metal spends from its well; the well refills not from the world's glow
## but from the player's pouch — [method ensure] auto-swallows flakes from an
## [Inventory] on demand, turning one flake into [constant FLAKE_CHARGE] of charge.
##
## The Sanderson-style limitation: every metal is a separate, finite budget. You
## cannot pull iron with an empty iron reserve, and topping up costs real flakes.
class_name MetalReserves
extends RefCounted

## Re-emitted from each per-metal well whenever its stored amount changes. Carries
## the metal [param kind] alongside the new current value and that well's capacity.
signal changed(kind: StringName, current: float, capacity: float)

## Per-metal well capacity when none is supplied.
const DEFAULT_CAPACITY := 60.0
## Charge gained from swallowing a single metal flake.
const FLAKE_CHARGE := 30.0

## Maps metal kind -> the item id of its burnable flake.
var _flake_map: Dictionary = {}
## Maps metal kind -> its [LumenWell].
var _wells: Dictionary = {}


## Construct one [LumenWell] per key in [param flake_map] (metal kind -> flake item
## id), each at [param capacity] and starting empty. Each well's
## [signal LumenWell.changed] is re-emitted as [signal changed] tagged with its kind.
func _init(flake_map: Dictionary, capacity := DEFAULT_CAPACITY) -> void:
	_flake_map = flake_map.duplicate()
	for kind: StringName in _flake_map.keys():
		var well := LumenWell.new(capacity)
		well.changed.connect(
			func(current: float, cap: float) -> void: changed.emit(kind, current, cap)
		)
		_wells[kind] = well


## The metal kinds this reserve tracks, sorted for stable iteration / UI order.
##
## Sorted lexically by string value (StringName's default sort is by internal
## hash, which is not stable across runs), so callers and the HUD get a stable
## metal order.
func kinds() -> Array:
	var ks := _wells.keys()
	ks.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ks


## The [LumenWell] backing [param kind], or null when the kind is not tracked.
func well(kind: StringName) -> LumenWell:
	return _wells.get(kind, null)


## Add [param amount] of charge to [param kind]'s well; return the overflow.
##
## Delegates to [method LumenWell.add]. An unknown [param kind] accepts nothing and
## returns [param amount] as full overflow (clamped at 0.0 for non-positive input).
func add(kind: StringName, amount: float) -> float:
	var w := well(kind)
	if w == null:
		return maxf(0.0, amount)
	return w.add(amount)


## Ensure [param kind]'s well holds at least [param amount], swallowing flakes.
##
## While the well is short and [param inventory] still has a matching flake, removes
## one flake and adds [constant FLAKE_CHARGE]. Returns whether the well can finally
## afford [param amount]. An unknown kind returns false; a null [param inventory] is
## a no-op top-up (the result then reflects only what was already in the well).
func ensure(kind: StringName, amount: float, inventory: Object) -> bool:
	var w := well(kind)
	if w == null:
		return false
	if inventory != null:
		var flake_id: StringName = _flake_map.get(kind, &"")
		while w.current() < amount and inventory.count_of(flake_id) > 0:
			inventory.remove(flake_id, 1)
			w.add(FLAKE_CHARGE)
	return w.can_afford(amount)


## Top up the well an [param ability] will spend from, if it burns a metal.
##
## A no-op returning true for &"lumen" or any untracked kind (those abilities do not
## draw on metal reserves). Otherwise delegates to [method ensure] for the ability's
## [member AbilityDef.resource_kind] and [member AbilityDef.lumen_cost].
func ensure_for_cost(ability: AbilityDef, inventory: Object) -> bool:
	var kind: StringName = ability.resource_kind
	if kind == &"" or kind == &"lumen" or not _wells.has(kind):
		return true
	return ensure(kind, ability.lumen_cost, inventory)
