extends GutTest

# ---------------------------------------------------------------------------
# Integration test — in-world music sequencer wiring (Phase 6, the signature).
#
# Boots world.tscn and asserts the sequencer is composed end to end: a Blocks
# container, a BlockPlacementService published on the WorldContext, and the
# player block intents flowing through the CommandBus to spawn, retune, and
# remove blocks while charging/refunding the shared inventory. Placement is
# exercised through the bus (never the service directly) so the command-layer
# wiring is proven. Kept in its own file (mirroring test_world_combat.gd) so
# test_world_boot.gd stays under the 20-public-method lint cap.
# ---------------------------------------------------------------------------

const WORLD_SCENE := "res://scenes/world/world.tscn"


func _boot() -> World:
	var world: World = load(WORLD_SCENE).instantiate()
	add_child_autofree(world)
	return world


func test_sequencer_service_and_container_wired() -> void:
	var world := _boot()
	assert_not_null(world.block_place(), "block_place() must return a BlockPlacementService")
	assert_true(
		world.block_place() is BlockPlacementService, "block_place() must be the service type"
	)
	var container := world.blocks_container()
	assert_not_null(container, "blocks_container() must return the Blocks node")
	assert_true(container.is_inside_tree(), "the Blocks container must be in the scene tree")


func test_place_core_through_bus_consumes_item_and_spawns() -> void:
	var world := _boot()
	world.inventory().add(&"sequencer_core", 1)
	assert_eq(world.inventory().count_of(&"sequencer_core"), 1, "precondition: one core in stock")

	world.command_bus().execute(PlaceBlockCommand.new(&"sequencer_core", Vector3(2, 0, 2)))

	assert_eq(
		world.inventory().count_of(&"sequencer_core"), 0, "placing must consume the core item"
	)
	var cores := world.blocks_container().get_children().filter(
		func(n: Node) -> bool: return n is SequencerCore
	)
	assert_eq(cores.size(), 1, "one Sequencer Core must be spawned under the Blocks container")


func test_note_block_registers_to_core_with_correct_step() -> void:
	var world := _boot()
	world.inventory().add(&"sequencer_core", 1)
	world.inventory().add(&"note_block", 1)

	# Core at origin; note due north (-Z) must land on step 0.
	world.command_bus().execute(PlaceBlockCommand.new(&"sequencer_core", Vector3.ZERO))
	world.command_bus().execute(PlaceBlockCommand.new(&"note_block", Vector3(0, 0, -2)))

	var core: SequencerCore = null
	var note: NoteBlock = null
	for child in world.blocks_container().get_children():
		if child is SequencerCore:
			core = child
		elif child is NoteBlock:
			note = child
	assert_not_null(core, "a Sequencer Core must be present")
	assert_not_null(note, "a Note Block must be present")
	assert_eq(note.assigned_step, 0, "a note due north of the core must occupy step 0")
	assert_true(core.blocks().has(note), "the core must own the registered note block")


func test_cycle_note_through_bus_changes_pitch() -> void:
	var world := _boot()
	world.inventory().add(&"note_block", 1)
	world.command_bus().execute(PlaceBlockCommand.new(&"note_block", Vector3(0, 0, -2)))
	var note: NoteBlock = null
	for child in world.blocks_container().get_children():
		if child is NoteBlock:
			note = child
	assert_not_null(note, "a Note Block must be present")
	var before := note.pitch_index

	world.command_bus().execute(CycleNoteCommand.new(note))

	assert_eq(note.pitch_index, (before + 1) % NoteBlock.PITCH_COUNT, "cycling must advance pitch")


func test_remove_block_through_bus_refunds_inventory() -> void:
	var world := _boot()
	world.inventory().add(&"note_block", 1)
	world.command_bus().execute(PlaceBlockCommand.new(&"note_block", Vector3(0, 0, -2)))
	assert_eq(world.inventory().count_of(&"note_block"), 0, "placement consumed the note block")
	var note: NoteBlock = null
	for child in world.blocks_container().get_children():
		if child is NoteBlock:
			note = child
	assert_not_null(note, "a Note Block must be present")

	world.command_bus().execute(RemoveBlockCommand.new(note))

	assert_eq(world.inventory().count_of(&"note_block"), 1, "removal must refund the note block")
