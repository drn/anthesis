## Tests CommandCodec: every replicable command round-trips encode -> decode to
## the same fields; client-local commands encode to {}; malformed / out-of-range
## dictionaries decode to null; scene targets resolve (and despawned targets
## fail) against a stub world exposing the same introspection funcs World does.
extends GutTest


## Minimal world stand-in exposing blocks_container() and flora() like World.
class StubWorld:
	extends Node

	var _blocks: Node3D
	var _flora: Node3D

	func _ready() -> void:
		_blocks = Node3D.new()
		_blocks.name = "Blocks"
		add_child(_blocks)
		_flora = Node3D.new()
		_flora.name = "Flora"
		add_child(_flora)

	func blocks_container() -> Node3D:
		return _blocks

	func flora() -> Node3D:
		return _flora


var _world: StubWorld


func before_each() -> void:
	_world = StubWorld.new()
	add_child_autofree(_world)


## Add a named block node under the stub world's container; return it.
func _add_block(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	_world.blocks_container().add_child(n)
	return n


## Add a flora prop under the stub world's flora node; return it.
func _add_flora() -> Node3D:
	var n := Node3D.new()
	_world.flora().add_child(n)
	return n


## Build a typed drop table from [[item_id, count], ...] pairs.
func _drops(pairs: Array) -> Array[ItemAmount]:
	var out: Array[ItemAmount] = []
	for p in pairs:
		var ia := ItemAmount.new()
		ia.item_id = StringName(p[0])
		ia.count = int(p[1])
		out.append(ia)
	return out


# ---------------------------------------------------------------------------
# Replicable round-trips
# ---------------------------------------------------------------------------


func test_dig_round_trips() -> void:
	var data := CommandCodec.encode(DigCommand.new(Vector3(1.0, -2.0, 3.5), 2.5), _world)
	assert_eq(data["t"], "dig")
	assert_eq(data["c"], [1.0, -2.0, 3.5])
	assert_eq(data["r"], 2.5)
	var cmd := CommandCodec.decode(data, _world) as DigCommand
	assert_not_null(cmd, "dig decodes")
	assert_eq(cmd._center, Vector3(1.0, -2.0, 3.5), "center preserved")
	assert_eq(cmd._radius, 2.5, "radius preserved")


func test_place_round_trips() -> void:
	var data := CommandCodec.encode(PlaceCommand.new(Vector3(-4.0, 5.0, 6.0), 1.0), _world)
	assert_eq(data["t"], "place")
	var cmd := CommandCodec.decode(data, _world) as PlaceCommand
	assert_not_null(cmd, "place decodes")
	assert_eq(cmd._center, Vector3(-4.0, 5.0, 6.0))
	assert_eq(cmd._radius, 1.0)


func test_place_block_round_trips() -> void:
	var data := CommandCodec.encode(
		PlaceBlockCommand.new(&"note_block", Vector3(0.5, 0.0, -1.5)), _world
	)
	assert_eq(data["t"], "pblock")
	assert_eq(data["item"], "note_block")
	assert_eq(data["c"], [0.5, 0.0, -1.5])
	var cmd := CommandCodec.decode(data, _world) as PlaceBlockCommand
	assert_not_null(cmd, "pblock decodes")
	assert_eq(cmd._item_id, &"note_block", "item id preserved as StringName")
	assert_eq(cmd._position, Vector3(0.5, 0.0, -1.5), "position preserved")


func test_remove_block_round_trips_by_name() -> void:
	var block := _add_block("Block_7")
	var data := CommandCodec.encode(RemoveBlockCommand.new(block), _world)
	assert_eq(data["t"], "rblock")
	assert_eq(data["path"], "Block_7", "encodes the node name")
	var cmd := CommandCodec.decode(data, _world) as RemoveBlockCommand
	assert_not_null(cmd, "rblock decodes")
	assert_eq(cmd._target, block, "resolves back to the same node")


func test_cycle_note_round_trips_by_name() -> void:
	var block := _add_block("Block_2")
	var data := CommandCodec.encode(CycleNoteCommand.new(block), _world)
	assert_eq(data["t"], "cycle")
	assert_eq(data["path"], "Block_2")
	var cmd := CommandCodec.decode(data, _world) as CycleNoteCommand
	assert_not_null(cmd, "cycle decodes")
	assert_eq(cmd._target, block, "resolves to the same note block")


func test_harvest_round_trips_by_index() -> void:
	_add_flora()  # index 0
	var target := _add_flora()  # index 1
	_add_flora()  # index 2
	var drops := _drops([["glow_spore", 2], ["seed", 1]])
	var data := CommandCodec.encode(HarvestCommand.new(target, drops), _world)
	assert_eq(data["t"], "harvest")
	assert_eq(data["idx"], 1, "encodes the flora child index")
	assert_eq(data["drops"], [["glow_spore", 2], ["seed", 1]], "drops flattened to pairs")
	var cmd := CommandCodec.decode(data, _world) as HarvestCommand
	assert_not_null(cmd, "harvest decodes")
	assert_eq(cmd._target, target, "resolves to the indexed prop")
	assert_eq(cmd._drops.size(), 2, "two drops decoded")
	assert_eq(cmd._drops[0].item_id, &"glow_spore")
	assert_eq(cmd._drops[0].count, 2)
	assert_eq(cmd._drops[1].item_id, &"seed")
	assert_eq(cmd._drops[1].count, 1)


func test_harvest_empty_drops_round_trips() -> void:
	var target := _add_flora()
	var data := CommandCodec.encode(HarvestCommand.new(target, _drops([])), _world)
	assert_eq(data["idx"], 0)
	assert_eq(data["drops"], [])
	var cmd := CommandCodec.decode(data, _world) as HarvestCommand
	assert_not_null(cmd, "empty-drop harvest still decodes")
	assert_eq(cmd._drops.size(), 0, "no drops")


# ---------------------------------------------------------------------------
# Non-replicable commands -> {}
# ---------------------------------------------------------------------------


func test_client_local_commands_not_replicable() -> void:
	# Cast / damage / craft stay on the originating peer: encode -> {}.
	var cast := CastCommand.new(AbilityDef.new(), Vector3.ZERO)
	assert_eq(CommandCodec.encode(cast, _world), {}, "cast encodes empty")
	assert_false(CommandCodec.is_replicable(cast, _world), "cast not replicable")
	var dmg := DamageCommand.new(42, 10.0)
	assert_eq(CommandCodec.encode(dmg, _world), {}, "damage encodes empty")
	assert_false(CommandCodec.is_replicable(dmg, _world), "damage not replicable")
	var craft := CraftCommand.new(Recipe.new())
	assert_eq(CommandCodec.encode(craft, _world), {}, "craft encodes empty")
	assert_false(CommandCodec.is_replicable(craft, _world), "craft not replicable")
	# A null command also encodes empty.
	assert_eq(CommandCodec.encode(null, _world), {}, "null encodes empty")
	# A well-formed replicable command reports true.
	assert_true(
		CommandCodec.is_replicable(DigCommand.new(Vector3.ZERO, 1.0), _world), "dig replicable"
	)


# ---------------------------------------------------------------------------
# Decode validation: malformed dictionaries -> null
# ---------------------------------------------------------------------------


func test_decode_unknown_or_missing_tag_null() -> void:
	assert_null(CommandCodec.decode({}, _world), "no tag -> null")
	assert_null(
		CommandCodec.decode({"t": "explode", "c": [0, 0, 0], "r": 1.0}, _world), "unknown tag"
	)


func test_decode_dig_malformed_fields_null() -> void:
	assert_null(CommandCodec.decode({"t": "dig", "r": 1.0}, _world), "missing c")
	assert_null(CommandCodec.decode({"t": "dig", "c": [1.0, 2.0], "r": 1.0}, _world), "short c")
	assert_null(CommandCodec.decode({"t": "dig", "c": "nope", "r": 1.0}, _world), "non-array c")
	assert_null(
		CommandCodec.decode({"t": "dig", "c": [1.0, "x", 3.0], "r": 1.0}, _world), "non-num c"
	)
	assert_null(CommandCodec.decode({"t": "dig", "c": [0, 0, 0]}, _world), "missing r")


# ---------------------------------------------------------------------------
# Range gates
# ---------------------------------------------------------------------------


func test_decode_radius_gate() -> void:
	assert_null(CommandCodec.decode({"t": "dig", "c": [0, 0, 0], "r": 0.05}, _world), "too small")
	assert_null(CommandCodec.decode({"t": "dig", "c": [0, 0, 0], "r": 25.0}, _world), "too large")
	assert_not_null(CommandCodec.decode({"t": "dig", "c": [0, 0, 0], "r": 0.1}, _world), "min ok")
	assert_not_null(CommandCodec.decode({"t": "dig", "c": [0, 0, 0], "r": 10.0}, _world), "max ok")


func test_decode_coord_out_of_range_null() -> void:
	assert_null(CommandCodec.decode({"t": "dig", "c": [200000.0, 0, 0], "r": 1.0}, _world))
	assert_null(CommandCodec.decode({"t": "place", "c": [0, -200000.0, 0], "r": 1.0}, _world))


func test_decode_pblock_bad_item_null() -> void:
	assert_null(CommandCodec.decode({"t": "pblock", "item": 5, "c": [0, 0, 0]}, _world))
	assert_null(CommandCodec.decode({"t": "pblock", "c": [0, 0, 0]}, _world))


# ---------------------------------------------------------------------------
# Target resolution against the stub world
# ---------------------------------------------------------------------------


func test_decode_block_path_resolution_failures_null() -> void:
	# No such block name under the container.
	assert_null(CommandCodec.decode({"t": "rblock", "path": "Block_99"}, _world), "rblock missing")
	assert_null(CommandCodec.decode({"t": "cycle", "path": "Block_99"}, _world), "cycle missing")
	assert_null(CommandCodec.decode({"t": "rblock", "path": ""}, _world), "empty path")
	assert_null(CommandCodec.decode({"t": "rblock"}, _world), "no path key")


func test_encode_unaddressable_block_empty() -> void:
	# A block not parented under the container is unencodable.
	var orphan := Node3D.new()
	orphan.name = "Loose"
	add_child_autofree(orphan)
	assert_eq(CommandCodec.encode(RemoveBlockCommand.new(orphan), _world), {}, "orphan")
	# A block that has left the container (reparented) likewise cannot be named.
	var block := _add_block("Block_1")
	_world.blocks_container().remove_child(block)
	add_child_autofree(block)
	assert_eq(CommandCodec.encode(RemoveBlockCommand.new(block), _world), {}, "reparented")


func test_decode_harvest_bad_index_null() -> void:
	_add_flora()  # only index 0 exists
	assert_null(CommandCodec.decode({"t": "harvest", "idx": 5, "drops": []}, _world), "too big")
	assert_null(CommandCodec.decode({"t": "harvest", "idx": -1, "drops": []}, _world), "negative")
	assert_null(CommandCodec.decode({"t": "harvest", "idx": "two", "drops": []}, _world), "non-int")


func test_decode_harvest_malformed_drops_skipped() -> void:
	var target := _add_flora()
	var idx := _world.flora().get_children().find(target)
	# Mix valid and malformed drop entries; only the valid one survives.
	var data := {
		"t": "harvest",
		"idx": idx,
		"drops": [["seed", 3], ["bad"], "nope", [5, 5], ["ok", 1]],
	}
	var cmd := CommandCodec.decode(data, _world) as HarvestCommand
	assert_not_null(cmd, "decodes despite malformed drop entries")
	assert_eq(cmd._drops.size(), 2, "only well-formed pairs kept")
	assert_eq(cmd._drops[0].item_id, &"seed")
	assert_eq(cmd._drops[1].item_id, &"ok")
