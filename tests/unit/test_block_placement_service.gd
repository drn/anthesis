## Tests BlockPlacementService: inventory gating, grid snap, core binding,
## dormant adoption, and removal/refund — using stub block scenes so the suite
## does not depend on the concrete SequencerCore / NoteBlock scripts.
extends GutTest


## Stub Sequencer Core: records registered/unregistered note blocks.
class StubCore:
	extends Node3D

	var registered: Array = []

	func _ready() -> void:
		add_to_group(&"sequencer_cores")

	func register_block(block: Node) -> void:
		registered.append(block)
		if &"assigned_step" in block:
			block.assigned_step = 0

	func unregister_block(block: Node) -> void:
		registered.erase(block)

	func blocks() -> Array:
		return registered.duplicate()


## Stub Note Block exposing assigned_step + cycle_pitch like the real one.
class StubNote:
	extends Node3D

	var assigned_step := -1

	func _ready() -> void:
		add_to_group(&"note_blocks")


var _container: Node3D
var _inventory: Inventory
var _service: BlockPlacementService
var _nearest_core: Node3D


func before_each() -> void:
	_container = Node3D.new()
	add_child_autofree(_container)
	_inventory = Inventory.new(24)
	_nearest_core = null
	var provider := func() -> Node3D: return _container
	var lookup := func(_pos: Vector3) -> Node3D: return _nearest_core
	_service = BlockPlacementService.new(_inventory, provider, lookup)
	_service.scenes = {
		&"sequencer_core": _pack(StubCore),
		&"note_block": _pack(StubNote),
	}


## Pack a fresh node of the given inner-class script into a PackedScene.
func _pack(script_class: GDScript) -> PackedScene:
	var node := Node3D.new()
	node.set_script(script_class)
	var scene := PackedScene.new()
	scene.pack(node)
	node.free()
	return scene


# ---------------------------------------------------------------------------
# Inventory gating
# ---------------------------------------------------------------------------


func test_place_consumes_inventory() -> void:
	_inventory.add(&"note_block", 3)
	var ok := _service.place(&"note_block", Vector3.ZERO)
	assert_true(ok, "placement should succeed with stock")
	assert_eq(_inventory.count_of(&"note_block"), 2, "one note_block consumed")
	assert_eq(_service.blocks().size(), 1, "one block spawned in container")


func test_place_refuses_when_empty() -> void:
	# Inventory has no note_block.
	var ok := _service.place(&"note_block", Vector3.ZERO)
	assert_false(ok, "placement should fail without stock")
	assert_eq(_service.blocks().size(), 0, "no block spawned")
	assert_eq(_inventory.count_of(&"note_block"), 0, "inventory unchanged")


func test_place_unknown_item_refuses() -> void:
	_inventory.add(&"glow_spore", 5)
	var ok := _service.place(&"glow_spore", Vector3.ZERO)
	assert_false(ok, "unknown placeable refused")
	assert_eq(_inventory.count_of(&"glow_spore"), 5, "inventory untouched on refusal")


func test_place_emits_block_placed() -> void:
	_inventory.add(&"note_block", 1)
	watch_signals(_service)
	_service.place(&"note_block", Vector3(2.0, 0.0, 0.0))
	assert_signal_emitted(_service, "block_placed")


# ---------------------------------------------------------------------------
# Grid snapping
# ---------------------------------------------------------------------------


func test_place_snaps_to_half_grid() -> void:
	_inventory.add(&"note_block", 1)
	_service.place(&"note_block", Vector3(1.2, 0.7, -2.4))
	var block: Node3D = _service.blocks()[0]
	assert_eq(block.global_position, Vector3(1.0, 0.5, -2.5), "snapped to 0.5 grid")


# ---------------------------------------------------------------------------
# Core binding / dormancy
# ---------------------------------------------------------------------------


func test_note_near_core_registers_with_step() -> void:
	var core := StubCore.new()
	_container.add_child(core)
	core.global_position = Vector3.ZERO
	_nearest_core = core

	_inventory.add(&"note_block", 1)
	_service.place(&"note_block", Vector3(2.0, 0.0, 0.0))

	assert_eq(core.registered.size(), 1, "core registered the new note")
	var note: Node3D = core.registered[0]
	assert_eq(note.assigned_step, 0, "registered note got a step assignment")


func test_note_dormant_when_no_core() -> void:
	_nearest_core = null
	_inventory.add(&"note_block", 1)
	_service.place(&"note_block", Vector3(5.0, 0.0, 0.0))
	var note: StubNote = _service.blocks()[0]
	assert_eq(note.assigned_step, -1, "no core in range -> dormant")


