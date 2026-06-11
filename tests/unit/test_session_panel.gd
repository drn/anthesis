extends GutTest
## Structural and behavioral tests for SessionPanel.
##
## Tests cover: default visibility, status label existence, address LineEdit
## default text, button signal emissions, and bind(session) status reflection.
## No networking is exercised — FakeSession stands in for NetworkSession.

const PANEL_PATH := "res://scenes/ui/session_panel.tscn"


func _load_panel() -> SessionPanel:
	var panel := (load(PANEL_PATH) as PackedScene).instantiate() as SessionPanel
	add_child_autofree(panel)
	return panel


# ---------------------------------------------------------------------------
# Structural assertions
# ---------------------------------------------------------------------------


func test_scene_loads() -> void:
	assert_not_null(load(PANEL_PATH), "session_panel.tscn must load")


func test_root_is_session_panel() -> void:
	var panel := _load_panel()
	assert_true(panel is SessionPanel, "Root must carry the SessionPanel script")


func test_hidden_by_default() -> void:
	var panel := _load_panel()
	assert_false(panel.visible, "SessionPanel must be hidden by default")


func test_status_label_exists() -> void:
	var panel := _load_panel()
	var label := panel.get_node_or_null("Layout/Panel/Margin/Body/Status")
	assert_not_null(label, "SessionPanel must have a Status label")
	assert_true(label is Label, "Status node must be a Label")


func test_address_edit_default_text() -> void:
	var panel := _load_panel()
	var edit := panel.get_node_or_null("Layout/Panel/Margin/Body/Row/AddressEdit")
	assert_not_null(edit, "SessionPanel must have an AddressEdit LineEdit")
	assert_true(edit is LineEdit, "AddressEdit must be a LineEdit")
	assert_eq(edit.text, "127.0.0.1", "AddressEdit default text must be 127.0.0.1")


func test_has_host_button() -> void:
	var panel := _load_panel()
	var btn := panel.get_node_or_null("Layout/Panel/Margin/Body/Row/HostButton")
	assert_not_null(btn, "SessionPanel must have a HostButton")
	assert_true(btn is Button, "HostButton must be a Button")


func test_has_join_button() -> void:
	var panel := _load_panel()
	var btn := panel.get_node_or_null("Layout/Panel/Margin/Body/Row/JoinButton")
	assert_not_null(btn, "SessionPanel must have a JoinButton")
	assert_true(btn is Button, "JoinButton must be a Button")


func test_has_leave_button() -> void:
	var panel := _load_panel()
	var btn := panel.get_node_or_null("Layout/Panel/Margin/Body/LeaveButton")
	assert_not_null(btn, "SessionPanel must have a LeaveButton")
	assert_true(btn is Button, "LeaveButton must be a Button")


func test_has_bind_method() -> void:
	var panel := _load_panel()
	assert_true(panel.has_method("bind"), "SessionPanel must expose bind(session)")


# ---------------------------------------------------------------------------
# Signal emissions
# ---------------------------------------------------------------------------


func test_host_button_emits_host_requested() -> void:
	var panel := _load_panel()
	watch_signals(panel)
	panel.get_node("Layout/Panel/Margin/Body/Row/HostButton").emit_signal("pressed")
	assert_signal_emitted(panel, "host_requested")


func test_join_button_emits_join_requested_with_address() -> void:
	var panel := _load_panel()
	watch_signals(panel)
	var edit := panel.get_node("Layout/Panel/Margin/Body/Row/AddressEdit") as LineEdit
	edit.text = "192.168.1.5"
	panel.get_node("Layout/Panel/Margin/Body/Row/JoinButton").emit_signal("pressed")
	assert_signal_emitted(panel, "join_requested")
	assert_signal_emitted_with_parameters(panel, "join_requested", ["192.168.1.5"])


func test_leave_button_emits_leave_requested() -> void:
	var panel := _load_panel()
	watch_signals(panel)
	panel.get_node("Layout/Panel/Margin/Body/LeaveButton").emit_signal("pressed")
	assert_signal_emitted(panel, "leave_requested")


# ---------------------------------------------------------------------------
# bind(session) status reflection
# ---------------------------------------------------------------------------


class FakeSession:
	extends RefCounted
	signal session_started(hosting: bool)
	signal session_ended
	signal peer_joined(id: int)
	signal peer_left(id: int)

	var _active := false
	var _hosting := false
	var _peers: Array = []

	func is_active() -> bool:
		return _active

	func is_host() -> bool:
		return _hosting

	func peer_ids() -> Array:
		return _peers.duplicate()

	func simulate_host() -> void:
		_active = true
		_hosting = true
		session_started.emit(true)

	func simulate_join() -> void:
		_active = true
		_hosting = false
		session_started.emit(false)

	func simulate_peer_join(id: int) -> void:
		_peers.append(id)
		peer_joined.emit(id)

	func simulate_leave() -> void:
		_active = false
		_hosting = false
		_peers.clear()
		session_ended.emit()


func _status_text(panel: SessionPanel) -> String:
	var label := panel.get_node("Layout/Panel/Margin/Body/Status") as Label
	return label.text


func test_bind_nil_shows_offline() -> void:
	var panel := _load_panel()
	panel.bind(null)
	assert_eq(_status_text(panel), "Offline", "Null session -> Offline status")


func test_bind_inactive_session_shows_offline() -> void:
	var panel := _load_panel()
	var session := FakeSession.new()
	panel.bind(session)
	assert_eq(_status_text(panel), "Offline", "Inactive session -> Offline status")


func test_bind_hosting_reflects_status() -> void:
	var panel := _load_panel()
	var session := FakeSession.new()
	panel.bind(session)
	session.simulate_host()
	var text := _status_text(panel)
	assert_true(
		text.begins_with("Hosting on :24565"),
		"Hosting session status must start with 'Hosting on :24565', got: %s" % text
	)


func test_hosting_peer_count_in_status() -> void:
	var panel := _load_panel()
	var session := FakeSession.new()
	panel.bind(session)
	session.simulate_host()
	session.simulate_peer_join(2)
	var text := _status_text(panel)
	assert_true("1 peer" in text, "Status must mention 1 peer after one join, got: %s" % text)


func test_leave_resets_to_offline() -> void:
	var panel := _load_panel()
	var session := FakeSession.new()
	panel.bind(session)
	session.simulate_host()
	session.simulate_leave()
	assert_eq(_status_text(panel), "Offline", "After leave, status returns to Offline")
