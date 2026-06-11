## Adds voxels in a sphere — the player placing material into the terrain.
class_name PlaceCommand
extends WorldCommand

var _center: Vector3
var _radius: float


## Capture the placement location [param center] and [param radius].
func _init(center: Vector3, radius: float) -> void:
	_center = center
	_radius = radius


## Route the placement to the terrain edit service.
func apply(ctx: WorldContext) -> void:
	ctx.terrain_edit.place_sphere(_center, _radius)
