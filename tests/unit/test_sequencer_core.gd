extends GutTest

## Exercises [SequencerCore] (Phase 6 contract #4): the scene loads and spins,
## [method SequencerCore.setup] binds a fake transport Callable, advancing the
## fake playhead fires registered stub blocks at the correct steps (including a
## loop wrap), registration assigns a step from the block's angle, unregistering
## stops a block firing, and freed blocks are tolerated. A stub Note Block records
## its fire count so we can assert exactly which steps fired.

const CORE_SCENE := "res://scenes/blocks/sequencer_core.tscn"

# Step duration for the canonical 110/16/4 grid the core owns.
const STEP_DUR := 60.0 / 110.0 / 4.0
const LOOP_DUR := 16 * STEP_DUR


# A minimal stand-in for a Note Block: a Node3D in the world with a fire() that
# tallies calls and an assigned_step the core writes into.
class StubBlock:
	extends Node3D
	var fire_count := 0
	var assigned_step := -1

	func fire() -> void:
		fire_count += 1


# A mutable transport: tests set `pos` and hand the core get_pos as its Callable.
class FakeTransport:
	extends RefCounted
	var pos := 0.0

	func get_pos() -> float:
		return pos


var _core: SequencerCore
var _xport: FakeTransport


func before_each() -> void:
	var packed: PackedScene = load(CORE_SCENE)
	_core = packed.instantiate()
	add_child_autofree(_core)
	_xport = FakeTransport.new()
	_core.setup(_xport.get_pos)


func _add_block_at(offset: Vector3) -> StubBlock:
	var b := StubBlock.new()
	add_child_autofree(b)
	b.global_position = _core.global_position + offset
	return b


# Drive the core's _process one frame at the given transport position.
func _step_to(pos: float) -> void:
	_xport.pos = pos
	_core._process(0.016)


# ---------------------------------------------------------------------------
# Scene / construction
# ---------------------------------------------------------------------------


func test_scene_loads() -> void:
	assert_not_null(load(CORE_SCENE), "sequencer_core.tscn must load")


func test_core_in_group_and_has_timeline() -> void:
	assert_true(_core.is_in_group(SequencerCore.GROUP), "core joins the sequencer_cores group")
	assert_eq(_core.timeline().steps, 16, "core owns a 16-step timeline")
	assert_almost_eq(_core.timeline().bpm, 110.0, 1e-6, "core timeline is 110 BPM")


func test_spins_in_process() -> void:
	var before := _core.rotation.y
	_step_to(0.0)
	assert_ne(_core.rotation.y, before, "core rotates each _process frame")


# ---------------------------------------------------------------------------
# Registration assigns a step from angle
# ---------------------------------------------------------------------------


func test_register_assigns_north_step_zero() -> void:
	var b := _add_block_at(Vector3(0, 0, -2))  # due north
	_core.register_block(b)
	assert_eq(b.assigned_step, 0, "block due north of core is assigned step 0")


func test_register_assigns_east_step_four() -> void:
	var b := _add_block_at(Vector3(2, 0, 0))  # east
	_core.register_block(b)
	assert_eq(b.assigned_step, 4, "block east of core is assigned step 4")


func test_register_appears_in_blocks() -> void:
	var b := _add_block_at(Vector3(0, 0, -2))
	_core.register_block(b)
	assert_true(_core.blocks().has(b), "registered block is listed in blocks()")


func test_double_register_no_duplicate() -> void:
	var b := _add_block_at(Vector3(2, 0, 0))
	_core.register_block(b)
	_core.register_block(b)
	var count := 0
	for x in _core.blocks():
		if x == b:
			count += 1
	assert_eq(count, 1, "re-registering must not duplicate the block")


# ---------------------------------------------------------------------------
# Advancing the fake transport fires blocks at their step
# ---------------------------------------------------------------------------


