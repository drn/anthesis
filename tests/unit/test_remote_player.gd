## Unit tests for [RemotePlayer] — the glowing peer avatar.
##
## Loads scenes/net/remote_player.tscn headless and exercises:
## - scene loads and root is Node3D
## - procedural CapsuleMesh, OmniLight3D, and billboard Label3D are present
## - [method update_state] sets the target position and yaw
## - avatar snaps when gap > 8 m (after one manual _process call)
## - avatar lerps (does not snap) when gap <= 8 m
extends GutTest

var _scene: PackedScene = preload("res://scenes/net/remote_player.tscn")
var _avatar: RemotePlayer


func before_each() -> void:
	_avatar = _scene.instantiate() as RemotePlayer
	add_child_autofree(_avatar)


# ---------------------------------------------------------------------------
# Scene structure
# ---------------------------------------------------------------------------


func test_root_is_node3d() -> void:
	assert_true(_avatar is Node3D, "RemotePlayer root must be a Node3D")


func test_has_capsule_mesh() -> void:
	var mesh_node := _avatar.get_node_or_null("CapsuleMesh")
	assert_not_null(mesh_node, "RemotePlayer must have a CapsuleMesh child")
	assert_true(mesh_node is MeshInstance3D, "CapsuleMesh must be a MeshInstance3D")
	assert_not_null(
		(mesh_node as MeshInstance3D).mesh, "CapsuleMesh MeshInstance3D must have a mesh"
	)
	assert_true((mesh_node as MeshInstance3D).mesh is CapsuleMesh, "mesh must be a CapsuleMesh")


func test_capsule_mesh_is_emissive() -> void:
	var mesh_node := _avatar.get_node("CapsuleMesh") as MeshInstance3D
	var mat := mesh_node.get_surface_override_material(0) as StandardMaterial3D
	assert_not_null(mat, "CapsuleMesh must carry a material")
	assert_true(mat.emission_enabled, "avatar material must be emissive")


func test_has_omni_light() -> void:
	var light := _avatar.get_node_or_null("AvatarLight")
	assert_not_null(light, "RemotePlayer must have an AvatarLight child")
	assert_true(light is OmniLight3D, "AvatarLight must be an OmniLight3D")


func test_has_label3d() -> void:
	var label := _avatar.get_node_or_null("PeerLabel")
	assert_not_null(label, "RemotePlayer must have a PeerLabel child")
	assert_true(label is Label3D, "PeerLabel must be a Label3D")


func test_label_is_billboard() -> void:
	var label := _avatar.get_node("PeerLabel") as Label3D
	assert_eq(
		label.billboard, BaseMaterial3D.BILLBOARD_ENABLED, "PeerLabel must use BILLBOARD_ENABLED"
	)


# ---------------------------------------------------------------------------
# set_peer_id
# ---------------------------------------------------------------------------


func test_set_peer_id_updates_peer_id() -> void:
	_avatar.set_peer_id(42)
	assert_eq(_avatar.peer_id, 42, "peer_id must be updated by set_peer_id")


func test_set_peer_id_updates_label_text() -> void:
	_avatar.set_peer_id(7)
	var label := _avatar.get_node("PeerLabel") as Label3D
	assert_true(label.text.find("7") >= 0, "label text must contain the peer id after set_peer_id")


# ---------------------------------------------------------------------------
# update_state — target assignment
# ---------------------------------------------------------------------------


func test_update_state_sets_target_position() -> void:
	var target := Vector3(10.0, 0.0, 5.0)
	_avatar.update_state(target, 0.0)
	# Target is stored; _process hasn't run yet, so internal _target_pos == target.
	# Drive one _process tick manually to commit.
	_avatar._process(0.016)
	# After lerp from near-zero origin toward 10m target, position must have moved.
	assert_true(
		(
			_avatar.global_position.distance_to(target)
			< _avatar.global_position.distance_to(Vector3.ZERO)
		),
		"position must have moved toward target after _process"
	)


func test_update_state_sets_target_yaw() -> void:
	_avatar.update_state(Vector3.ZERO, 1.2)
	_avatar._process(0.016)
	# After one frame of lerp toward yaw 1.2 from 0, yaw must be nonzero.
	assert_true(abs(_avatar.rotation.y) > 0.0, "yaw must have started lerping after _process")


# ---------------------------------------------------------------------------
# Snap vs lerp
# ---------------------------------------------------------------------------


func test_snap_when_far() -> void:
	## Place the avatar at origin; set target > 8 m away. One _process must snap.
	_avatar.global_position = Vector3.ZERO
	var far_target := Vector3(20.0, 0.0, 0.0)
	_avatar.update_state(far_target, 0.0)
	_avatar._process(0.016)
	assert_almost_eq(
		_avatar.global_position.x,
		far_target.x,
		0.01,
		"avatar must snap to target when distance > 8 m"
	)


func test_lerp_when_close() -> void:
	## Place avatar near target (< 8 m). After ONE short frame it must NOT have
	## reached the target — it is smoothly interpolating.
	_avatar.global_position = Vector3(0.0, 0.0, 0.0)
	var close_target := Vector3(4.0, 0.0, 0.0)
	_avatar.update_state(close_target, 0.0)
	# Very short delta so lerp covers only a fraction of the gap.
	_avatar._process(0.001)
	var dist_after := _avatar.global_position.distance_to(close_target)
	assert_true(
		dist_after > 0.01, "avatar must still be lerping (not snapped) after one tiny frame"
	)


func test_lerp_multiple_frames_converges() -> void:
	## After many frames the avatar must converge to within 0.1 m of the target.
	_avatar.global_position = Vector3(0.0, 0.0, 0.0)
	var target := Vector3(3.0, 0.0, 0.0)
	_avatar.update_state(target, 0.0)
	for _i in range(120):
		_avatar._process(0.016)
	assert_almost_eq(
		_avatar.global_position.x, target.x, 0.1, "avatar must converge to target over many frames"
	)
