class_name MetalLineOverlay
extends Node3D
## Allomantic blue-line overlay: while the player holds the metal_sense action
## and has iron or steel in reserve, draws translucent blue lines from just below
## the camera to every metal source within FerroKinetics.MAX_RANGE.
##
## Lines are drawn with ImmediateMesh on an unshaded additive child
## MeshInstance3D. Alpha scales with source mass so massive anchors (deposits)
## glow brighter than light coins. This node is pure presentation — it never
## mutates game state.

## Mesh child node name, created in _ready.
const MESH_NODE_NAME := "BlueLineMesh"

## Blue-line base color (additive steel-blue).
const LINE_COLOR := Color(0.35, 0.65, 1.0, 1.0)

## Camera origin offset so lines start just below eye level rather than at the
## exact camera position (avoids z-fighting near the camera frustum).
const CAMERA_OFFSET := Vector3(0.0, -0.25, 0.0)

var _camera_provider: Callable
var _sources_provider: Callable
var _reserves: Object

var _mesh_instance: MeshInstance3D
var _imesh: ImmediateMesh


func _ready() -> void:
	_imesh = ImmediateMesh.new()

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = MESH_NODE_NAME
	_mesh_instance.mesh = _imesh
	_mesh_instance.material_override = mat
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)


## Wire the overlay to the live scene. Call once after add_child.
## camera_provider() -> Camera3D or null.
## sources_provider() -> Array of metal-source Node3Ds (contract #7 protocol).
## reserves is duck-typed (must expose well(kind) -> LumenWell-like with current()).
func setup(camera_provider: Callable, sources_provider: Callable, reserves: Object) -> void:
	_camera_provider = camera_provider
	_sources_provider = sources_provider
	_reserves = reserves


func _process(_delta: float) -> void:
	_imesh.clear_surfaces()

	if not _should_draw():
		return

	var camera: Camera3D = _camera_provider.call() if _camera_provider.is_valid() else null
	if camera == null:
		return

	var sources: Array = _sources_provider.call() if _sources_provider.is_valid() else []
	if sources.is_empty():
		return

	var origin: Vector3 = camera.global_position + CAMERA_OFFSET

	_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for source in sources:
		if not is_instance_valid(source):
			continue
		var source_pos: Vector3 = source.global_position
		var dist := origin.distance_to(source_pos)
		if dist > FerroKinetics.MAX_RANGE:
			continue
		var mass: float = source.metal_mass if "metal_mass" in source else 1.0
		var alpha := clampf(mass / FerroKinetics.PLAYER_MASS, 0.2, 1.0)
		var color := Color(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, alpha)
		_imesh.surface_set_color(color)
		_imesh.surface_add_vertex(origin)
		_imesh.surface_set_color(color)
		_imesh.surface_add_vertex(source_pos)
	_imesh.surface_end()


## Returns true only when the metal_sense action is pressed and iron or steel
## reserve is above zero. All guards use InputMap.has_action to tolerate
## headless / importless runs.
func _should_draw() -> bool:
	if not InputMap.has_action("metal_sense"):
		return false
	if not Input.is_action_pressed("metal_sense"):
		return false
	if _reserves == null:
		return false
	if not _reserves.has_method("well"):
		return false
	var iron_well: Object = _reserves.well(&"iron")
	var steel_well: Object = _reserves.well(&"steel")
	var iron_current := 0.0
	var steel_current := 0.0
	if iron_well != null and iron_well.has_method("current"):
		iron_current = iron_well.current()
	if steel_well != null and steel_well.has_method("current"):
		steel_current = steel_well.current()
	return iron_current > 0.0 or steel_current > 0.0
