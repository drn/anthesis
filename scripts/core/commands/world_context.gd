## Shared dependency bundle passed to every [WorldCommand] on apply.
##
## WorldContext is the seam between commands (which describe intent) and the
## systems that carry it out. Commands never reach into the scene tree; they
## only touch services exposed here. As new mutable subsystems appear
## (inventory, entities, lighting), add them as fields on this context.
class_name WorldContext
extends RefCounted

## Service that performs voxel terrain mutations. Assigned by the integrator.
var terrain_edit: TerrainEditService

## The player's item registry. May be null in legacy / unit-test contexts.
var registry: ItemRegistry
## The player's inventory. May be null in legacy / unit-test contexts.
var inventory: Inventory
## Crafting logic service. May be null in legacy / unit-test contexts.
var crafting: CraftingService
## Loot award service. May be null in legacy / unit-test contexts.
var loot: LootService
## Callable(node: Node) that frees a harvested prop node safely.
## Set by World during wiring. May be an invalid Callable in test contexts.
var flora_harvest: Callable = Callable()
