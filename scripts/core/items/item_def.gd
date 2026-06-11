## Definition of a single item type — immutable data loaded from a .tres resource.
##
## ItemDef is the canonical description of an item: its ID, display name, stack
## limit, category, and how it looks in UI swatches. All game items are
## represented as ItemDef resources under resources/items/.
class_name ItemDef
extends Resource

## Unique identifier for this item, used as the key in [Inventory] and [Recipe].
@export var id: StringName
## Human-readable name shown in UI.
@export var display_name: String
## Maximum number of this item per inventory slot.
@export var max_stack: int = 99
## Broad grouping: "material", "tool", "placeable", etc.
@export var category: StringName = &"material"
## Color swatch shown in the inventory grid (no textures required).
@export var swatch_color: Color = Color.WHITE
## Flavor / lore text shown in tooltips.
@export_multiline var description: String = ""
