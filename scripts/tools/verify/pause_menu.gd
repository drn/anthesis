# scripts/tools/verify/pause_menu.gd — SceneTree harness, NOT a GUT test.
#
# Verifies the Escape pause menu live: boots world.tscn windowed, sends a real
# Escape key event through the input pipeline, asserts the menu opens and the
# tree pauses (offline), drives a settings slider, confirms persistence, then
# closes the menu and asserts the tree resumes. Screenshots land in artifacts/.
extends SceneTree

const WORLD_SCENE := "res://scenes/world/world.tscn"

var _world: World
var _frame := 0
var _failed := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	_world = load(WORLD_SCENE).instantiate()
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1

	if _frame == 150:
		_snap("res://artifacts/verify-pause-menu-before.png")
		_press_escape()

	if _frame == 170:
		_check_menu_open()

	if _frame == 220:
		_snap("res://artifacts/verify-pause-menu-open.png")
		_drive_settings()

	if _frame == 240:
		_snap("res://artifacts/verify-pause-menu-settings.png")
		_press_escape()

	if _frame == 260:
		_check_menu_closed()
		if _failed:
			print("VERIFY_FAIL see CHECK lines above")
		else:
			print("VERIFY_OK frame=%d" % _frame)
		return true
	return false


func _menu() -> PauseMenu:
	return _world.hud().get_node("PauseMenu") as PauseMenu


func _press_escape() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)


func _check(label: String, ok: bool) -> void:
	print("CHECK %s: %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		_failed = true


func _check_menu_open() -> void:
	_check("menu visible after Escape", _menu().visible)
	_check("tree paused while menu open (offline)", paused)
	var grid := _menu().get_node("%BindingsGrid") as GridContainer
	_check("bindings grid populated", grid.get_child_count() == PauseMenu.BINDINGS.size() * 2)
	_check("mouse visible", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)


func _drive_settings() -> void:
	var slider := _menu().get_node("%SensitivitySlider") as HSlider
	slider.value = 2.0
	var settings: GameSettings = _world.get("_settings")
	_check("slider drives GameSettings", is_equal_approx(settings.mouse_sensitivity, 2.0))
	_check("setting applied to player", is_equal_approx(_world.player().sensitivity_scale, 2.0))
	_check(
		"settings persisted to user://settings.cfg",
		FileAccess.file_exists(GameSettings.DEFAULT_PATH)
	)
	# Restore the default so repeated verify runs start clean.
	slider.value = 1.0


func _check_menu_closed() -> void:
	_check("menu hidden after second Escape", not _menu().visible)
	_check("tree unpaused after close", not paused)
	_check("mouse recaptured", Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


func _snap(path: String) -> void:
	var img := root.get_texture().get_image()
	var absolute := ProjectSettings.globalize_path(path)
	var err := img.save_png(absolute)
	print("SNAP %s err=%d" % [absolute, err])
