## Tests for [NetworkSession]: the offline-by-default authority model and the
## structural API the rest of Phase 7 wires against. Live ENet host/join cannot
## be meaningfully asserted in a headless unit test, so those are covered by the
## two-instance smoke test; here we pin down the offline contract and that every
## documented method and signal exists.
extends GutTest


func _make_session() -> NetworkSession:
	var s := NetworkSession.new()
	add_child_autofree(s)
	return s


# ---------------------------------------------------------------------------
# Offline defaults
# ---------------------------------------------------------------------------


func test_offline_not_active() -> void:
	var s := _make_session()
	assert_false(s.is_active(), "fresh session is offline")


func test_offline_not_host() -> void:
	var s := _make_session()
	assert_false(s.is_host(), "is_host is false when offline (no peer)")


func test_offline_has_authority_true() -> void:
	var s := _make_session()
	assert_true(s.has_authority(), "offline counts as authoritative (solo path)")


func test_offline_unique_id_is_host_peer() -> void:
	var s := _make_session()
	assert_eq(s.unique_id(), NetworkSession.HOST_PEER_ID, "offline reports peer 1")


func test_offline_peer_ids_empty() -> void:
	var s := _make_session()
	assert_eq(s.peer_ids(), [], "no peers when offline")


func test_leave_when_idle_is_safe() -> void:
	var s := _make_session()
	s.leave()
	assert_false(s.is_active(), "leave on idle session stays offline")


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------


func test_default_port_constant() -> void:
	assert_eq(NetworkSession.DEFAULT_PORT, 24565)


func test_host_peer_id_constant() -> void:
	assert_eq(NetworkSession.HOST_PEER_ID, 1)


# ---------------------------------------------------------------------------
# API surface (structural)
# ---------------------------------------------------------------------------


func test_has_session_methods() -> void:
	var s := _make_session()
	for m in [
		"host", "join", "leave", "is_active", "is_host", "unique_id", "has_authority", "peer_ids"
	]:
		assert_true(s.has_method(m), "NetworkSession exposes %s()" % m)


func test_has_session_signals() -> void:
	var s := _make_session()
	for sig in ["session_started", "session_ended", "peer_joined", "peer_left"]:
		assert_true(s.has_signal(sig), "NetworkSession declares signal %s" % sig)


func test_signals_are_connectable() -> void:
	# Connecting/emitting must not error — the wiring code (SessionPanel, World)
	# binds these, so they have to behave like ordinary user signals.
	var s := _make_session()
	watch_signals(s)
	s.session_started.emit(true)
	s.peer_joined.emit(7)
	s.peer_left.emit(7)
	s.session_ended.emit()
	assert_signal_emitted_with_parameters(s, "session_started", [true])
	assert_signal_emitted_with_parameters(s, "peer_joined", [7])
	assert_signal_emitted_with_parameters(s, "peer_left", [7])
	assert_signal_emitted(s, "session_ended")
