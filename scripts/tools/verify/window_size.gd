# scripts/tools/verify/window_size.gd — SceneTree harness, NOT a GUT test.
#
# Boots the real world windowed, waits for terrain, snaps the framebuffer, and
# reports the window/viewport size so the configured 1920x1080 default can be
# verified live. Screenshot lands in artifacts/.
extends SceneTree

const WORLD_SCENE := "res://scenes/world/world.tscn"

var _world: World
var _frame := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	_world = load(WORLD_SCENE).instantiate()
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1

	# ~3s at 60fps — enough for terrain to stream in and the HUD to settle.
	if _frame == 180:
		var window_size := DisplayServer.window_get_size()
		var viewport_size := root.size
		print("WINDOW_SIZE %d x %d" % [window_size.x, window_size.y])
		print("VIEWPORT_SIZE %d x %d" % [viewport_size.x, viewport_size.y])
		_snap("res://artifacts/window-size.png")
		if viewport_size.x == 1920 and viewport_size.y == 1080:
			print("VERIFY_OK frame=%d" % _frame)
		else:
			print("VERIFY_FAIL expected 1920x1080, got %s" % viewport_size)
		return true
	return false


func _snap(path: String) -> void:
	var img := root.get_texture().get_image()
	print("FRAMEBUFFER %d x %d" % [img.get_width(), img.get_height()])
	var absolute := ProjectSettings.globalize_path(path)
	var err := img.save_png(absolute)
	print("SNAP %s err=%d" % [absolute, err])
