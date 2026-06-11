## Structural unit tests for the Player scene.
##
## Loads player.tscn headless and verifies node types, required children,
## and signal declarations.  Input simulation is deliberately avoided —
## headless mode does not have a reliable input map or display.
extends GutTest

var _player_scene: PackedScene = preload("res://scenes/player/player.tscn")
var _player: Player


func before_each() -> void:
	_player = _player_scene.instantiate() as Player
	add_child_autofree(_player)


# ---------------------------------------------------------------------------
# Node type
# ---------------------------------------------------------------------------


func test_root_is_character_body_3d() -> void:
	assert_true(_player is CharacterBody3D, "Player root must be a CharacterBody3D")


# ---------------------------------------------------------------------------
# Required children
# ---------------------------------------------------------------------------


func test_has_camera3d_child() -> void:
	var cam := _player.get_node_or_null("Camera3D")
	assert_not_null(cam, "Player must have a Camera3D child named Camera3D")
	assert_true(cam is Camera3D, "Camera3D child must be a Camera3D")


func test_has_raycast3d_under_camera() -> void:
	var rc := _player.get_node_or_null("Camera3D/RayCast3D")
	assert_not_null(rc, "Player must have a RayCast3D under Camera3D")
	assert_true(rc is RayCast3D, "RayCast3D child must be a RayCast3D")


func test_has_voxel_viewer_child() -> void:
	var vv := _player.get_node_or_null("VoxelViewer")
	assert_not_null(vv, "Player must have a VoxelViewer child")


func test_has_collision_shape() -> void:
	var cs := _player.get_node_or_null("CollisionShape3D")
	assert_not_null(cs, "Player must have a CollisionShape3D child")


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------


func test_has_signal_dig_requested() -> void:
	assert_true(_player.has_signal("dig_requested"), "Player must declare signal dig_requested")


func test_has_signal_place_requested() -> void:
	assert_true(_player.has_signal("place_requested"), "Player must declare signal place_requested")


# ---------------------------------------------------------------------------
# Camera configuration
# ---------------------------------------------------------------------------


func test_camera_near_clip() -> void:
	var cam := _player.get_node("Camera3D") as Camera3D
	assert_almost_eq(cam.near, 0.05, 0.001, "Camera near clip must be 0.05")


func test_camera_far_clip() -> void:
	var cam := _player.get_node("Camera3D") as Camera3D
	assert_almost_eq(cam.far, 500.0, 1.0, "Camera far clip must be 500")


func test_camera_eye_height() -> void:
	var cam := _player.get_node("Camera3D") as Camera3D
	assert_almost_eq(cam.position.y, 1.7, 0.05, "Camera eye height must be ~1.7 m")


# ---------------------------------------------------------------------------
# RayCast reach
# ---------------------------------------------------------------------------


func test_raycast_reach() -> void:
	var rc := _player.get_node("Camera3D/RayCast3D") as RayCast3D
	# Target must be 6 m forward (negative Z in local camera space).
	assert_almost_eq(rc.target_position.z, -6.0, 0.1, "RayCast3D reach must be ~6 m forward")


# ---------------------------------------------------------------------------
# VoxelViewer configuration
# ---------------------------------------------------------------------------


func test_voxel_viewer_requires_collisions() -> void:
	var vv := _player.get_node("VoxelViewer")
	assert_true(vv.requires_collisions, "VoxelViewer must have requires_collisions = true")
