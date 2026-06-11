## Spawns and removes sequencer blocks, charging and refunding the inventory.
##
## BlockPlacementService is the one seam where in-world sequencer blocks
## (Sequencer Cores and Note Blocks) enter and leave the scene. It is driven
## exclusively by the command layer ([PlaceBlockCommand] / [RemoveBlockCommand]),
## never from input or render code, so block placement stays an auditable world
## mutation like every other.
##
## Placement is gated on inventory: [method place] consumes one of the requested
## item before it spawns anything, and refuses (returns [code]false[/code])
## without mutating the world when the item is not in stock. Positions snap to a
## half-unit grid so blocks tile cleanly.
##
## Note Blocks bind to the nearest [SequencerCore] within [constant RADIUS] at
## placement time; with no core in range they stay dormant ([code]assigned_step
## == -1[/code]) until a core is placed nearby, at which point that core adopts
## every dormant Note Block in range. The service identifies blocks by scene
## group membership ([code]"sequencer_cores"[/code] / [code]"note_blocks"[/code])
## and talks to cores through duck-typed methods, so it never hard-depends on the
## concrete block scripts.
class_name BlockPlacementService
extends RefCounted

## Emitted after a block is successfully placed into the world.
signal block_placed(item_id: StringName, position: Vector3)
## Emitted after a block is removed from the world.
signal block_removed(item_id: StringName)

## A Note Block joins a core's loop only when placed within this many metres.
const RADIUS := 10.0
## Grid resolution that placement positions snap to.
const GRID := 0.5

## Group names that identify the two block kinds on their scene roots.
const GROUP_CORE := &"sequencer_cores"
const GROUP_NOTE := &"note_blocks"

## Canonical scene paths, loaded lazily so this service compiles before the
## block scenes exist and so tests can override [member scenes] with stubs.
const _SCENE_PATHS := {
	&"sequencer_core": "res://scenes/blocks/sequencer_core.tscn",
	&"note_block": "res://scenes/blocks/note_block.tscn",
}

## item_id (StringName) -> [PackedScene]. Populated lazily from [constant
## _SCENE_PATHS]; tests may assign stub scenes directly before calling [method
## place].
var scenes: Dictionary = {}

var _inventory: Inventory
var _container_provider: Callable
var _core_lookup: Callable

## Monotonic counter feeding deterministic block names. Increments once per
## successful [method place]. Late-join replay reproduces identical names
## because placements replay in the same order they were committed.
var _spawn_counter: int = 0


## Construct with the player [param inventory] that placement charges/refunds,
## a [param container_provider] returning the [Node3D] blocks live under, and a
## [param core_lookup] mapping a world position to the nearest [SequencerCore]
## within range (or [code]null[/code]).
func _init(inventory: Inventory, container_provider: Callable, core_lookup: Callable) -> void:
	_inventory = inventory
	_container_provider = container_provider
	_core_lookup = core_lookup


## Spawn the block for [param item_id] at [param position]; return success.
##
## Charges one [param item_id] from the inventory first and refuses (returns
## [code]false[/code], no world change) when none is available or the item has
## no registered scene. The spawned block is snapped to the half-unit grid and
## added to the container. A Note Block registers with the nearest core in range
## (else stays dormant); a Sequencer Core adopts every dormant Note Block within
## [constant RADIUS]. Emits [signal block_placed] on success.
func place(item_id: StringName, position: Vector3) -> bool:
	var scene := _scene_for(item_id)
	if scene == null:
		return false
	if _inventory == null or _inventory.remove(item_id, 1) != 1:
		return false
	var block := scene.instantiate() as Node3D
	if block == null:
		# Refund: we charged but cannot spawn.
		if _inventory != null:
			_inventory.add(item_id, 1)
		return false
	var snapped := _snap(position)
	var container := _container()
	# Name the block deterministically and sequentially so replicated /
	# late-join replays resolve the same node by name across peers.
	block.name = "Block_%d" % _spawn_counter
	_spawn_counter += 1
	if container != null:
		container.add_child(block)
	block.global_position = snapped
	if item_id == &"note_block":
		_bind_note_to_core(block)
	elif item_id == &"sequencer_core":
		_adopt_dormant_notes(block)
	block_placed.emit(item_id, snapped)
	return true


