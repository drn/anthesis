## Pure (de)serialization between [WorldCommand]s and replication dictionaries.
##
## CommandCodec is the wire format for Phase 7 host-authority co-op. It is
## stateless and side-effect free: [method encode] turns a replicable command
## into a compact [Dictionary] (or an empty one when the command is client-local
## and must not replicate), and [method decode] rebuilds a command from such a
## dictionary, resolving any scene targets against a live world.
##
## Replicable commands describe shared-world mutations — terrain edits, sequencer
## blocks, note retuning, flora harvests. Client-local commands — casting,
## damage, crafting — stay on the originating peer and encode to [code]{}[/code].
##
## Wire shapes (the [code]t[/code] tag selects the command):
## [codeblock]
## {t:"dig",     c:[x,y,z], r:radius}
## {t:"place",   c:[x,y,z], r:radius}
## {t:"pblock",  item:"note_block", c:[x,y,z]}
## {t:"rblock",  path:"Block_3"}              # node name under blocks_container()
## {t:"cycle",   path:"Block_3"}              # node name under blocks_container()
## {t:"harvest", idx:2, drops:[["seed",1],...]}  # index into flora() children
## [/codeblock]
##
## Decode resolves [code]rblock[/code]/[code]cycle[/code] paths and the
## [code]harvest[/code] index against the passed world via its introspection
## funcs ([code]blocks_container()[/code], [code]flora()[/code]); when the target
## has despawned, decode returns [code]null[/code] so the caller can drop the
## stale command. Numeric fields are range-gated host-side so a malformed or
## hostile peer cannot drive a pathological edit.
class_name CommandCodec
extends RefCounted

## Coordinate magnitude ceiling (per axis) for any encoded position.
const MAX_COORD := 100000.0
## Inclusive radius bounds for sphere edits (dig / place).
const MIN_RADIUS := 0.1
const MAX_RADIUS := 10.0


## Encode [param cmd] for the wire, or [code]{}[/code] when it must not replicate.
##
## Returns an empty [Dictionary] for client-local commands ([CastCommand],
## [DamageCommand], [CraftCommand]) and for any unrecognized command type. The
## [param world] resolves scene targets to stable identifiers: a block's node
## name for [RemoveBlockCommand] / [CycleNoteCommand], and a flora child index
## for [HarvestCommand]. When a target cannot be located in [param world] the
## command is treated as non-replicable and [code]{}[/code] is returned.
static func encode(cmd: WorldCommand, world: Node) -> Dictionary:
	if cmd == null:
		return {}
	if cmd is DigCommand:
		return {"t": "dig", "c": _vec_to_arr(cmd._center), "r": cmd._radius}
	if cmd is PlaceCommand:
		return {"t": "place", "c": _vec_to_arr(cmd._center), "r": cmd._radius}
	if cmd is PlaceBlockCommand:
		return {"t": "pblock", "item": String(cmd._item_id), "c": _vec_to_arr(cmd._position)}
	if cmd is RemoveBlockCommand:
		var rname := _block_name(cmd._target, world)
		if rname == "":
			return {}
		return {"t": "rblock", "path": rname}
	if cmd is CycleNoteCommand:
		var cname := _block_name(cmd._target, world)
		if cname == "":
			return {}
		return {"t": "cycle", "path": cname}
	if cmd is HarvestCommand:
		var idx := _flora_index(cmd._target, world)
		if idx < 0:
			return {}
		return {"t": "harvest", "idx": idx, "drops": _drops_to_arr(cmd._drops)}
	return {}


## Rebuild a [WorldCommand] from [param data], or [code]null[/code] on failure.
##
## Returns [code]null[/code] when: [param data] lacks a known [code]t[/code] tag;
## a numeric field is missing, the wrong type, or out of range; or a scene target
## (block path / flora index) no longer resolves in [param world]. Decode never
## mutates [param world]; it only reads it to bind targets.
static func decode(data: Dictionary, world: Node) -> WorldCommand:
	if not data.has("t"):
		return null
	var tag := String(data["t"])
	match tag:
		"dig":
			var dc: Variant = _arr_to_vec(data.get("c"))
			if dc == null or not _radius_ok(data.get("r")):
				return null
			return DigCommand.new(dc, float(data["r"]))
		"place":
			var pc: Variant = _arr_to_vec(data.get("c"))
			if pc == null or not _radius_ok(data.get("r")):
				return null
			return PlaceCommand.new(pc, float(data["r"]))
		"pblock":
			var bc: Variant = _arr_to_vec(data.get("c"))
			if bc == null or not (data.get("item") is String):
				return null
			return PlaceBlockCommand.new(StringName(data["item"]), bc)
		"rblock":
			var rt := _resolve_block(data.get("path"), world)
			if rt == null:
				return null
			return RemoveBlockCommand.new(rt)
		"cycle":
			var ct := _resolve_block(data.get("path"), world)
			if ct == null:
				return null
			return CycleNoteCommand.new(ct)
		"harvest":
			var ht := _resolve_flora(data.get("idx"), world)
			if ht == null:
				return null
			return HarvestCommand.new(ht, _arr_to_drops(data.get("drops")))
		_:
			return null


