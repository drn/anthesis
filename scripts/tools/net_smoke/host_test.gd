# Two-instance live network smoke test — HOST side (Phase 7 contract #10).
#
# This is a SceneTree script, NOT part of the GUT suite. It boots the real
# world.tscn, hosts a session on port 24571, waits for one client to connect,
# then submits a DigCommand through the CommandRouter. As the authoritative
# host the router validates -> executes -> logs -> broadcasts commit_command to
# the peer. After 8 seconds it prints "HOST_OK <log_size>" and quits.
#
# Run BOTH processes on loopback (host first, then client):
#
#   export HOME=/tmp/anthesis-home
#   GODOT="tools/godot/macos_editor.app/Contents/MacOS/Godot"
#   "$GODOT" --headless --path . -s res://scripts/tools/net_smoke/host_test.gd &
#   sleep 1
#   "$GODOT" --headless --path . -s res://scripts/tools/net_smoke/client_test.gd
#
# Success criteria: host prints HOST_OK (log size >= 1), client prints
# CLIENT_GOT_DIG. The DigCommand's voxel edit may no-op headless (chunks have
# not streamed) — this test asserts the REPLICATION path, not the terrain edit.
extends SceneTree

const PORT := 24571
const WORLD_SCENE := "res://scenes/world/world.tscn"
const RUN_SECONDS := 8.0

var _world: World
var _elapsed := 0.0
var _peer_seen := false
var _dig_sent := false
var _started := false


func _initialize() -> void:
	_world = load(WORLD_SCENE).instantiate()
	root.add_child(_world)


## Begin hosting on the first frame, once World._ready() has built the net layer.
func _begin() -> void:
	var session := _world.session()
	session.peer_joined.connect(_on_peer_joined)
	var err := session.host(PORT)
	if err != OK:
		print("HOST_FAIL host() error=%d" % err)
		quit(1)
		return
	print("HOST_LISTENING on :%d" % PORT)


func _on_peer_joined(id: int) -> void:
	_peer_seen = true
	print("HOST_PEER_JOINED %d" % id)


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_begin()
	_elapsed += delta

	# Once a client is connected, commit one DigCommand through the router.
	if _peer_seen and not _dig_sent:
		_dig_sent = true
		_world.router().submit(DigCommand.new(Vector3(0.0, 0.0, 0.0), 2.0))
		print("HOST_DIG_SUBMITTED")

	if _elapsed >= RUN_SECONDS:
		var size := _world.command_log().size()
		print("HOST_OK %d" % size)
		quit(0)
		return true
	return false
