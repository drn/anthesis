class_name SessionPanel
extends Control
## Multiplayer session panel. Hidden by default, toggled by action toggle_session (M).
##
## Shows connection status, an address field, and Host / Join / Leave buttons.
## Emits signals for all three actions — never calls NetworkSession directly.
## World wires the signals and calls bind(session) to keep the status line current.

## Emitted when the user clicks Host.
signal host_requested
## Emitted when the user clicks Join with the entered address.
signal join_requested(address: String)
## Emitted when the user clicks Leave.
signal leave_requested

const DEFAULT_ADDRESS := "127.0.0.1"

## Bound NetworkSession (may be null until bind() is called).
var _session: Object = null

@onready var _status_label: Label = $Layout/Panel/Margin/Body/Status
@onready var _address_edit: LineEdit = $Layout/Panel/Margin/Body/Row/AddressEdit
@onready var _host_button: Button = $Layout/Panel/Margin/Body/Row/HostButton
@onready var _join_button: Button = $Layout/Panel/Margin/Body/Row/JoinButton
@onready var _leave_button: Button = $Layout/Panel/Margin/Body/LeaveButton


func _ready() -> void:
	visible = false
	_address_edit.text = DEFAULT_ADDRESS
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	_refresh_status()


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("toggle_session") and event.is_action_pressed("toggle_session"):
		_toggle_panel()
		get_viewport().set_input_as_handled()


## Bind a NetworkSession so the status line reflects live state.
## session may be null — the panel degrades to showing "Offline".
func bind(session: Object) -> void:
	if _session != null:
		_disconnect_session_signals()
	_session = session
	if _session != null:
		_connect_session_signals()
	_refresh_status()


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------


func _on_host_pressed() -> void:
	host_requested.emit()


func _on_join_pressed() -> void:
	join_requested.emit(_address_edit.text)


func _on_leave_pressed() -> void:
	leave_requested.emit()


func _on_session_started(_hosting: bool) -> void:
	_refresh_status()


func _on_session_ended() -> void:
	_refresh_status()


func _on_peer_joined(_id: int) -> void:
	_refresh_status()


func _on_peer_left(_id: int) -> void:
	_refresh_status()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


func _toggle_panel() -> void:
	var now_visible := not visible
	visible = now_visible
	if now_visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _refresh_status() -> void:
	if _status_label == null:
		return
	_status_label.text = _status_text()


func _status_text() -> String:
	if _session == null or not _session.has_method("is_active"):
		return "Offline"
	if not _session.is_active():
		return "Offline"
	if _session.has_method("is_host") and _session.is_host():
		var peer_count := 0
		if _session.has_method("peer_ids"):
			peer_count = _session.peer_ids().size()
		return "Hosting on :24565 — %d peer%s" % [peer_count, "s" if peer_count != 1 else ""]
	# Connected as client.
	var addr := _address_edit.text if _address_edit != null else "?"
	return "Connected to %s" % addr


func _connect_session_signals() -> void:
	if _session.has_signal("session_started"):
		_session.session_started.connect(_on_session_started)
	if _session.has_signal("session_ended"):
		_session.session_ended.connect(_on_session_ended)
	if _session.has_signal("peer_joined"):
		_session.peer_joined.connect(_on_peer_joined)
	if _session.has_signal("peer_left"):
		_session.peer_left.connect(_on_peer_left)


func _disconnect_session_signals() -> void:
	if (
		_session.has_signal("session_started")
		and _session.session_started.is_connected(_on_session_started)
	):
		_session.session_started.disconnect(_on_session_started)
	if (
		_session.has_signal("session_ended")
		and _session.session_ended.is_connected(_on_session_ended)
	):
		_session.session_ended.disconnect(_on_session_ended)
	if _session.has_signal("peer_joined") and _session.peer_joined.is_connected(_on_peer_joined):
		_session.peer_joined.disconnect(_on_peer_joined)
	if _session.has_signal("peer_left") and _session.peer_left.is_connected(_on_peer_left):
		_session.peer_left.disconnect(_on_peer_left)
