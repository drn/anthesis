## Tests BlockPlacementService storm_catcher placement and removal.
##
## Extends the Phase 9 coverage for BlockPlacementService — the main file
## test_block_placement_service.gd is at the 20-public-method linter ceiling,
## so storm_catcher cases live here per convention.
##
## Uses a stub StormCatcher that joins &"storm_catchers" in _ready, mirroring
## the real class's group registration, without depending on the concrete
## storm_catcher.tscn scene.
extends GutTest


## Minimal StormCatcher stub: joins storm_catchers group so _item_id_for
## identifies it correctly on remove().
class StubStormCatcher:
	extends Node3D

	func _ready() -> void:
		add_to_group(&"storm_catchers")


var _container: Node3D
var _inventory: Inventory
var _service: BlockPlacementService


func before_each() -> void:
	_container = Node3D.new()
	add_child_autofree(_container)
	_inventory = Inventory.new(24)
	var provider := func() -> Node3D: return _container
	var lookup := func(_pos: Vector3) -> Node3D: return null
	_service = BlockPlacementService.new(_inventory, provider, lookup)
	_service.scenes = {
		&"storm_catcher": _pack(StubStormCatcher),
	}


## Pack an instance of [param script_class] into a PackedScene.
func _pack(script_class: GDScript) -> PackedScene:
	var node := Node3D.new()
	node.set_script(script_class)
	var scene := PackedScene.new()
	scene.pack(node)
	node.free()
	return scene


# ---------------------------------------------------------------------------
# storm_catcher placement
# ---------------------------------------------------------------------------


func test_storm_catcher_placement_consumes_inventory() -> void:
	_inventory.add(&"storm_catcher", 2)
	var ok := _service.place(&"storm_catcher", Vector3.ZERO)
	assert_true(ok, "storm_catcher placement should succeed with stock")
	assert_eq(_inventory.count_of(&"storm_catcher"), 1, "one storm_catcher consumed")
	assert_eq(_service.blocks().size(), 1, "one block spawned")


func test_storm_catcher_placement_refuses_without_stock() -> void:
	var ok := _service.place(&"storm_catcher", Vector3.ZERO)
	assert_false(ok, "storm_catcher placement refused without inventory")
	assert_eq(_service.blocks().size(), 0, "no block spawned")


func test_storm_catcher_emits_block_placed() -> void:
	_inventory.add(&"storm_catcher", 1)
	watch_signals(_service)
	_service.place(&"storm_catcher", Vector3.ZERO)
	assert_signal_emitted(_service, "block_placed")


func test_storm_catcher_placement_snaps_to_grid() -> void:
	_inventory.add(&"storm_catcher", 1)
	_service.place(&"storm_catcher", Vector3(1.3, 0.8, -2.6))
	var block: Node3D = _service.blocks()[0]
	assert_eq(block.global_position, Vector3(1.5, 1.0, -2.5), "storm_catcher snaps to 0.5 grid")


# ---------------------------------------------------------------------------
# storm_catcher removal / refund
# ---------------------------------------------------------------------------


func test_storm_catcher_remove_returns_correct_item_id() -> void:
	_inventory.add(&"storm_catcher", 1)
	_service.place(&"storm_catcher", Vector3.ZERO)
	var block: Node = _service.blocks()[0]
	var id := _service.remove(block)
	assert_eq(id, &"storm_catcher", "remove reports storm_catcher id")


func test_storm_catcher_remove_emits_block_removed() -> void:
	_inventory.add(&"storm_catcher", 1)
	_service.place(&"storm_catcher", Vector3.ZERO)
	var block: Node = _service.blocks()[0]
	watch_signals(_service)
	_service.remove(block)
	assert_signal_emitted(_service, "block_removed")


func test_storm_catcher_remove_frees_block() -> void:
	_inventory.add(&"storm_catcher", 1)
	_service.place(&"storm_catcher", Vector3.ZERO)
	var block: Node = _service.blocks()[0]
	_service.remove(block)
	# remove() uses queue_free(), which defers to end of frame — await it so the
	# block is actually gone before asserting the container is empty.
	await get_tree().process_frame
	assert_eq(_service.blocks().size(), 0, "no blocks remain after removal")


func test_storm_catcher_spawn_counter_increments() -> void:
	_inventory.add(&"storm_catcher", 2)
	_service.place(&"storm_catcher", Vector3.ZERO)
	assert_eq(_service.spawn_count(), 1, "spawn counter advances")
	_service.place(&"storm_catcher", Vector3(3.0, 0.0, 0.0))
	assert_eq(_service.spawn_count(), 2, "spawn counter advances again")