## True when [param cmd] has a replicable wire form (encodes non-empty).
##
## Note this also returns [code]false[/code] when a replicable command's target
## cannot currently be located in [param world] (e.g. it despawned), since such
## a command cannot be encoded.
static func is_replicable(cmd: WorldCommand, world: Node) -> bool:
	return not encode(cmd, world).is_empty()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


## Pack a [Vector3] into a plain [code][x,y,z][/code] float array.
static func _vec_to_arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


## Parse a [code][x,y,z][/code] array into a [Vector3], or null when malformed or
## out of the coordinate range gate.
static func _arr_to_vec(raw: Variant) -> Variant:
	if not (raw is Array) or (raw as Array).size() != 3:
		return null
	var arr: Array = raw
	for n in arr:
		if not (n is float or n is int):
			return null
		if absf(float(n)) > MAX_COORD:
			return null
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


## True when [param raw] is a number within the sphere-radius bounds.
static func _radius_ok(raw: Variant) -> bool:
	if not (raw is float or raw is int):
		return false
	var r := float(raw)
	return r >= MIN_RADIUS and r <= MAX_RADIUS


## Pack an [ItemAmount] drop table into [code][[item_id, count], ...][/code].
static func _drops_to_arr(drops: Array) -> Array:
	var out: Array = []
	for d in drops:
		if d is ItemAmount:
			out.append([String(d.item_id), d.count])
	return out


## Rebuild an [ItemAmount] drop table from [code][[item_id, count], ...][/code].
## Malformed entries are skipped; an absent / non-array input yields an empty
## typed array (a harvest with no drops is still a valid mutation).
static func _arr_to_drops(raw: Variant) -> Array[ItemAmount]:
	var out: Array[ItemAmount] = []
	if not (raw is Array):
		return out
	for entry in raw:
		if not (entry is Array) or (entry as Array).size() != 2:
			continue
		var pair: Array = entry
		if not (pair[0] is String) or not (pair[1] is float or pair[1] is int):
			continue
		var ia := ItemAmount.new()
		ia.item_id = StringName(pair[0])
		ia.count = int(pair[1])
		out.append(ia)
	return out


## The node name [param target] is known by under [param world]'s blocks
## container, or [code]""[/code] when it is not a live block there.
static func _block_name(target: Node, world: Node) -> String:
	if target == null or not is_instance_valid(target):
		return ""
	var container := _blocks_container(world)
	if container == null:
		return ""
	if target.get_parent() != container:
		return ""
	return String(target.name)


## Resolve a block by node [param raw] name under [param world]'s container.
static func _resolve_block(raw: Variant, world: Node) -> Node:
	if not (raw is String) or raw == "":
		return null
	var container := _blocks_container(world)
	if container == null:
		return null
	var node := container.get_node_or_null(NodePath(raw))
	if node == null or not is_instance_valid(node):
		return null
	return node


## The index of [param target] among [param world]'s flora children, or -1.
static func _flora_index(target: Node, world: Node) -> int:
	if target == null or not is_instance_valid(target):
		return -1
	var flora := _flora(world)
	if flora == null:
		return -1
	return flora.get_children().find(target)


## Resolve the flora child at integer index [param raw] under [param world].
static func _resolve_flora(raw: Variant, world: Node) -> Node:
	if not (raw is float or raw is int):
		return null
	var idx := int(raw)
	if idx < 0:
		return null
	var flora := _flora(world)
	if flora == null:
		return null
	var kids := flora.get_children()
	if idx >= kids.size():
		return null
	var node: Node = kids[idx]
	if node == null or not is_instance_valid(node):
		return null
	return node


## The blocks container [Node] via [param world].blocks_container(), or null.
static func _blocks_container(world: Node) -> Node:
	if world == null or not world.has_method("blocks_container"):
		return null
	return world.blocks_container() as Node


## The flora [Node] via [param world].flora(), or null.
static func _flora(world: Node) -> Node:
	if world == null or not world.has_method("flora"):
		return null
	return world.flora() as Node
