extends GutTest
## Unit tests for SettingsApplier: each GameSettings key lands on the right
## engine target. Fullscreen is a guarded no-op headless, so it is only
## exercised for crash-safety.

const PLAYER_SCENE := "res://scenes/player/player.tscn"


func after_each() -> void:
	AudioServer.set_bus_volume_db(SettingsApplier.MASTER_BUS, 0.0)


func _make_player() -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	add_child_autofree(player)
	return player


func test_apply_sensitivity_updates_player() -> void:
	var player := _make_player()
	var settings := GameSettings.new()
	settings.mouse_sensitivity = 2.4
	SettingsApplier.new(player).apply(&"mouse_sensitivity", settings)
	assert_almost_eq(player.sensitivity_scale, 2.4, 0.001)


func test_apply_volume_sets_master_bus() -> void:
	var settings := GameSettings.new()
	settings.master_volume = 0.5
	SettingsApplier.new(_make_player()).apply(&"master_volume", settings)
	assert_almost_eq(
		AudioServer.get_bus_volume_db(SettingsApplier.MASTER_BUS), linear_to_db(0.5), 0.01
	)


func test_apply_zero_volume_stays_finite() -> void:
	var settings := GameSettings.new()
	settings.master_volume = 0.0
	SettingsApplier.new(_make_player()).apply(&"master_volume", settings)
	var db := AudioServer.get_bus_volume_db(SettingsApplier.MASTER_BUS)
	assert_true(is_finite(db), "muted volume must map to a finite dB, got %s" % db)


func test_apply_all_covers_every_key() -> void:
	var player := _make_player()
	var settings := GameSettings.new()
	settings.mouse_sensitivity = 1.5
	settings.master_volume = 0.8
	settings.fullscreen = true
	SettingsApplier.new(player).apply_all(settings)
	assert_almost_eq(player.sensitivity_scale, 1.5, 0.001)
	assert_almost_eq(
		AudioServer.get_bus_volume_db(SettingsApplier.MASTER_BUS), linear_to_db(0.8), 0.01
	)
	# fullscreen is a headless no-op — reaching here without a crash is the assert.
