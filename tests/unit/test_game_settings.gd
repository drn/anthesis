extends GutTest
## Unit tests for GameSettings: defaults, clamping, change signals, and
## ConfigFile persistence round-trips.

const TEST_PATH := "user://test_settings.cfg"


func after_each() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_PATH)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)


# ---------------------------------------------------------------------------
# Defaults + clamping
# ---------------------------------------------------------------------------


func test_defaults() -> void:
	var settings := GameSettings.new()
	assert_eq(settings.mouse_sensitivity, 1.0, "default sensitivity is 1.0x")
	assert_eq(settings.master_volume, 1.0, "default master volume is full")
	assert_false(settings.fullscreen, "default is windowed")


func test_sensitivity_clamped_low() -> void:
	var settings := GameSettings.new()
	settings.mouse_sensitivity = 0.01
	assert_eq(settings.mouse_sensitivity, GameSettings.MIN_SENSITIVITY)


func test_sensitivity_clamped_high() -> void:
	var settings := GameSettings.new()
	settings.mouse_sensitivity = 99.0
	assert_eq(settings.mouse_sensitivity, GameSettings.MAX_SENSITIVITY)


func test_volume_clamped_to_unit_range() -> void:
	var settings := GameSettings.new()
	settings.master_volume = -0.5
	assert_eq(settings.master_volume, 0.0, "volume clamps at 0")
	settings.master_volume = 2.0
	assert_eq(settings.master_volume, 1.0, "volume clamps at 1")


# ---------------------------------------------------------------------------
# Change signal
# ---------------------------------------------------------------------------


func test_changed_emitted_with_key_and_value() -> void:
	var settings := GameSettings.new()
	watch_signals(settings)
	settings.mouse_sensitivity = 2.0
	assert_signal_emitted_with_parameters(settings, "changed", [&"mouse_sensitivity", 2.0])


func test_changed_emitted_for_each_setting() -> void:
	var settings := GameSettings.new()
	watch_signals(settings)
	settings.master_volume = 0.5
	settings.fullscreen = true
	assert_signal_emit_count(settings, "changed", 2)


func test_setting_same_value_does_not_emit() -> void:
	var settings := GameSettings.new()
	watch_signals(settings)
	settings.mouse_sensitivity = 1.0
	settings.master_volume = 1.0
	settings.fullscreen = false
	assert_signal_emit_count(settings, "changed", 0, "no-op writes must not emit")


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------


func test_save_load_round_trip() -> void:
	var settings := GameSettings.new()
	settings.mouse_sensitivity = 1.8
	settings.master_volume = 0.35
	settings.fullscreen = true
	assert_eq(settings.save_to_file(TEST_PATH), OK, "save must succeed")

	var loaded := GameSettings.new()
	assert_eq(loaded.load_from_file(TEST_PATH), OK, "load must succeed")
	assert_almost_eq(loaded.mouse_sensitivity, 1.8, 0.001)
	assert_almost_eq(loaded.master_volume, 0.35, 0.001)
	assert_true(loaded.fullscreen)


func test_load_missing_file_keeps_defaults() -> void:
	var settings := GameSettings.new()
	var err := settings.load_from_file("user://does_not_exist.cfg")
	assert_ne(err, OK, "loading a missing file reports an error")
	assert_eq(settings.mouse_sensitivity, 1.0, "defaults survive a failed load")
	assert_eq(settings.master_volume, 1.0)
	assert_false(settings.fullscreen)


func test_loaded_values_are_clamped() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "mouse_sensitivity", 50.0)
	cfg.set_value("settings", "master_volume", -3.0)
	cfg.save(TEST_PATH)

	var settings := GameSettings.new()
	settings.load_from_file(TEST_PATH)
	assert_eq(settings.mouse_sensitivity, GameSettings.MAX_SENSITIVITY, "tampered file clamps")
	assert_eq(settings.master_volume, 0.0)
