## Removes voxels in a sphere — the player digging into the terrain.
##
## Also awards loot via [LootService] when [member WorldContext.loot] is set.
## The loot hook is optional so existing tests that build a minimal
## [WorldContext] (terrain_edit only) continue to pass unchanged.
class_name DigCommand
extends WorldCommand

var _center: Vector3
var _radius: float


## Capture the dig location [param center] and [param radius].
func _init(center: Vector3, radius: float) -> void:
	_center = center
	_radius = radius


## Route the dig to the terrain edit service, then award loot if available.
func apply(ctx: WorldContext) -> void:
	ctx.terrain_edit.dig_sphere(_center, _radius)
	if ctx.loot != null:
		ctx.loot.award_dig_loot(_center, _radius)
