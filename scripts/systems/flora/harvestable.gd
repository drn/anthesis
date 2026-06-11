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