func test_fires_block_at_its_step() -> void:
	# East block -> step 4. Seed at step 0, then advance past step 4.
	var b := _add_block_at(Vector3(2, 0, 0))
	_core.register_block(b)
	_step_to(0.0)  # seed origin, fires nothing
	assert_eq(b.fire_count, 0, "seeding frame fires nothing")
	_step_to(STEP_DUR * 4.5)  # crosses boundaries into 1,2,3,4
	assert_eq(b.fire_count, 1, "east block fires exactly once when step 4 is crossed")


func test_block_does_not_fire_on_other_steps() -> void:
	var b := _add_block_at(Vector3(0, 0, -2))  # north -> step 0
	_core.register_block(b)
	_step_to(STEP_DUR * 0.5)  # seed inside step 0, fires nothing
	_step_to(STEP_DUR * 3.5)  # crosses 1,2,3 — not 0
	assert_eq(b.fire_count, 0, "step-0 block does not fire crossing steps 1..3")


func test_fires_on_loop_wrap() -> void:
	var b := _add_block_at(Vector3(0, 0, -2))  # north -> step 0
	_core.register_block(b)
	_step_to(STEP_DUR * 15.5)  # seed inside step 15
	_step_to(STEP_DUR * 0.5)  # wraps to step 0 -> fires
	assert_eq(b.fire_count, 1, "north block fires when the loop wraps into step 0")


func test_step_advanced_signal_emitted() -> void:
	watch_signals(_core)
	_step_to(STEP_DUR * 0.5)  # seed
	_step_to(STEP_DUR * 1.5)  # cross into step 1
	assert_signal_emitted(_core, "step_advanced", "step_advanced fires on crossing")


func test_multiple_blocks_distinct_steps() -> void:
	var north := _add_block_at(Vector3(0, 0, -2))  # step 0
	var east := _add_block_at(Vector3(2, 0, 0))  # step 4
	_core.register_block(north)
	_core.register_block(east)
	_step_to(STEP_DUR * 0.5)  # seed in step 0
	_step_to(STEP_DUR * 4.5)  # cross 1,2,3,4
	assert_eq(north.fire_count, 0, "north (step 0) does not fire on 1..4")
	assert_eq(east.fire_count, 1, "east (step 4) fires once")


# ---------------------------------------------------------------------------
# Unregister stops firing
# ---------------------------------------------------------------------------


func test_unregister_stops_firing() -> void:
	var b := _add_block_at(Vector3(2, 0, 0))  # step 4
	_core.register_block(b)
	_core.unregister_block(b)
	assert_false(_core.blocks().has(b), "unregistered block leaves blocks()")
	_step_to(STEP_DUR * 0.5)
	_step_to(STEP_DUR * 4.5)
	assert_eq(b.fire_count, 0, "unregistered block never fires")


# ---------------------------------------------------------------------------
# Freed-block tolerance
# ---------------------------------------------------------------------------


func test_freed_block_does_not_crash_firing() -> void:
	var b := _add_block_at(Vector3(2, 0, 0))  # step 4
	_core.register_block(b)
	# Free the block out from under the core, then advance across its step.
	b.free()
	_step_to(STEP_DUR * 0.5)
	_step_to(STEP_DUR * 4.5)  # would fire the (now freed) block
	# Surviving without error and pruning the dead entry is the assertion.
	assert_eq(_core.blocks().size(), 0, "freed block is pruned from the registry")


func test_blocks_skips_freed_entries() -> void:
	# A block freed while still registered is silently skipped by blocks() — no
	# stale reference is ever handed back to callers.
	var live := _add_block_at(Vector3(0, 0, -2))  # step 0
	var doomed := _add_block_at(Vector3(2, 0, 0))  # step 4
	_core.register_block(live)
	_core.register_block(doomed)
	doomed.free()
	var listed := _core.blocks()
	assert_true(listed.has(live), "live block still listed")
	assert_eq(listed.size(), 1, "freed block is omitted from blocks()")
