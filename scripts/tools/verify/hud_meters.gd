# scripts/tools/verify/hud_meters.gd — SceneTree harness, NOT a GUT test.
#
# Boots the real world windowed and walks the HP/Lumen energy meters through
# their visual states: full, mid (damage taken), low (alarm pulse), and a
# lumen drain after casting. Snaps a PNG per state under /tmp/anthesis-verify.
#
# Run:
#   HOME=/tmp/anthesis-home tools/godot/macos_editor.app/Contents/MacOS/Godot \
#     --path . -s res://scripts/tools/verify/hud_meters.gd
extends SceneTree

const WORLD_SCENE := "res://scenes/world/world.tscn"
const SNAP_DIR := "/tmp/anthesis-verify"
const MID_DAMAGE := 18.0
const LOW_DAMAGE := 18.0

var _world: World
var _frame := 0
var _failed := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SNAP_DIR)
	_world = load(WORLD_SCENE).instantiate()
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1

	# Let terrain stream and the player land; top the well up so both orbs
	# start visibly full, and grant items so the quick belt shows stacks.
	if _frame == 200:
		_world.lumen_well().add(100.0)
		_world.inventory().add(&"soil", 12)
		_world.inventory().add(&"crystal_shard", 3)
	if _frame == 240:
		_snap("1_full")

	# Mid health: 40 -> 22 through the command path (knockback zero so the
	# player stays framed).
	if _frame == 250:
		_damage_player(MID_DAMAGE)
	if _frame == 300:
		_check_hp(22.0, "mid")
		_snap("2_mid")

	# Low health (alarm pulse) + lumen drain from a real cast.
	if _frame == 310:
		_damage_player(LOW_DAMAGE)
		var ability := AbilityRegistry.new().ability(&"shape_burst")
		var before := _world.lumen_well().current()
		_world.command_bus().execute(CastCommand.new(ability, _world.player().global_position))
		if _world.lumen_well().current() >= before:
			_fail("cast did not drain the lumen well")
	if _frame == 360:
		_check_hp(4.0, "low")
		_snap("3_low_pulse")

	if _frame == 380:
		if _failed:
			print("VERIFY_FAIL hud_meters")
		else:
			print("VERIFY_OK hud_meters")
		return true
	return false


func _damage_player(amount: float) -> void:
	var id := _world.player().get_instance_id()
	_world.command_bus().execute(DamageCommand.new(id, amount, Vector3.ZERO))


func _check_hp(expected: float, label: String) -> void:
	var current := _world.player_health().current()
	if absf(current - expected) > 0.01:
		_fail("%s hp expected %.1f got %.1f" % [label, expected, current])


func _fail(reason: String) -> void:
	_failed = true
	print("VERIFY_FAIL_REASON %s" % reason)


func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/hud_meters_%s.png" % [SNAP_DIR, name]
	var err := img.save_png(path)
	print("SNAP %s err=%d" % [path, err])
