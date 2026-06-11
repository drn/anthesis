## A crafting recipe: a list of ingredient [ItemAmount]s consumed to produce an output.
##
## Recipe resources live under resources/recipes/ and are loaded at runtime by
## [ItemRegistry]. The [CraftingService] evaluates whether an [Inventory]
## satisfies the inputs and executes the atomic consume/produce transaction.
class_name Recipe
extends Resource

## Unique identifier for this recipe.
@export var id: StringName
## Human-readable name shown in the crafting panel.
@export var display_name: String
## Ingredient slots consumed when this recipe is crafted.
@export var inputs: Array[ItemAmount] = []
## The item and count produced when crafting succeeds.
@export var output: ItemAmount
