## Deterministic flora scattering for cosmic-whimsical prop placement.
##
## FloraScatter provides both a pure placement-math function (testable
## without a scene) and a runtime scatter() method that instantiates
## prop scenes at those placements with Y adjusted by a height callback.
##
## Usage:
##   var placements := FloraScatter.compute_placements(rng, 80, 60.0)
##   scatter(world_seed, func(xz: Vector2) -> float: return terrain_height(xz))
class_name FloraScatter
extends Node3D

## Prop scenes to instantiate during [method scatter].
@export var prop_scenes: Array[PackedScene]

## Number of props to place.
@export var count := 80

## Half-extent of the square placement area (XZ plane).
@export var area_extent := 60.0


## Compute [param count] random [Transform3D] placements within a square XZ
## area of half-extent [param area_extent], using [param rng] for
## reproducibility.
##
## Positions are distributed uniformly in [-area_extent, +area_extent] on X
## and Z. Y is always 0 (caller adjusts via height_fn in [method scatter]).
## Each transform has a random yaw rotation and a uniform scale jitter in
## [0.7, 1.4].
##
## This is a PURE function: same rng state always yields identical results.
static func compute_placements(
	rng: RandomNumberGenerator, count: int, area_extent: float
) -> Array[Transform3D]:
	var results: Array[Transform3D] = []
	results.resize(count)
	for i in range(count):
		var x := rng.randf_range(-area_extent, area_extent)
		var z := rng.randf_range(-area_extent, area_extent)
		var yaw := rng.randf_range(0.0, TAU)
		var scale_uniform := rng.randf_range(0.7, 1.4)
		var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0))
		basis = basis.scaled(Vector3(scale_uniform, scale_uniform, scale_uniform))
		results[i] = Transform3D(basis, Vector3(x, 0.0, z))
	return results


## Instantiate [member prop_scenes] at computed placements with Y from
## [param height_fn].
##
## [param world_seed] is used to derive the "flora" RNG stream so placement
## is deterministic for the same seed.
##
## [param height_fn] must be a [Callable] accepting [Vector2] (XZ position)
## and returning a [float] world-space Y coordinate.
##
## Any previously added children are freed first, so calling scatter() again
## with a different seed cleanly replaces the props.
func scatter(world_seed: WorldSeed, height_fn: Callable) -> void:
	for child in get_children():
		child.queue_free()

	if prop_scenes.is_empty():
		push_warning("FloraScatter.scatter: prop_scenes is empty, nothing to place")
		return

	var rng := world_seed.derive("flora")
	var placements := compute_placements(rng, count, area_extent)

	var scene_count := prop_scenes.size()
	var scene_rng := world_seed.derive("flora_scene_pick")

	for t in placements:
		var scene_index := scene_rng.randi() % scene_count
		var packed: PackedScene = prop_scenes[scene_index]
		if packed == null:
			continue
		var instance := packed.instantiate()
		var xz := Vector2(t.origin.x, t.origin.z)
		var y: float = height_fn.call(xz)
		if is_nan(y):
			# Chunk not streamed in at this point yet — skip rather than
			# float a prop at a bogus height.
			instance.free()
			continue
		var adjusted := Transform3D(t.basis, Vector3(t.origin.x, y, t.origin.z))
		instance.transform = adjusted
		add_child(instance)
