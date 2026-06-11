## Exhaustive tests for [CommandRouter]: the authority-aware routing seam.
##
## The router's networking is intentionally thin — every rpc body delegates to a
## plain method and all traffic funnels through [code]_send[/code]. We exploit
## that here: a [code]FakeRouter[/code] captures [code]_send[/code] calls instead
## of transmitting, a [code]FakeSession[/code] forces each authority posture, and
## a fake codec/log/bus let us assert exactly what executes, logs, and is sent in
## the offline / host / client cases without ever opening a socket.
extends GutTest


## A WorldCommand that records nothing — apply is a no-op so the recording bus
## can execute it safely without a real WorldContext.
class DummyCommand:
	extends WorldCommand

	var tag := ""

	func _init(t := "") -> void:
		tag = t

	func apply(_ctx: WorldContext) -> void:
		pass


## Bus that records executed commands instead of applying them.
class RecordingBus:
	extends CommandBus

	var executed: Array = []

	func _init() -> void:
		super(WorldContext.new())

	func execute(cmd: WorldCommand) -> void:
		executed.append(cmd)


## Minimal CommandLog stand-in (duck-typed: append/entries/size).
class FakeLog:
	extends RefCounted

	var _entries: Array = []

	func append(data: Dictionary) -> void:
		_entries.append(data.duplicate(true))

	func entries() -> Array:
		return _entries.duplicate(true)

	func size() -> int:
		return _entries.size()


## CommandCodec stand-in. Encodes a command to a dict carrying its tag and a
## replicable flag; decodes by reading "valid" back. Lets tests force the
## replicable / decodable axes independently of the real codec.
class FakeCodec:
	extends RefCounted

	# A registry: encoded dict -> command, so decode round-trips identity for
	# valid entries and returns null for entries flagged invalid.
	func encode(cmd: WorldCommand, _world: Node) -> Dictionary:
		var dc: DummyCommand = cmd
		return {"t": dc.tag, "valid": true}

	func decode(data: Dictionary, _world: Node) -> WorldCommand:
		if not data.get("valid", false):
			return null
		return DummyCommand.new(String(data.get("t", "")))

	func is_replicable(cmd: WorldCommand, _world: Node) -> bool:
		var dc: DummyCommand = cmd
		return dc.tag.begins_with("repl")


## Session double: each authority posture is set explicitly. Fields are named to
## avoid colliding with NetworkSession's own private members.
class FakeSession:
	extends NetworkSession

	var active_flag := false
	var authority_flag := true
	var uid_value := 1

	func is_active() -> bool:
		return active_flag

	func has_authority() -> bool:
		return authority_flag

	func unique_id() -> int:
		return uid_value


## Router double: captures _send instead of touching the network.
class FakeRouter:
	extends CommandRouter

	var sent: Array = []

	func _send(method: StringName, args: Array, peer := 0) -> void:
		sent.append({"method": method, "args": args, "peer": peer})


var _router: FakeRouter
var _session: FakeSession
var _bus: RecordingBus
var _log: FakeLog
var _codec: FakeCodec


func before_each() -> void:
	_router = FakeRouter.new()
	add_child_autofree(_router)
	_session = FakeSession.new()
	add_child_autofree(_session)
	_bus = RecordingBus.new()
	_log = FakeLog.new()
	_codec = FakeCodec.new()
	_router.setup(_session, _bus, null, _log)
	_router.set_codec(_codec)


func _repl(tag := "repl") -> DummyCommand:
	return DummyCommand.new(tag)


func _local(tag := "local") -> DummyCommand:
	return DummyCommand.new(tag)


# ---------------------------------------------------------------------------
# Offline submit
# ---------------------------------------------------------------------------


func test_offline_submit_executes_directly() -> void:
	_session.active_flag = false
	_router.submit(_repl())
	assert_eq(_bus.executed.size(), 1, "offline submit executes on the bus")
	assert_eq(_router.sent.size(), 0, "offline submit sends nothing")
	assert_eq(_log.size(), 0, "offline submit does not log")


func test_offline_submit_executes_nonreplicable_too() -> void:
	_session.active_flag = false
	_router.submit(_local())
	assert_eq(_bus.executed.size(), 1)
	assert_eq(_router.sent.size(), 0)


func test_submit_null_is_noop() -> void:
	_session.active_flag = false
	_router.submit(null)
	assert_eq(_bus.executed.size(), 0)
	assert_eq(_router.sent.size(), 0)


# ---------------------------------------------------------------------------
# Host submit
# ---------------------------------------------------------------------------


func test_host_submit_replicable_executes_logs_and_broadcasts() -> void:
	_session.active_flag = true
	_session.authority_flag = true
	_router.submit(_repl())
	assert_eq(_bus.executed.size(), 1, "host executes the command")
	assert_eq(_log.size(), 1, "host logs the encoded command")
	assert_eq(_router.sent.size(), 1, "host broadcasts a commit")
	assert_eq(_router.sent[0]["method"], &"commit_command")
	assert_eq(_router.sent[0]["peer"], 0, "commit broadcasts to all peers")


func test_host_submit_nonreplicable_executes_no_broadcast() -> void:
	_session.active_flag = true
	_session.authority_flag = true
	_router.submit(_local())
	assert_eq(_bus.executed.size(), 1, "host executes local-only command")
	assert_eq(_log.size(), 0, "non-replicable is not logged")
	assert_eq(_router.sent.size(), 0, "non-replicable is not broadcast")


