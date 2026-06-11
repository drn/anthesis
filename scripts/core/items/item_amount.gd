## A quantity of a specific item — used in recipe inputs/outputs and loot tables.
##
## ItemAmount pairs an item ID with a count. It is used wherever "N of item X"
## must be expressed as data: recipe ingredients, crafting outputs, and loot
## drop tables.
class_name ItemAmount
extends Resource

## ID of the item this amount refers to. Must match an [ItemDef].id.
@export var item_id: StringName
## How many of the item this entry represents.
@export var count: int = 1
