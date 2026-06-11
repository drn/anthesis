## Immutable definition of a single magic ability loaded from a .tres resource.
##
## AbilityDef is the canonical description of an ability: its ID, display name,
## effect kind, lumen cost, cooldown in ticks, magnitude, and UI swatch color.
## All abilities are represented as AbilityDef resources under resources/abilities/.
class_name AbilityDef
extends Resource

## Unique identifier for this ability, used as the key in ability lookups.
@export var id: StringName
## Human-readable name shown in UI.
@export var display_name: String
## Effect kind tag dispatched by the magic system.
## Valid values: &"shape_burst", &"lumen_bloom", &"skyward".
@export var kind: StringName
## Lumen cost deducted from the caster's well on a successful cast.
@export var lumen_cost: float = 10.0
## Minimum ticks between successive casts of this ability.
@export var cooldown_ticks: int = 20
## Effect-specific scalar (carve radius, light radius, impulse m/s, etc.).
@export var magnitude: float = 1.0
## Color swatch shown in the HUD ability slots.
@export var swatch_color: Color = Color.CYAN
## Flavor / lore text shown in tooltips.
@export_multiline var description: String = ""
