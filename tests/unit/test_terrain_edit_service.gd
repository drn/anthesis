extends GutTest


## A duck-typed stand-in for [VoxelTool] that records edit operations.
class FakeVoxelTool:
	var mode: int = -1
	var calls: Array = []

	func do_sphere(center: Vector3, radius: float) -> void:
		calls.append({"mode": mode, "center": center, "radius": radius})


func _make_service(fake: FakeVoxelTool) -> TerrainEditService:
	return TerrainEditService.new(func() -> Object: return fake)


func test_dig_sphere_sets_remove_mode_and_calls_do_sphere() -> void:
	var fake := FakeVoxelTool.new()
	var svc := _make_service(fake)

	svc.dig_sphere(Vector3(1, 2, 3), 1.6)

	assert_eq(fake.mode, VoxelTool.MODE_REMOVE, "mode should be MODE_REMOVE")
	assert_eq(fake.calls.size(), 1, "do_sphere called once")
	assert_eq(fake.calls[0]["center"], Vector3(1, 2, 3))
	assert_eq(fake.calls[0]["radius"], 1.6)
	assert_eq(fake.calls[0]["mode"], VoxelTool.MODE_REMOVE)


func test_place_sphere_sets_add_mode_and_calls_do_sphere() -> void:
	var fake := FakeVoxelTool.new()
	var svc := _make_service(fake)

	svc.place_sphere(Vector3(-4, 0, 5), 2.0)

	assert_eq(fake.mode, VoxelTool.MODE_ADD, "mode should be MODE_ADD")
	assert_eq(fake.calls.size(), 1, "do_sphere called once")
	assert_eq(fake.calls[0]["center"], Vector3(-4, 0, 5))
	assert_eq(fake.calls[0]["radius"], 2.0)
	assert_eq(fake.calls[0]["mode"], VoxelTool.MODE_ADD)


func test_remove_and_add_modes_differ() -> void:
	assert_ne(VoxelTool.MODE_REMOVE, VoxelTool.MODE_ADD, "dig and place must use distinct modes")
