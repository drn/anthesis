## Broadcasts the local player's position + yaw to peers and manages
## [RemotePlayer] avatar nodes for every connected peer.
##
## Wired by World after [NetworkSession] is set up:
##   player_sync.setup(session, player_node, avatar_container)
##
## Transport is rpc-thin: [method sync_state] is the only @rpc method; all
## logic lives in [method _apply_remote_state] so tests drive it without a
## live multiplayer peer.
##
## Broadcast cadence: a [Timer] fires every 0.1 s and calls [method _broadcast].
## On [signal NetworkSession.peer_left] the avatar is freed immediately.
## On [signal NetworkSession.session_ended] all avatars are cleared.
class_name PlayerSync
extends Node

## Seconds between position broadcasts.
const BROADCAST_INTERVAL := 0.1

## Packed scene used to spawn [RemotePlayer] avatars on demand.
const REMOTE_PLAYER_SCENE := preload("res://scenes/net/remote_player.tscn")

var _session: Object  # NetworkSession (duck-typed to avoid circular dep)
var _local_player: Node3D
var _avatar_container: Node3D

## peer_id -> RemotePlayer node
var _avatars: Dictionary = {}

var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.name = "BroadcastTimer"
	_timer.wait_time = BROADCAST_INTERVAL
	_timer.autostart = false
	_timer.timeout.connect(_broadcast)
	add_child(_timer)


## Wire this system to the live session and scene nodes.
## Must be called before the session becomes active to ensure signal connections.
func setup(session: Object, local_player: Node3D, avatar_container: Node3D) -> void:
	_session = session
	_local_player = local_player
	_avatar_container = avatar_container

	if _session != null:
		if _session.has_signal("peer_joined"):
			_session.peer_joined.connect(_on_peer_joined)
		if _session.has_signal("peer_left"):
			_session.peer_left.connect(_on_peer_left)
		if _session.has_signal("session_ended"):
			_session.session_ended.connect(_on_session_ended)
		if _session.has_signal("session_started"):
			_session.session_started.connect(_on_session_started)


# ---------------------------------------------------------------------------
# Broadcast
# ---------------------------------------------------------------------------


func _broadcast() -> void:
	if _session == null or not _session.is_active():
		return
	if _local_player == null:
		return
	var pos := _local_player.global_position
	var yaw := _local_player.rotation.y
	sync_state.rpc(pos, yaw)


# ---------------------------------------------------------------------------
# RPC — thin transport seam
# ---------------------------------------------------------------------------

## Receives a remote player's position + yaw.  Receiving side identifies the
## sender via [method MultiplayerAPI.get_remote_sender_id] and delegates to
## [method _apply_remote_state] — all logic stays testable without networking.
@rpc("any_peer", "call_remote", "unreliable")
func sync_state(pos: Vector3, yaw: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_apply_remote_state(sender, pos, yaw)


# ---------------------------------------------------------------------------
# Core logic (testable without networking)
# ---------------------------------------------------------------------------


## Ensure a [RemotePlayer] avatar exists for [param peer_id], then update it.
## Spawns on demand so the first packet implicitly creates the avatar.
func _apply_remote_state(peer_id: int, pos: Vector3, yaw: float) -> void:
	if _avatar_container == null:
		return
	if not _avatars.has(peer_id):
		_spawn_avatar(peer_id)
	var avatar: RemotePlayer = _avatars[peer_id]
	avatar.update_state(pos, yaw)


func _spawn_avatar(peer_id: int) -> void:
	var avatar: RemotePlayer = REMOTE_PLAYER_SCENE.instantiate() as RemotePlayer
	avatar.set_peer_id(peer_id)
	_avatar_container.add_child(avatar)
	_avatars[peer_id] = avatar


func _free_avatar(peer_id: int) -> void:
	if _avatars.has(peer_id):
		var avatar: RemotePlayer = _avatars[peer_id]
		if is_instance_valid(avatar):
			avatar.queue_free()
		_avatars.erase(peer_id)


func _clear_all_avatars() -> void:
	for id in _avatars.keys():
		_free_avatar(id)
	_avatars.clear()


# ---------------------------------------------------------------------------
# Session signal handlers
# ---------------------------------------------------------------------------


func _on_session_started(_hosting: bool) -> void:
	_timer.start()


func _on_peer_joined(_peer_id: int) -> void:
	# Avatar spawns on first packet — nothing to do here proactively.
	pass


func _on_peer_left(peer_id: int) -> void:
	_free_avatar(peer_id)


func _on_session_ended() -> void:
	_timer.stop()
	_clear_all_avatars()
