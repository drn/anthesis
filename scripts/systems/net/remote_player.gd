## Remote-peer avatar shown to the local player in a co-op session.
##
## A glowing cosmic capsule built procedurally in [method _ready]: a
## CapsuleMesh with an emissive gradient material, a small [OmniLight3D] halo,
## and a billboard [Label3D] showing the peer id. The node smoothly lerps
## toward [member _target_pos] / [member _target_yaw] each [method _process]
## frame; state is refreshed by [PlayerSync] via [method update_state].
##
## Snap rule: if the gap between current and target exceeds 8 m the avatar
## teleports instantly (e.g. after late-join state replay).
class_name RemotePlayer
extends Node3D

## Distance beyond which position snaps instead of lerps.
const SNAP_DISTANCE := 8.0
## Lerp speed for smooth position interpolation (m/s feel).
const LERP_SPEED := 12.0

## Peer id whose position this avatar represents.
var peer_id: int = 0

var _target_pos: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0

# Procedural parts built in _build_avatar().
var _mesh: MeshInstance3D
var _light: OmniLight3D
var _label: Label3D


func _ready() -> void:
	_build_avatar()


func _process(delta: float) -> void:
	# Snap if too far, otherwise lerp.
	var dist := global_position.distance_to(_target_pos)
	if dist > SNAP_DISTANCE:
		global_position = _target_pos
		rotation.y = _target_yaw
	else:
		global_position = global_position.lerp(_target_pos, LERP_SPEED * delta)
		rotation.y = lerp_angle(rotation.y, _target_yaw, LERP_SPEED * delta)


## Apply a new network state from [PlayerSync].
## Stores the target; [method _process] will snap if the gap exceeds
## [constant SNAP_DISTANCE] or lerp toward it each frame.
func update_state(pos: Vector3, yaw: float) -> void:
	_target_pos = pos
	_target_yaw = yaw


# ---------------------------------------------------------------------------
# Procedural avatar
# ---------------------------------------------------------------------------


func _build_avatar() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "CapsuleMesh"
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.7
	_mesh.mesh = cap
	_mesh.set_surface_override_material(0, _make_body_material())
	_mesh.position = Vector3(0.0, 0.85, 0.0)
	add_child(_mesh)

	_light = OmniLight3D.new()
	_light.name = "AvatarLight"
	_light.light_color = Color(0.5, 0.8, 1.0)
	_light.light_energy = 1.2
	_light.omni_range = 3.5
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 1.5, 0.0)
	add_child(_light)

	_label = Label3D.new()
	_label.name = "PeerLabel"
	_label.text = "peer %d" % peer_id
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 28
	_label.modulate = Color(0.85, 0.95, 1.0, 0.9)
	_label.position = Vector3(0.0, 2.0, 0.0)
	add_child(_label)


## Emissive cosmic-gradient capsule material: deep indigo with cyan/magenta rim.
func _make_body_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.06, 0.18, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.8
	mat.roughness = 0.3
	mat.rim_enabled = true
	mat.rim = 0.7
	mat.rim_tint = 0.5
	return mat


## Refresh the floating label to match the current [member peer_id].
## Called by [PlayerSync] when spawning this avatar on demand.
func set_peer_id(id: int) -> void:
	peer_id = id
	if _label != null:
		_label.text = "peer %d" % peer_id
