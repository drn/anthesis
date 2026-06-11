class_name GameSettings
extends RefCounted
## Player-adjustable settings: mouse sensitivity, master volume, fullscreen.
##
## Pure model + ConfigFile persistence. Holds no engine state — World listens
## to [signal changed] and applies each value to the player / AudioServer /
## DisplayServer, so this class stays trivially testable headless.

## Emitted whenever a setting actually changes value. key is one of
## &"mouse_sensitivity", &"master_volume", &"fullscreen".
signal changed(key: StringName, value: Variant)

## Where settings persist between runs.
const DEFAULT_PATH := "user://settings.cfg"

## Mouse-look sensitivity multiplier bounds (1.0 = default feel).
const MIN_SENSITIVITY := 0.2
const MAX_SENSITIVITY := 3.0

const _SECTION := "settings"

## Mouse-look sensitivity multiplier, clamped to [MIN_SENSITIVITY, MAX_SENSITIVITY].
var mouse_sensitivity := 1.0:
	set(value):
		value = clampf(value, MIN_SENSITIVITY, MAX_SENSITIVITY)
		if is_equal_approx(mouse_sensitivity, value):
			return
		mouse_sensitivity = value
		changed.emit(&"mouse_sensitivity", value)

## Master bus volume, linear 0..1.
var master_volume := 1.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if is_equal_approx(master_volume, value):
			return
		master_volume = value
		changed.emit(&"master_volume", value)

## Fullscreen window when true, windowed when false.
var fullscreen := false:
	set(value):
		if fullscreen == value:
			return
		fullscreen = value
		changed.emit(&"fullscreen", value)


## Persist all settings to [param path] in ConfigFile format.
func save_to_file(path: String = DEFAULT_PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value(_SECTION, "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value(_SECTION, "master_volume", master_volume)
	cfg.set_value(_SECTION, "fullscreen", fullscreen)
	return cfg.save(path)


## Load settings from [param path]. A missing file or missing keys leave the
## current values untouched (first run keeps the defaults). Loaded values pass
## through the setters, so they are clamped and emit [signal changed].
func load_from_file(path: String = DEFAULT_PATH) -> Error:
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return err
	mouse_sensitivity = cfg.get_value(_SECTION, "mouse_sensitivity", mouse_sensitivity)
	master_volume = cfg.get_value(_SECTION, "master_volume", master_volume)
	fullscreen = cfg.get_value(_SECTION, "fullscreen", fullscreen)
	return OK
