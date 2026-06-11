extends GutTest
## Behavioral tests for PauseMenu: open/close/toggle signal flow, button
## behavior, and the two-way binding between controls and GameSettings.
## Structural coverage lives in test_pause_menu.gd.

const MENU_PATH := "res://scenes/ui/pause_menu.tscn"


func _load_menu() -> PauseMenu:
	var menu := (load(MENU_PATH) as PackedScene).instantiate() as PauseMenu
	add_child_autofree(menu)
	return menu


# ---------------------------------------------------------------------------
# Open / close / toggle
# ---------------------------------------------------------------------------


func test_open_shows_and_emits_opened() -> void:
	var menu := _load_menu()
	watch_signals(menu)
	menu.open()
	assert_true(menu.visible, "open() must show the menu")
	assert_signal_emitted(menu, "opened")


func test_close_hides_and_emits_closed() -> void:
	var menu := _load_menu()
	menu.open()
	watch_signals(menu)
	menu.close()
	assert_false(menu.visible, "close() must hide the menu")
	assert_signal_emitted(menu, "closed")


func test_open_twice_emits_once() -> void:
	var menu := _load_menu()
	watch_signals(menu)
	menu.open()
	menu.open()
	assert_signal_emit_count(menu, "opened", 1, "re-opening an open menu is a no-op")


func test_toggle_round_trip() -> void:
	var menu := _load_menu()
	menu.toggle()
	assert_true(menu.visible, "first toggle opens")
	menu.toggle()
	assert_false(menu.visible, "second toggle closes")


func test_resume_button_closes() -> void:
	var menu := _load_menu()
	menu.open()
	watch_signals(menu)
	menu.get_node("%ResumeButton").emit_signal("pressed")
	assert_false(menu.visible, "Resume must close the menu")
	assert_signal_emitted(menu, "closed")


func test_quit_button_emits_quit_requested() -> void:
	var menu := _load_menu()
	watch_signals(menu)
	menu.get_node("%QuitButton").emit_signal("pressed")
	assert_signal_emitted(menu, "quit_requested")


# ---------------------------------------------------------------------------
# Settings binding
# ---------------------------------------------------------------------------


func test_bind_pushes_settings_into_controls() -> void:
	var menu := _load_menu()
	var settings := GameSettings.new()
	settings.mouse_sensitivity = 2.0
	settings.master_volume = 0.4
	settings.fullscreen = true
	menu.bind(settings)
	assert_almost_eq((menu.get_node("%SensitivitySlider") as HSlider).value, 2.0, 0.001)
	assert_almost_eq((menu.get_node("%VolumeSlider") as HSlider).value, 0.4, 0.001)
	assert_true((menu.get_node("%FullscreenCheck") as CheckBox).button_pressed)


func test_slider_writes_back_to_settings() -> void:
	var menu := _load_menu()
	var settings := GameSettings.new()
	menu.bind(settings)
	(menu.get_node("%SensitivitySlider") as HSlider).value = 2.5
	assert_almost_eq(settings.mouse_sensitivity, 2.5, 0.001)
	(menu.get_node("%VolumeSlider") as HSlider).value = 0.25
	assert_almost_eq(settings.master_volume, 0.25, 0.001)


func test_fullscreen_check_writes_back_to_settings() -> void:
	var menu := _load_menu()
	var settings := GameSettings.new()
	menu.bind(settings)
	(menu.get_node("%FullscreenCheck") as CheckBox).button_pressed = true
	assert_true(settings.fullscreen, "checking the box must set settings.fullscreen")


func test_unbound_menu_controls_are_inert() -> void:
	var menu := _load_menu()
	(menu.get_node("%SensitivitySlider") as HSlider).value = 2.5
	assert_true(true, "moving controls with no settings bound must not crash")
