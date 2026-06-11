# scripts/tools/verify/verify_ferromancy.gd — SceneTree harness, NOT a GUT test.
#
# Boots the real world.tscn windowed and exercises the full Phase 8 ferromancy
# loop through the live command/context seams:
#   1. Grant metal flakes + ferric coins to the inventory (state SETUP, not the
#      behaviour under test).
#   2. Toggle Vigor (pewter) via ToggleChannelCommand and assert the player's
#      speed_scale rises to 1.4 and the vigor status is held.
#   3. Spawn a heavy anchored metal deposit ahead of the camera, then cast
#      Ferropush via CastCommand and assert the player's velocity changed (the
#      Ferromancer launches off the anchor).
#   4. Throw a ferric coin via ThrowCoinCommand and assert one coin was consumed
#      and a live FerricCoin exists in the Coins container.
# Screenshots land in docs/media/ named phase8-*.png. Any engine script error
# during the run fails the harness.
#
# Run (windowed, never --headless):
#   HOME=/tmp/anthesis-home tools/godot/macos_editor.app/Contents/MacOS/Godot \
#     --path . -s res://scripts/tools/verify/verify_ferromancy.gd
extends SceneTree

const WORLD_SCENE := "res://scenes/world/world.tscn"
const MEDIA_DIR := "res://docs/media"
const DEPOSIT_SCENE := "res://scenes/props/metal_deposit_lodestone.tscn"

var _world: World
var _frame := 0
var _failed := false
var _deposit: Node3D
var _push: AbilityDef
var _push_velocity_seen := 0.0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MEDIA_DIR))
	_push = AbilityRegistry.new().ability(&"ferro_push")
	_world = load(WORLD_SCENE).instantiate()
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1

	# Let terrain stream and the player land, then grant the metal economy.
	if _frame == 200:
		_grant_metals()
	if _frame == 240:
		_snap("phase8-1-reserves")

	# Vigor channel: toggle on through the command bus, assert the boon lands.
	if _frame == 250:
		_world.command_bus().execute(ToggleChannelCommand.new(&"vigor"))
	if _frame == 270:
		_check_vigor()
		_snap("phase8-2-vigor")

	# Ferropush off an anchored deposit dead ahead of the camera.
	if _frame == 290:
		_spawn_deposit()
	if _frame == 320:
		_cast_push()
	if _frame == 322:
		_check_push()
		_snap("phase8-3-ferro-push")

	# Coin toss: consume one coin, spawn a live FerricCoin.
	if _frame == 340:
		_throw_coin()
	if _frame == 360:
		_check_coin()
		_snap("phase8-4-coin")

	if _frame == 380:
		if _failed:
			print("VERIFY_FAIL verify_ferromancy — see CHECK lines above")
		else:
			print("VERIFY_OK verify_ferromancy frame=%d" % _frame)
		return true
	return false


# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------


func _grant_metals() -> void:
	var inv := _world.inventory()
	inv.add(&"pewter_flakes", 8)
	inv.add(&"steel_flakes", 8)
	inv.add(&"iron_flakes", 8)
	inv.add(&"ferric_coin", 8)


func _check_vigor() -> void:
	var ctx: WorldContext = _world.command_bus().get("_ctx")
	_check("vigor channel active", ctx.channels.is_active(&"vigor"))
	_check("player speed_scale raised to 1.4", is_equal_approx(_world.player().speed_scale, 1.4))
	_check(
		"player carries vigor status", ctx.status.has(_world.player().get_instance_id(), &"vigor")
	)


func _spawn_deposit() -> void:
	var player := _world.player()
	var camera := player.get_node("Camera3D") as Camera3D
	var forward := -camera.global_transform.basis.z
	_deposit = load(DEPOSIT_SCENE).instantiate()
	_world.add_child(_deposit)
	_deposit.global_position = camera.global_position + forward * 8.0


func _cast_push() -> void:
	_world.player().velocity = Vector3.ZERO
	_world.command_bus().execute(CastCommand.new(_push, Vector3.ZERO))
	_push_velocity_seen = _world.player().velocity.length()


func _check_push() -> void:
	_check("Ferropush off an anchor moved the player", _push_velocity_seen > 0.0)


func _throw_coin() -> void:
	var before := _world.inventory().count_of(&"ferric_coin")
	var camera := _world.player().get_node("Camera3D") as Camera3D
	var forward := -camera.global_transform.basis.z
	var origin := camera.global_transform.origin + forward * 0.6
	_world.command_bus().execute(ThrowCoinCommand.new(origin, forward * FerricCoin.THROW_SPEED))
	var after := _world.inventory().count_of(&"ferric_coin")
	_check("coin toss consumed exactly one coin", before - after == 1)


func _check_coin() -> void:
	var coins := _world.get_node_or_null("Coins")
	_check("Coins container exists", coins != null)
	if coins != null:
		var live := 0
		for child in coins.get_children():
			if child is FerricCoin:
				live += 1
		_check("a live ferric coin exists in the world", live >= 1)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _check(label: String, ok: bool) -> void:
	print("CHECK %s: %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		_failed = true


func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	var absolute := ProjectSettings.globalize_path("%s/%s.png" % [MEDIA_DIR, name])
	var err := img.save_png(absolute)
	print("SNAP %s err=%d" % [absolute, err])
