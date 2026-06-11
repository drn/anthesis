## Authority-aware seam between player intent and command execution.
##
## CommandRouter is THE entry point World uses for every player-intent command.
## It decides — based on the [NetworkSession] authority model — whether a command
## executes locally, is committed by the host and broadcast, or is requested from
## the host by a client:
##
## [codeblock]
## offline                 -> bus.execute(cmd)                       (solo)
## online host             -> _commit(encoded): validate, execute,   (peer 1)
##                            log, broadcast commit_command to peers
## online client + replic. -> rpc_id(1, request_command, encoded)    (ask host)
## online client + local   -> bus.execute(cmd)                       (inventory,
##                            magic, combat, craft stay client-local)
## [/codeblock]
##
## Networking is deliberately thin: every [code]@rpc[/code] body just unpacks its
## arguments and delegates to a plain method ([method _handle_request],
## [method _handle_commit], [method _build_state], [method _handle_state]) so the
## whole protocol is unit-testable without a live peer. The transport itself is
## funneled through [method _send], which a test double overrides to capture
## traffic instead of sending it.
##
## Trust model (v0): the host validates numeric ranges on inbound client commands
## but does not otherwise authenticate intent. This is co-op for friends, not
## anti-cheat.
class_name CommandRouter
extends Node

## Emitted on a client once the host's world state arrives, so World can rebuild
## terrain/flora/blocks from the seed and replay the command log.
signal state_received(state: Dictionary)

# Resolved lazily so this file parses and tests run even before the codec /
# log siblings are merged. In production these resolve to CommandCodec and a
# CommandLog instance supplied via setup().
var _codec: Object = null

var _session: NetworkSession = null
var _bus: CommandBus = null
var _world: Node = null
var _log: Object = null


## Wire dependencies. [param log] is a CommandLog (duck-typed: append/entries/
## size). Called once by the integrator before any [method submit].
func setup(session: NetworkSession, bus: CommandBus, world: Node, log: Object) -> void:
	_session = session
	_bus = bus
	_world = world
	_log = log
	if _codec == null:
		_codec = _resolve_codec()


## Inject a codec (duck-typed: encode/decode/is_replicable). Test seam so the
## protocol can be exercised without the production CommandCodec / a live peer.
func set_codec(codec: Object) -> void:
	_codec = codec


## Submit a player-intent [param cmd]. Routes per the authority model above.
func submit(cmd: WorldCommand) -> void:
	if cmd == null:
		return
	if not _is_active():
		_bus.execute(cmd)
		return
	var replicable := _codec_is_replicable(cmd)
	if _has_authority():
		if replicable:
			_commit(_encode(cmd))
		else:
			_bus.execute(cmd)
		return
	# Non-authoritative client.
	if replicable:
		_send(&"request_command", [_encode(cmd)], NetworkSession.HOST_PEER_ID)
	else:
		# Inventory / magic / combat / craft stay client-local in v0.
		_bus.execute(cmd)


# ---------------------------------------------------------------------------
# RPC surface — each body only unpacks + delegates to a plain method.
# ---------------------------------------------------------------------------

## Client -> host: request that a command be committed. Host-only.
@rpc("any_peer", "call_remote", "reliable")
func request_command(data: Dictionary) -> void:
	_handle_request(data, multiplayer.get_remote_sender_id())


## Host -> clients: a command was committed; apply it locally.
@rpc("authority", "call_remote", "reliable")
func commit_command(data: Dictionary) -> void:
	_handle_commit(data)


## Client -> host: request a full state snapshot for late join. Host-only.
@rpc("any_peer", "call_remote", "reliable")
func request_state() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not _has_authority():
		return
	_send(&"receive_state", [_build_state()], sender)


## Host -> client: the requested state snapshot.
@rpc("authority", "call_remote", "reliable")
func receive_state(state: Dictionary) -> void:
	_handle_state(state)


# ---------------------------------------------------------------------------
# Plain testable cores (no networking).
# ---------------------------------------------------------------------------


## Host path: validate, execute, log, broadcast. [param data] is encoded.
func _commit(data: Dictionary) -> void:
	if data.is_empty():
		return
	var cmd := _decode(data)
	if cmd == null:
		return
	_bus.execute(cmd)
	if _log != null:
		_log.append(data)
	_send(&"commit_command", [data])


## Host path: handle an inbound client request from [param sender_id].
## Ignored unless this instance is authoritative; rejects undecodable/invalid.
func _handle_request(data: Dictionary, _sender_id: int) -> void:
	if not _has_authority():
		return
	if _decode(data) == null:
		return
	_commit(data)


## Client path: apply a host-committed command. [param data] is encoded.
func _handle_commit(data: Dictionary) -> void:
	var cmd := _decode(data)
	if cmd == null:
		return
	_bus.execute(cmd)


## Host path: build a late-join snapshot (seed + full command log).
func _build_state() -> Dictionary:
	var seed_value := 0
	if _world != null and _world.has_method(&"seed_value"):
		seed_value = _world.seed_value()
	elif _world != null and &"seed_value" in _world:
		seed_value = _world.seed_value
	var log_entries: Array = []
	if _log != null:
		log_entries = _log.entries()
	return {"seed": seed_value, "log": log_entries}


## Client path: surface a received snapshot so World rebuilds + replays.
func _handle_state(state: Dictionary) -> void:
	state_received.emit(state)


# ---------------------------------------------------------------------------
# Transport seam + helpers (overridable in test doubles).
# ---------------------------------------------------------------------------


## Send [param method] with [param args] to [param peer] (0 = broadcast).
## The sole point where traffic leaves this node; a [code]FakeRouter[/code]
## overrides this to capture instead of transmit.
func _send(method: StringName, args: Array, peer := 0) -> void:
	if peer == 0:
		callv("rpc", _prepend(method, args))
	else:
		callv("rpc_id", _prepend_id(peer, method, args))


func _prepend(method: StringName, args: Array) -> Array:
	var out: Array = [method]
	out.append_array(args)
	return out


func _prepend_id(peer: int, method: StringName, args: Array) -> Array:
	var out: Array = [peer, method]
	out.append_array(args)
	return out


func _is_active() -> bool:
	return _session != null and _session.is_active()


func _has_authority() -> bool:
	# Offline or host. Defaults to authoritative when no session is wired so the
	# solo/test path always executes locally.
	return _session == null or _session.has_authority()


func _encode(cmd: WorldCommand) -> Dictionary:
	if _codec == null:
		return {}
	return _codec.encode(cmd, _world)


func _decode(data: Dictionary) -> WorldCommand:
	if _codec == null:
		return null
	return _codec.decode(data, _world)


func _codec_is_replicable(cmd: WorldCommand) -> bool:
	if _codec == null:
		return false
	return _codec.is_replicable(cmd, _world)


## Resolve the CommandCodec class. Loaded by script path so this file parses
## before the codec sibling lands; falls back to null (everything local) if
## absent, which keeps offline/solo behavior intact.
func _resolve_codec() -> Object:
	var path := "res://scripts/core/net/command_codec.gd"
	if not ResourceLoader.exists(path):
		return null
	return load(path)
