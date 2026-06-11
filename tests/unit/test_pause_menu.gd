extends GutTest
## Structural tests for PauseMenu: default visibility, settings controls, and
## the key bindings list generated from the live InputMap.
## Behavioral coverage (open/close/buttons/settings) lives in
## test_pause_menu_behavior.gd to respect the public-methods-per-file budget.

const MENU_PATH := "res://scenes/ui/pause_menu.tscn"


func _load_menu() -> PauseMenu:
	var menu := (load(MENU_PATH) as PackedScene).instantiate() as PauseMenu
	add_child_autofree(menu)
	return menu


# ---------------------------------------------------------------------------
# Structural assertions
# ---------------------------------------------------------------------------


func test_scene_loads() -> void:
	assert_not_null(load(MENU_PATH), "pause_menu.tscn must load")


func test_root_is_pause_menu() -> void:
	var menu := _load_menu()
	assert_true(menu is PauseMenu, "Root must carry the PauseMenu script")


func test_hidden_by_default() -> void:
	var menu := _load_menu()
	assert_false(menu.visible, "PauseMenu must be hidden by default")


func test_processes_while_paused() -> void:
	var menu := _load_menu()
	assert_eq(
		menu.process_mode,
		Node.PROCESS_MODE_ALWAYS,
		"PauseMenu must process while the tree is paused so Escape can close it"
	)


func test_has_resume_and_quit_buttons() -> void:
	var menu := _load_menu()
	assert_not_null(menu.get_node_or_null("%ResumeButton"), "menu must have a ResumeButton")
	assert_not_null(menu.get_node_or_null("%QuitButton"), "menu must have a QuitButton")


func test_has_settings_controls() -> void:
	var menu := _load_menu()
	assert_true(menu.get_node_or_null("%SensitivitySlider") is HSlider)
	assert_true(menu.get_node_or_null("%VolumeSlider") is HSlider)
	assert_true(menu.get_node_or_null("%FullscreenCheck") is CheckBox)


func test_sensitivity_slider_matches_settings_range() -> void:
	var menu := _load_menu()
	var slider := menu.get_node("%SensitivitySlider") as HSlider
	assert_eq(slider.min_value, GameSettings.MIN_SENSITIVITY)
	assert_eq(slider.max_value, GameSettings.MAX_SENSITIVITY)


# ---------------------------------------------------------------------------
# Key bindings list
# ---------------------------------------------------------------------------


func test_bindings_grid_lists_every_action() -> void:
	var menu := _load_menu()
	var grid := menu.get_node("%BindingsGrid") as GridContainer
	assert_eq(
		grid.get_child_count(),
		PauseMenu.BINDINGS.size() * 2,
		"grid must hold a label + key pair per binding"
	)


func test_binding_text_resolves_keyboard_keys() -> void:
	assert_eq(PauseMenu.binding_text(&"move_forward"), "W")
	assert_eq(PauseMenu.binding_text(&"jump"), "Space")
	assert_eq(PauseMenu.binding_text(&"toggle_menu"), "Escape")


func test_binding_text_resolves_mouse_buttons() -> void:
	assert_eq(PauseMenu.binding_text(&"dig"), "Left Mouse")
	assert_eq(PauseMenu.binding_text(&"place"), "Right Mouse")


func test_binding_text_unknown_action_is_dash() -> void:
	assert_eq(PauseMenu.binding_text(&"no_such_action"), "—")


func test_every_listed_binding_resolves() -> void:
	for entry in PauseMenu.BINDINGS:
		var text := PauseMenu.binding_text(entry[0])
		assert_ne(text, "—", "action %s must resolve to a key" % entry[0])
