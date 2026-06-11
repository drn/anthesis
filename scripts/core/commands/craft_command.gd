## Attempts to craft a [Recipe] from the player's inventory.
##
## Routes the crafting request through [CraftingService] on [WorldContext] so
## the mutation path remains inside the command layer. The command is a no-op
## when crafting fails (insufficient inputs or no room for output).
class_name CraftCommand
extends WorldCommand

var _recipe: Recipe


## Capture the [param recipe] to craft.
func _init(recipe: Recipe) -> void:
	_recipe = recipe


## Delegate to [CraftingService]; silently does nothing on failure or null ctx.
func apply(ctx: WorldContext) -> void:
	if ctx.crafting == null or ctx.inventory == null:
		return
	ctx.crafting.craft(ctx.inventory, _recipe)
