class_name SettingsApplier
extends RefCounted
## Applies [GameSettings] values to the engine: player look sensitivity, the
## master audio bus, and the window mode. Kept out of World so the mapping is
## unit-testable and World stays inside its file-size budget.

## Master bus index — bus 0 is always "Master" in Godot.
const MASTER_BUS := 0

## Floor for the linear volume so linear_to_db stays finite (~-80 dB).
const VOLUME_FLOOR := 0.0001

var _player: Player


func _init(player: Player) -> void:
	_player = player


## Apply a single setting by key (matches GameSettings.changed keys).
func apply(key: StringName, settings: GameSettings) -> void:
	match key:
		&"mouse_sensitivity":
			_player.sensitivity_scale = settings.mouse_sensitivity
		&"master_volume":
			var linear := maxf(settings.master_volume, VOLUME_FLOOR)
			AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(linear))
		&"fullscreen":
			_apply_fullscreen(settings.fullscreen)


## Apply every setting at once (used at boot after loading the file).
func apply_all(settings: GameSettings) -> void:
	for key in [&"mouse_sensitivity", &"master_volume", &"fullscreen"]:
		apply(key, settings)


## Headless runs (tests, CI) have no window — guard the DisplayServer call.
func _apply_fullscreen(enabled: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := (
		DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_mode(mode)
