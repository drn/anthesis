## Applies recipes against an [Inventory], atomically.
##
## CraftingService is stateless gameplay logic: it reads a [Recipe], checks an
## [Inventory] for sufficient inputs, and — only if the output will also fit —
## consumes the inputs and stores the output. If producing the output would
## overflow the inventory, the craft fails and NOTHING is consumed, so a failed
## craft never destroys materials.
##
## Crafting never mutates voxel/world state directly; callers route requests
## through the command layer, which delegates here.
class_name CraftingService
extends RefCounted

## Emitted after a successful [method craft] for [param recipe].
signal crafted(recipe: Recipe)

var _registry: ItemRegistry


## Construct against [param registry] (used for stack sizes during the fit check).
func _init(registry: ItemRegistry) -> void:
	_registry = registry


## Return [code]true[/code] if [param inv] holds every input of [param recipe].
##
## Only checks inputs; the output-fit check happens inside [method craft] after
## inputs are notionally removed. A null/empty recipe is not craftable.
func can_craft(inv: Inventory, recipe: Recipe) -> bool:
	if recipe == null or inv == null:
		return false
	if recipe.inputs == null or recipe.inputs.is_empty():
		return false
	for need in recipe.inputs:
		if need == null:
			return false
		if inv.count_of(need.item_id) < need.count:
			return false
	return true


## Attempt to craft [param recipe] into [param inv]; return success.
##
## Atomic: verifies all inputs are present, then removes them, then adds the
## output. If the output cannot fully fit, the removed inputs are restored and
## the call fails with no net change. Emits [signal crafted] only on success.
func craft(inv: Inventory, recipe: Recipe) -> bool:
	if not can_craft(inv, recipe):
		return false
	if recipe.output == null or recipe.output.item_id == &"" or recipe.output.count <= 0:
		return false

	# Consume inputs. can_craft guarantees each is fully present, so each
	# remove() returns exactly the requested amount.
	for need in recipe.inputs:
		inv.remove(need.item_id, need.count)

	# Try to store the output; an overflow means the craft must be undone.
	var leftover := inv.add(recipe.output.item_id, recipe.output.count)
	if leftover > 0:
		_rollback(inv, recipe, leftover)
		return false

	crafted.emit(recipe)
	return true


## Undo a partial craft: pull back any stored output, then restore inputs.
func _rollback(inv: Inventory, recipe: Recipe, output_leftover: int) -> void:
	var stored := recipe.output.count - output_leftover
	if stored > 0:
		inv.remove(recipe.output.item_id, stored)
	for need in recipe.inputs:
		inv.add(need.item_id, need.count)