## Remove [param block] from the world and report which item to refund.
##
## Determines the refund item from the block's group membership, unregisters it
## from any core it belongs to, frees it, and returns the item id (or [code]&""
## [/code] when [param block] is not a recognised sequencer block). Emits
## [signal block_removed] with the refunded id on success.
func remove(block: Node) -> StringName:
	if block == null or not is_instance_valid(block):
		return &""
	var item_id := _item_id_for(block)
	if item_id == &"":
		return &""
	if block.is_in_group(GROUP_NOTE):
		_unregister_from_cores(block)
	elif block.is_in_group(GROUP_CORE):
		_release_core_blocks(block)
	block.queue_free()
	block_removed.emit(item_id)
	return item_id


## All current block nodes under the container, freed nodes excluded.
func blocks() -> Array:
	var out: Array = []
	var container := _container()
	if container == null:
		return out
	for child in container.get_children():
		if is_instance_valid(child):
			out.append(child)
	return out


## Number of blocks spawned so far; also the name index of the next block.
##
## Equals the next [code]Block_N[/code] suffix [method place] will assign. Used
## by replication to confirm two peers agree on placement order.
func spawn_count() -> int:
	return _spawn_counter


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


## Resolve (and cache) the [PackedScene] for [param item_id], or null.
func _scene_for(item_id: StringName) -> PackedScene:
	if scenes.has(item_id):
		return scenes[item_id]
	if not _SCENE_PATHS.has(item_id):
		return null
	var loaded := ResourceLoader.load(_SCENE_PATHS[item_id]) as PackedScene
	scenes[item_id] = loaded
	return loaded


## The blocks container [Node3D], or null when no valid provider is wired.
func _container() -> Node3D:
	if not _container_provider.is_valid():
		return null
	return _container_provider.call() as Node3D


## Snap a world [param position] to the half-unit placement grid.
func _snap(position: Vector3) -> Vector3:
	return Vector3(
		snappedf(position.x, GRID), snappedf(position.y, GRID), snappedf(position.z, GRID)
	)


## Identify which item a placed [param block] refunds, by group membership.
func _item_id_for(block: Node) -> StringName:
	if block.is_in_group(GROUP_NOTE):
		return &"note_block"
	if block.is_in_group(GROUP_CORE):
		return &"sequencer_core"
	return &""


## Register a freshly placed note [param block] with the nearest core in range.
func _bind_note_to_core(block: Node) -> void:
	if not _core_lookup.is_valid():
		return
	var core: Node = _core_lookup.call((block as Node3D).global_position)
	if core != null and is_instance_valid(core) and core.has_method("register_block"):
		core.register_block(block)


## Have a freshly placed [param core] adopt dormant notes within range.
func _adopt_dormant_notes(core: Node) -> void:
	if not core.has_method("register_block"):
		return
	var core_pos := (core as Node3D).global_position
	var container := _container()
	if container == null:
		return
	for child in container.get_children():
		if child == core or not is_instance_valid(child):
			continue
		if not child.is_in_group(GROUP_NOTE):
			continue
		if not _is_dormant(child):
			continue
		if (child as Node3D).global_position.distance_to(core_pos) <= RADIUS:
			core.register_block(child)


## True when a note block has not yet joined a core (assigned_step defaults -1).
func _is_dormant(note: Node) -> bool:
	if not (&"assigned_step" in note):
		return true
	return int(note.assigned_step) < 0


## Unregister [param block] from every core that currently owns it.
func _unregister_from_cores(block: Node) -> void:
	if block.get_tree() == null:
		return
	for core in block.get_tree().get_nodes_in_group(GROUP_CORE):
		if is_instance_valid(core) and core.has_method("unregister_block"):
			core.unregister_block(block)


## When a core is removed, drop the note blocks it owns back to dormant.
func _release_core_blocks(core: Node) -> void:
	if not core.has_method("blocks"):
		return
	for note in core.blocks():
		if not is_instance_valid(note):
			continue
		if &"assigned_step" in note:
			note.assigned_step = -1