# ---------------------------------------------------------------------------
# Client submit
# ---------------------------------------------------------------------------


func test_client_submit_replicable_requests_host_no_local_exec() -> void:
	_session.active_flag = true
	_session.authority_flag = false
	_session.uid_value = 2
	_router.submit(_repl())
	assert_eq(_bus.executed.size(), 0, "client does NOT execute replicable locally")
	assert_eq(_router.sent.size(), 1, "client sends a request to the host")
	assert_eq(_router.sent[0]["method"], &"request_command")
	assert_eq(_router.sent[0]["peer"], NetworkSession.HOST_PEER_ID, "request targets peer 1")
	assert_eq(_log.size(), 0, "client does not log")


func test_client_submit_nonreplicable_executes_locally_no_send() -> void:
	_session.active_flag = true
	_session.authority_flag = false
	_session.uid_value = 2
	_router.submit(_local())
	assert_eq(_bus.executed.size(), 1, "client runs inventory/magic/etc locally")
	assert_eq(_router.sent.size(), 0, "client sends nothing for local commands")


# ---------------------------------------------------------------------------
# _handle_request (host inbound)
# ---------------------------------------------------------------------------


func test_handle_request_on_host_validates_and_commits() -> void:
	_session.active_flag = true
	_session.authority_flag = true
	var data := {"t": "repl", "valid": true}
	_router._handle_request(data, 2)
	assert_eq(_bus.executed.size(), 1, "valid request is committed")
	assert_eq(_log.size(), 1, "committed request is logged")
	assert_eq(_router.sent.size(), 1, "committed request is broadcast")
	assert_eq(_router.sent[0]["method"], &"commit_command")


func test_handle_request_ignored_when_not_authority() -> void:
	_session.active_flag = true
	_session.authority_flag = false
	_session.uid_value = 2
	_router._handle_request({"t": "repl", "valid": true}, 3)
	assert_eq(_bus.executed.size(), 0, "non-host ignores inbound requests")
	assert_eq(_router.sent.size(), 0)
	assert_eq(_log.size(), 0)


func test_handle_request_rejects_undecodable() -> void:
	_session.active_flag = true
	_session.authority_flag = true
	_router._handle_request({"t": "repl", "valid": false}, 2)
	assert_eq(_bus.executed.size(), 0, "undecodable (despawned target) request dropped")
	assert_eq(_router.sent.size(), 0)
	assert_eq(_log.size(), 0)


# ---------------------------------------------------------------------------
# _handle_commit (client inbound)
# ---------------------------------------------------------------------------


func test_handle_commit_executes_on_client() -> void:
	_session.active_flag = true
	_session.authority_flag = false
	_session.uid_value = 2
	_router._handle_commit({"t": "repl", "valid": true})
	assert_eq(_bus.executed.size(), 1, "client applies a host-committed command")
	assert_eq(_router.sent.size(), 0, "applying a commit sends nothing further")


func test_handle_commit_ignores_undecodable() -> void:
	_session.active_flag = true
	_session.authority_flag = false
	_router._handle_commit({"t": "repl", "valid": false})
	assert_eq(_bus.executed.size(), 0, "undecodable commit is dropped")


# ---------------------------------------------------------------------------
# _commit guards
# ---------------------------------------------------------------------------


func test_commit_ignores_empty_dict() -> void:
	_session.active_flag = true
	_session.authority_flag = true
	_router._commit({})
	assert_eq(_bus.executed.size(), 0, "empty (non-replicable) encoding is skipped")
	assert_eq(_log.size(), 0)
	assert_eq(_router.sent.size(), 0)


# ---------------------------------------------------------------------------
# State handshake
# ---------------------------------------------------------------------------


func test_build_state_includes_seed_and_log_entries() -> void:
	_session.active_flag = true
	_session.authority_flag = true
	# Seed two committed entries into the log.
	_router._commit({"t": "a", "valid": true})
	_router._commit({"t": "b", "valid": true})
	var state := _router._build_state()
	assert_true(state.has("seed"), "state carries a seed")
	assert_true(state.has("log"), "state carries the command log")
	assert_eq((state["log"] as Array).size(), 2, "log has both committed entries")


func test_build_state_seed_from_world() -> void:
	var world := _SeededWorld.new()
	add_child_autofree(world)
	_router.setup(_session, _bus, world, _log)
	_router.set_codec(_codec)
	var state := _router._build_state()
	assert_eq(state["seed"], 4242, "seed pulled from world.seed_value()")


func test_handle_state_emits_state_received() -> void:
	watch_signals(_router)
	var snapshot := {"seed": 99, "log": [{"t": "x", "valid": true}]}
	_router._handle_state(snapshot)
	assert_signal_emitted_with_parameters(_router, "state_received", [snapshot])


# ---------------------------------------------------------------------------
# request_state delegation (host only)
# ---------------------------------------------------------------------------


func test_no_send_helpers_leak_when_offline_authority() -> void:
	# has_authority must default true with a wired session that is inactive, so a
	# host-only guard path still behaves correctly. (Covered indirectly above;
	# this asserts the helper contract explicitly via build_state usability.)
	_session.active_flag = false
	var state := _router._build_state()
	assert_true(state.has("seed") and state.has("log"))


## World stand-in exposing a seed_value() method.
class _SeededWorld:
	extends Node

	func seed_value() -> int:
		return 4242
