## Thin wrapper over Godot high-level multiplayer for Anthesis co-op.
##
## A NetworkSession owns the [ENetMultiplayerPeer] lifecycle and re-broadcasts
## the engine's multiplayer signals as its own, so the rest of the game can
## observe session state without reaching into [member Node.multiplayer]. The
## game defaults to OFFLINE: nothing is networked until [method host] or
## [method join] is called, and [method leave] returns to that state.
##
## Authority model (v0, documented): the host is always peer 1. Offline counts
## as "has authority" so the single-player path runs the exact same command
## flow as the host path — see [method has_authority]. This is a co-op trust
## model for friends, not anti-cheat.
class_name NetworkSession
extends Node

## Emitted when a session becomes active. [param hosting] is true for the host.
signal session_started(hosting: bool)
## Emitted when the session tears down (leave, server disconnect, or failure).
signal session_ended
## Emitted on the host when a remote [param id] connects.
signal peer_joined(id: int)
## Emitted on the host when a remote [param id] disconnects.
signal peer_left(id: int)

## Default UDP port Anthesis listens on / connects to.
const DEFAULT_PORT := 24565
## Peer id the host always holds under Godot high-level multiplayer.
const HOST_PEER_ID := 1
## Max simultaneous client connections the host accepts (host + 7 friends).
const MAX_PEERS := 8

var _peer: ENetMultiplayerPeer = null
var _active := false
var _hosting := false


## Start hosting on [param port]. Returns [constant OK] on success, else the
## [enum Error] from peer creation. Idempotent: re-hosting first leaves.
func host(port := DEFAULT_PORT) -> Error:
	if _active:
		leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_active = true
	_hosting = true
	_connect_multiplayer_signals()
	session_started.emit(true)
	return OK


## Connect to a host at [param address]:[param port]. Returns [constant OK] on
## success, else the [enum Error] from peer creation. Idempotent.
func join(address: String, port := DEFAULT_PORT) -> Error:
	if _active:
		leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	_peer = peer
	multiplayer.multiplayer_peer = peer
	_active = true
	_hosting = false
	_connect_multiplayer_signals()
	# session_started(false) is deferred until connected_to_server fires —
	# RPCs sent before the ENet handshake completes are silently dropped.
	return OK


## Tear down the active session and return to OFFLINE. Safe to call when idle.
func leave() -> void:
	if not _active:
		return
	_disconnect_multiplayer_signals()
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	_active = false
	_hosting = false
	session_ended.emit()


## True while a session (host or client) is live.
func is_active() -> bool:
	return _active


## True when this instance is the authoritative host (active and peer 1).
func is_host() -> bool:
	return _active and unique_id() == HOST_PEER_ID


## This instance's multiplayer unique id, or [constant HOST_PEER_ID] when
## offline (so offline behaves like a solo host).
func unique_id() -> int:
	if not _active:
		return HOST_PEER_ID
	return multiplayer.get_unique_id()


## True when this instance may commit authoritatively: either offline (solo) or
## the host. Clients are non-authoritative and must request commits from peer 1.
func has_authority() -> bool:
	return not _active or unique_id() == HOST_PEER_ID


## Connected peer ids (excludes self). Empty when offline.
func peer_ids() -> Array:
	if not _active:
		return []
	return Array(multiplayer.get_peers())


# ---------------------------------------------------------------------------
# Multiplayer signal bridging
# ---------------------------------------------------------------------------


func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)


func _disconnect_multiplayer_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)


func _on_connected_to_server() -> void:
	# The ENet handshake completed — RPCs to the host are now deliverable.
	session_started.emit(false)


func _on_connection_failed() -> void:
	leave()


func _on_peer_connected(id: int) -> void:
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	peer_left.emit(id)


func _on_server_disconnected() -> void:
	# The host vanished; collapse back to OFFLINE on the client.
	leave()
