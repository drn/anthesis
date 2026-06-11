## Removes voxels in a sphere — the player digging into the terrain.
class_name DigCommand
extends WorldCommand

var _center: Vector3
var _radius: float


## Capture the dig location [param center] and [param radius].
func _init(center: Vector3, radius: float) -> void:
	_center = center
	_radius = radius


## Route the dig to the terrain edit service.
func apply(ctx: WorldContext) -> void:
	ctx.terrain_edit.dig_sphere(_center, _radius)
