# Two-instance live network smoke test — CLIENT side (Phase 7 contract #10).
#
# This is a SceneTree script, NOT part of the GUT suite. It boots the real
# world.tscn, joins the host on 127.0.0.1:24571, and (via World's
# session_started wiring) requests the host's state snapshot for late join.
# When the host broadcasts a commit_command (the DigCommand the host submits
# once this client connects), the CommandRouter applies it through the bus,
# emitting command_executed. This script listens on that signal and prints
# "CLIENT_GOT_DIG" on the first DigCommand, then quits.
#
# Run AFTER the host (see host_test.gd header for the full invocation):
#
#   export HOME=/tmp/anthesis-home
#   GODOT="tools/godot/macos_editor.app/Contents/MacOS/Godot"
#   "$GODOT" --headless --path . -s res://scripts/tools/net_smoke/client_test.gd
#
# Success: prints CLIENT_GOT_DIG. Times out with CLIENT_TIMEOUT after 12 s.
extends SceneTree

const ADDRESS := "127.0.0.1"
const PORT := 24571
const WORLD_SCENE := "res://scenes/world/world.tscn"
const TIMEOUT_SECONDS := 12.0

var _world: World
var _elapsed := 0.0
var _got_dig := false
var _started := false


func _initialize() -> void:
	_world = load(WORLD_SCENE).instantiate()
	root.add_child(_world)


## Join on the first frame, once World._ready() has built the net layer.
func _begin() -> void:
	# Observe applied commands: the host's broadcast commit_command decodes and
	# executes through the bus, which emits command_executed on this client.
	_world.command_bus().command_executed.connect(_on_command_executed)
	var err := _world.session().join(ADDRESS, PORT)
	if err != OK:
		print("CLIENT_FAIL join() error=%d" % err)
		quit(1)
		return
	print("CLIENT_JOINING %s:%d" % [ADDRESS, PORT])


func _on_command_executed(cmd: WorldCommand) -> void:
	if cmd is DigCommand and not _got_dig:
		_got_dig = true
		print("CLIENT_GOT_DIG")
		quit(0)


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		_begin()
	_elapsed += delta
	if _got_dig:
		return true
	if _elapsed >= TIMEOUT_SECONDS:
		print("CLIENT_TIMEOUT")
		quit(1)
		return true
	return false