func test_core_adopts_dormant_notes_within_range() -> void:
	# Place two dormant notes (no core), one near, one far.
	_nearest_core = null
	_inventory.add(&"note_block", 2)
	_service.place(&"note_block", Vector3(3.0, 0.0, 0.0))
	_service.place(&"note_block", Vector3(50.0, 0.0, 0.0))
	for b in _service.blocks():
		assert_eq(b.assigned_step, -1, "notes start dormant")

	# Now drop a core at origin; it should adopt only the near note.
	_inventory.add(&"sequencer_core", 1)
	_service.place(&"sequencer_core", Vector3.ZERO)

	var core: StubCore = null
	for b in _service.blocks():
		if b is StubCore:
			core = b
	assert_not_null(core, "core was placed")
	assert_eq(core.registered.size(), 1, "core adopts only the in-range dormant note")
	assert_eq((core.registered[0] as Node3D).global_position, Vector3(3.0, 0.0, 0.0))


# ---------------------------------------------------------------------------
# Removal / refund
# ---------------------------------------------------------------------------


func test_remove_returns_correct_item_id() -> void:
	_inventory.add(&"note_block", 1)
	_service.place(&"note_block", Vector3.ZERO)
	var block: Node = _service.blocks()[0]
	var id := _service.remove(block)
	assert_eq(id, &"note_block", "remove reports the note_block id")


func test_remove_core_returns_core_id() -> void:
	_inventory.add(&"sequencer_core", 1)
	_service.place(&"sequencer_core", Vector3.ZERO)
	var block: Node = _service.blocks()[0]
	var id := _service.remove(block)
	assert_eq(id, &"sequencer_core")


func test_remove_unregisters_note_from_core() -> void:
	var core := StubCore.new()
	_container.add_child(core)
	core.global_position = Vector3.ZERO
	_nearest_core = core
	_inventory.add(&"note_block", 1)
	_service.place(&"note_block", Vector3(2.0, 0.0, 0.0))
	var note: Node = core.registered[0]

	_service.remove(note)
	assert_eq(core.registered.size(), 0, "note unregistered from core on removal")


func test_remove_invalid_returns_empty() -> void:
	var plain := Node.new()
	add_child_autofree(plain)
	assert_eq(_service.remove(plain), &"", "non-block returns empty id")
	assert_eq(_service.remove(null), &"", "null returns empty id")


func test_remove_emits_block_removed() -> void:
	_inventory.add(&"note_block", 1)
	_service.place(&"note_block", Vector3.ZERO)
	var block: Node = _service.blocks()[0]
	watch_signals(_service)
	_service.remove(block)
	assert_signal_emitted(_service, "block_removed")


# ---------------------------------------------------------------------------
# Deterministic block names / spawn counter (Phase 7 replication)
# ---------------------------------------------------------------------------


func test_spawn_count_starts_zero() -> void:
	assert_eq(_service.spawn_count(), 0, "no blocks spawned yet")


func test_blocks_named_sequentially() -> void:
	_inventory.add(&"note_block", 3)
	_service.place(&"note_block", Vector3.ZERO)
	_service.place(&"note_block", Vector3(2.0, 0.0, 0.0))
	_service.place(&"note_block", Vector3(4.0, 0.0, 0.0))
	var names: Array = []
	for b in _service.blocks():
		names.append(String(b.name))
	assert_eq(names, ["Block_0", "Block_1", "Block_2"], "names increment in place order")


func test_spawn_count_increments_per_success() -> void:
	_inventory.add(&"note_block", 2)
	_service.place(&"note_block", Vector3.ZERO)
	assert_eq(_service.spawn_count(), 1, "one successful place")
	_service.place(&"note_block", Vector3(2.0, 0.0, 0.0))
	assert_eq(_service.spawn_count(), 2, "two successful places")


func test_spawn_count_unchanged_on_refusal() -> void:
	# No stock -> refused -> counter must not advance.
	_service.place(&"note_block", Vector3.ZERO)
	assert_eq(_service.spawn_count(), 0, "refused placement does not bump counter")


func test_names_unique_across_kinds() -> void:
	_inventory.add(&"note_block", 1)
	_inventory.add(&"sequencer_core", 1)
	_service.place(&"note_block", Vector3.ZERO)
	_service.place(&"sequencer_core", Vector3(3.0, 0.0, 0.0))
	var names: Array = []
	for b in _service.blocks():
		names.append(String(b.name))
	assert_eq(names, ["Block_0", "Block_1"], "counter spans both block kinds")
