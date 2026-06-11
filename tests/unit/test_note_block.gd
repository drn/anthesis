## Tests for the Note Block scene + script (Phase 6 sequencer).
##
## Validates: the scene loads and instantiates a NoteBlock in the note_blocks
## group; it carries an AudioStreamPlayer3D and a StaticBody3D + CollisionShape3D
## (so raycasts hit it); cycle_pitch wraps 0..7 and recolours the crystal;
## fire() runs without error headlessly; and assigned_step defaults to -1.
extends GutTest

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const NOTE_BLOCK_PATH := "res://scenes/blocks/note_block.tscn"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _instantiate() -> Node3D:
	var packed: PackedScene = load(NOTE_BLOCK_PATH)
	assert_not_null(packed, "note_block.tscn must load")
	var root := packed.instantiate()
	add_child_autofree(root)
	return root


func _find_class(node: Node, klass: String) -> Node:
	if node.is_class(klass):
		return node
	for child in node.get_children():
		var found := _find_class(child, klass)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# Scene-shape tests
# ---------------------------------------------------------------------------


func test_scene_loads() -> void:
	var packed: PackedScene = load(NOTE_BLOCK_PATH)
	assert_not_null(packed, "note_block.tscn must load")


func test_root_is_note_block_in_group() -> void:
	var root := _instantiate()
	assert_true(root is NoteBlock, "root must be a NoteBlock")
	assert_true(root.is_in_group(&"note_blocks"), "root must be in the note_blocks group")


func test_has_audio_stream_player_3d() -> void:
	var root := _instantiate()
	var player := _find_class(root, "AudioStreamPlayer3D")
	assert_not_null(player, "NoteBlock must have an AudioStreamPlayer3D")


func test_has_static_body_with_collision() -> void:
	var root := _instantiate()
	var body := _find_class(root, "StaticBody3D")
	assert_not_null(body, "NoteBlock must have a StaticBody3D for raycasts")
	if body != null:
		var shape := _find_class(body, "CollisionShape3D")
		assert_not_null(shape, "StaticBody3D must have a CollisionShape3D")
		if shape != null:
			assert_not_null(shape.shape, "CollisionShape3D must have a shape set")


func test_assigned_step_defaults_to_negative_one() -> void:
	var root := _instantiate()
	assert_eq(root.assigned_step, -1, "assigned_step must default to -1 (dormant)")


# ---------------------------------------------------------------------------
# Behaviour tests
# ---------------------------------------------------------------------------


func test_cycle_pitch_wraps_after_eight() -> void:
	var root := _instantiate()
	root.pitch_index = 0
	for expected in [1, 2, 3, 4, 5, 6, 7, 0]:
		root.cycle_pitch()
		assert_eq(root.pitch_index, expected, "cycle_pitch must advance + wrap mod 8")


func test_cycle_pitch_changes_color() -> void:
	var root := _instantiate()
	root.pitch_index = 0
	var mesh := root.get_node_or_null("Crystal") as MeshInstance3D
	assert_not_null(mesh, "NoteBlock must have a Crystal MeshInstance3D")
	var before := (mesh.get_active_material(0) as StandardMaterial3D).emission
	root.cycle_pitch()
	var after := (mesh.get_active_material(0) as StandardMaterial3D).emission
	assert_ne(before, after, "cycling pitch must change the crystal emission colour")


func test_fire_runs_without_error() -> void:
	var root := _instantiate()
	root.fire()
	# If fire() raised, the suite would fail; reaching here means it returned.
	assert_true(true, "fire() must return without error headlessly")


func test_pitch_index_setter_clamps_into_range() -> void:
	var root := _instantiate()
	root.pitch_index = 9
	assert_eq(root.pitch_index, 1, "setter must wrap 9 -> 1 (mod 8)")
	root.pitch_index = -1
	assert_eq(root.pitch_index, 7, "setter must wrap -1 -> 7 (mod 8)")
