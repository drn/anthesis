## Immutable definition of a creature/enemy loaded from a .tres resource.
##
## CreatureDef is the canonical description of a creature: its ID, display name,
## combat stats, AI parameters, drop table, and visual identity.
## All creatures are represented as CreatureDef resources under resources/creatures/.
class_name CreatureDef
extends Resource

## Unique identifier for this creature, used as the key in creature lookups.
@export var id: StringName
## Human-readable name shown in UI and debug output.
@export var display_name: String
## Maximum hit points for this creature.
@export var max_health: float = 10.0
## Movement speed in metres per second.
@export var move_speed: float = 2.0
## Damage dealt per successful attack.
@export var attack_damage: float = 5.0
## Range in metres within which the creature can land an attack.
@export var attack_range: float = 1.5
## Range in metres at which the creature notices and pursues the player.
@export var aggro_range: float = 10.0
## Minimum ticks between successive attacks.
@export var attack_cooldown_ticks: int = 20
## Radius in metres around the spawn point that the creature wanders when idle.
@export var wander_radius: float = 6.0
## Items dropped when this creature is defeated.
@export var drops: Array[ItemAmount]
## Lumen awarded to the player on kill.
@export var lumen_reward: float = 5.0
## Emissive colour of the glowing core sphere.
@export var core_color: Color = Color(0.7, 0.3, 1.0)
## Uniform scale applied to the procedural body mesh.
@export var body_scale: float = 1.0
