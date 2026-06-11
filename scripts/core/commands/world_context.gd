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

## The magic rule gate. Casts route through it for cost/cooldown enforcement.
## May be null in legacy / unit-test contexts.
var magic: MagicSystem
## Maps an ability [code]kind[/code] (StringName) to the effect that realizes it:
## Callable(ability: AbilityDef, target: Vector3) -> bool. Installed by World.
## An empty dictionary means every cast resolves to the no_effect path.
var ability_effects: Dictionary = {}
## Callable(amount: float) that adds gathered lumen to the player's well.
## Set by World during wiring. May be an invalid Callable in test contexts.
var lumen_gain: Callable = Callable()

## Combatant registry and damage router. Hits route through it via
## [DamageCommand]. May be null in legacy / unit-test contexts.
var combat: CombatService

## Sequencer block placement/removal service. Block commands
## ([PlaceBlockCommand], [RemoveBlockCommand], [CycleNoteCommand]) route through
## it. May be null in legacy / unit-test contexts.
var block_place: BlockPlacementService

## Active status-effect tracker for all combatants. Used by [DamageCommand] to
## check vigor resistance and by future commands that need per-entity effect
## state. May be null in legacy / unit-test contexts.
var status: StatusEffectSystem

## Burning-channel manager that drives vigor and keensight drain. Toggle and
## flare commands route through it. May be null in legacy / unit-test contexts.
var channels: ChannelSystem

## Per-metal reserve wells. Spell-cast commands top up reserves from inventory
## flakes before the cost gate runs. May be null in legacy / unit-test contexts.
var metal_reserves: MetalReserves

## Spawns a physical ferric coin at the given position with the given velocity.
## Signature: Callable(origin: Vector3, velocity: Vector3). Assigned by World
## during wiring. An invalid Callable is safe — [ThrowCoinCommand] guards it.
var coin_spawn: Callable = Callable()
