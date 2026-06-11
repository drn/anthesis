## Performs voxel terrain edits through an injected [VoxelTool]-like provider.
##
## TerrainEditService is the only place that mutates voxel data. It takes a
## [Callable] that returns a [VoxelTool] (or a duck-typed stand-in) so the
## live terrain and unit tests can share the same edit logic. The service
## itself owns no state beyond the provider — it sets the tool mode and
## issues sphere operations on demand.
##
## Usage:
##   var svc := TerrainEditService.new(func(): return voxel_world.voxel_tool())
##   svc.dig_sphere(hit_pos, 1.6)
class_name TerrainEditService
extends RefCounted

var _tool_provider: Callable


## Construct with a [param tool_provider] returning a [VoxelTool]-like object.
##
## The parameter is optional so test stubs can subclass without supplying a
## provider; calling [method dig_sphere] / [method place_sphere] on a service
## built without a valid provider is a no-op (with an error pushed).
func _init(tool_provider: Callable = Callable()) -> void:
	_tool_provider = tool_provider


## Remove voxels inside a sphere at [param center] with [param radius].
func dig_sphere(center: Vector3, radius: float) -> void:
	var tool: Object = _resolve_tool()
	if tool == null:
		return
	tool.mode = VoxelTool.MODE_REMOVE
	tool.do_sphere(center, radius)


## Add voxels inside a sphere at [param center] with [param radius].
func place_sphere(center: Vector3, radius: float) -> void:
	var tool: Object = _resolve_tool()
	if tool == null:
		return
	tool.mode = VoxelTool.MODE_ADD
	tool.do_sphere(center, radius)


## Invoke the provider and return the tool, or null if unavailable.
func _resolve_tool() -> Object:
	if not _tool_provider.is_valid():
		push_error("TerrainEditService has no valid tool provider")
		return null
	var tool: Object = _tool_provider.call()
	if tool == null:
		push_error("TerrainEditService tool provider returned null")
		return null
	return tool
