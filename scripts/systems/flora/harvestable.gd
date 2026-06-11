## Harvestable component — attach as a child named "Harvestable" to any prop
## scene that the player can harvest via the interact action.
##
## Declares the loot table (drops) and a UI prompt string.
## The Player emits harvest_requested when raycasting hits a prop that owns
## a Harvestable child; the World routes that through HarvestCommand.
class_name Harvestable
extends Node

## The items dropped when this prop is harvested.
@export var drops: Array[ItemAmount] = []

## Prompt text shown in the HUD crosshair area while targeting this prop.
@export var prompt: String = "Harvest"

## Lumen yielded to the player's well when this prop is harvested.
## Gathering living flora is the only source of the Lumen investiture, so this
## value is the per-prop reward (mushroom 8, flower 10, crystal 15). Zero or
## negative values yield nothing.
@export var lumen: float = 8.0
