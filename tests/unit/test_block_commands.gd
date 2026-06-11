## Tests the Phase 6 block commands: PlaceBlockCommand, RemoveBlockCommand,
## CycleNoteCommand. Verifies routing to BlockPlacementService stubs, the
## inventory refund on removal, null/invalid guards, and CommandBus integration.
extends GutTest


## Stub BlockPlacementService: records place/remove calls, controls remove's id.
class StubBlockPlace:
	extends BlockPlacementService

	var place_calls: Array = []
	var remove_calls: Array = []
	var remove_id := &""

	func _init() -> void:
		super(null, Callable(), Callable())

	func place(item_id: StringName, position: Vector3) -> bool:
		place_calls.append({"item_id": item_id, "position": position})
		return true

	func remove(block: Node) -> StringName:
		remove_calls.append(block)
		return remove_id


## Stub Note Block in the right group that records cycle_pitch calls.
class StubNote:
	extends Node3D

	var cycle_count := 0

	func _ready() -> void:
		add_to_group(&"note_blocks")

	func cycle_pitch() -> void:
		cycle_count += 1


func _make_context() -> WorldContext:
	var ctx := WorldContext.new()
	ctx.block_place = StubBlockPlace.new()
	ctx.inventory = Inventory.new(24)
	return ctx


# ---------------------------------------------------------------------------
# PlaceBlockCommand
# ---------------------------------------------------------------------------


func test_place_block_routes_to_service() -> void:
	var ctx := _make_context()
	var stub: StubBlockPlace = ctx.block_place
	PlaceBlockCommand.new(&"note_block", Vector3(1, 0, 2)).apply(ctx)
	assert_eq(stub.place_calls.size(), 1)
	assert_eq(stub.place_calls[0]["item_id"], &"note_block")
	assert_eq(stub.place_calls[0]["position"], Vector3(1, 0, 2))


func test_place_block_noop_when_service_null() -> void:
	var ctx := WorldContext.new()
	# ctx.block_place is null — must not crash.
	PlaceBlockCommand.new(&"sequencer_core", Vector3.ZERO).apply(ctx)
	assert_true(true)


# ---------------------------------------------------------------------------
# RemoveBlockCommand
# ---------------------------------------------------------------------------


func test_remove_block_routes_to_service() -> void:
	var ctx := _make_context()
	var stub: StubBlockPlace = ctx.block_place
	var target := Node.new()
	RemoveBlockCommand.new(target).apply(ctx)
	assert_eq(stub.remove_calls.size(), 1)
	assert_eq(stub.remove_calls[0], target)
	target.free()


func test_remove_block_refunds_via_inventory() -> void:
	var ctx := _make_context()
	var stub: StubBlockPlace = ctx.block_place
	stub.remove_id = &"note_block"
	var target := Node.new()
	RemoveBlockCommand.new(target).apply(ctx)
	assert_eq(ctx.inventory.count_of(&"note_block"), 1, "removed block refunded to inventory")
	target.free()


func test_remove_block_no_refund_when_empty_id() -> void:
	var ctx := _make_context()
	var stub: StubBlockPlace = ctx.block_place
	stub.remove_id = &""
	var target := Node.new()
	RemoveBlockCommand.new(target).apply(ctx)
	assert_true(ctx.inventory.is_empty(), "no refund when service returns empty id")
	target.free()


func test_remove_block_noop_when_service_null() -> void:
	var ctx := WorldContext.new()
	var target := Node.new()
	RemoveBlockCommand.new(target).apply(ctx)
	assert_true(true)
	target.free()


# ---------------------------------------------------------------------------
# CycleNoteCommand
# ---------------------------------------------------------------------------


func test_cycle_note_cycles_pitch() -> void:
	var ctx := _make_context()
	var note := StubNote.new()
	add_child_autofree(note)
	CycleNoteCommand.new(note).apply(ctx)
	assert_eq(note.cycle_count, 1, "pitch cycled once")


func test_cycle_note_ignores_non_note_block() -> void:
	var ctx := _make_context()
	var plain := Node.new()
	add_child_autofree(plain)
	# Not in group "note_blocks" — must not crash, no effect.
	CycleNoteCommand.new(plain).apply(ctx)
	assert_true(true)


func test_cycle_note_guards_null_target() -> void:
	var ctx := _make_context()
	CycleNoteCommand.new(null).apply(ctx)
	assert_true(true)


# ---------------------------------------------------------------------------
# CommandBus integration
# ---------------------------------------------------------------------------


func test_bus_executes_place_block_command() -> void:
	var ctx := _make_context()
	var stub: StubBlockPlace = ctx.block_place
	var bus := CommandBus.new(ctx)
	watch_signals(bus)
	var cmd := PlaceBlockCommand.new(&"sequencer_core", Vector3.ONE)
	bus.execute(cmd)
	assert_eq(stub.place_calls.size(), 1, "bus routed place command to service")
	assert_signal_emitted_with_parameters(bus, "command_executed", [cmd])


func test_bus_executes_remove_block_command_with_refund() -> void:
	var ctx := _make_context()
	var stub: StubBlockPlace = ctx.block_place
	stub.remove_id = &"sequencer_core"
	var bus := CommandBus.new(ctx)
	var target := Node.new()
	bus.execute(RemoveBlockCommand.new(target))
	assert_eq(stub.remove_calls.size(), 1, "bus routed remove command")
	assert_eq(ctx.inventory.count_of(&"sequencer_core"), 1, "refund applied through bus")
	target.free()
