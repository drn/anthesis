class_name PauseMenu
extends Control
## Escape pause menu: resume / quit, settings controls, and a key bindings list.
##
## Hidden by default, toggled by the toggle_menu action (Escape). The menu only
## edits the bound [GameSettings] and emits intent signals — World owns pausing
## the tree, quitting, and applying settings to the engine. The bindings list is
## generated from the live [InputMap], so it always matches project.godot.
## process_mode is ALWAYS so Escape still closes the menu while the tree is paused.

## Emitted when the menu becomes visible (Escape or open()).
signal opened
## Emitted when the menu hides (Escape, Resume, or close()).
signal closed
## Emitted when the user clicks Quit. World decides what quitting means.
signal quit_requested

## Actions shown in the key bindings list, in display order. Each entry is
## [action StringName, human label]. Keys are resolved live from InputMap.
const BINDINGS: Array = [
	[&"move_forward", "Move Forward"],
	[&"move_back", "Move Back"],
	[&"move_left", "Move Left"],
	[&"move_right", "Move Right"],
	[&"jump", "Jump"],
	[&"dig", "Dig"],
	[&"place", "Place Voxels"],
	[&"interact", "Interact / Harvest"],
	[&"strike", "Strike"],
	[&"cast_1", "Ability 1"],
	[&"cast_2", "Ability 2"],
	[&"cast_3", "Ability 3"],
	[&"toggle_inventory", "Inventory"],
	[&"place_core", "Place Sequencer Core"],
	[&"place_note", "Place Note Block"],
	[&"toggle_session", "Multiplayer Panel"],
	[&"toggle_menu", "Pause Menu"],
]

const ACTION_COLOR := Color(0.6, 0.75, 0.95, 1.0)
const KEY_COLOR := Color(0.85, 0.92, 1.0, 1.0)

## Bound GameSettings (may be null until bind() is called; controls stay inert).
var _settings: GameSettings = null

@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _sensitivity_value: Label = %SensitivityValue
@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _volume_value: Label = %VolumeValue
@onready var _fullscreen_check: CheckBox = %FullscreenCheck
@onready var _bindings_grid: GridContainer = %BindingsGrid
@onready var _resume_button: Button = %ResumeButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	visible = false
	_sensitivity_slider.min_value = GameSettings.MIN_SENSITIVITY
	_sensitivity_slider.max_value = GameSettings.MAX_SENSITIVITY
	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_resume_button.pressed.connect(close)
	_quit_button.pressed.connect(_on_quit_pressed)
	_build_bindings()
	_refresh_controls()


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("toggle_menu") and event.is_action_pressed("toggle_menu"):
		toggle()
		get_viewport().set_input_as_handled()


## Wire the controls to live settings. settings may be null — the menu still
## opens and shows bindings, but the sliders edit nothing.
func bind(settings: GameSettings) -> void:
	_settings = settings
	_refresh_controls()


## Show the menu and free the mouse. No-op when already open.
func open() -> void:
	if visible:
		return
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	opened.emit()


## Hide the menu and recapture the mouse. No-op when already closed.
func close() -> void:
	if not visible:
		return
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Human-readable key (or mouse button) for an InputMap action, e.g. "W",
## "Escape", "Left Mouse". Returns an em dash for unknown / unbound actions.
static func binding_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "—"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var code := key_event.physical_keycode
			if code == KEY_NONE:
				code = key_event.keycode
			return OS.get_keycode_string(code)
		if event is InputEventMouseButton:
			return _mouse_button_text((event as InputEventMouseButton).button_index)
	return "—"


static func _mouse_button_text(index: MouseButton) -> String:
	match index:
		MOUSE_BUTTON_LEFT:
			return "Left Mouse"
		MOUSE_BUTTON_RIGHT:
			return "Right Mouse"
		MOUSE_BUTTON_MIDDLE:
			return "Middle Mouse"
		_:
			return "Mouse %d" % index


# ---------------------------------------------------------------------------
# Settings controls
# ---------------------------------------------------------------------------


## Push bound settings values into the controls. Slider setters re-enter the
## value_changed handlers, which write the same value back — GameSettings
## setters no-op on equal values, so no signal loop forms.
func _refresh_controls() -> void:
	if _settings == null:
		return
	_sensitivity_slider.value = _settings.mouse_sensitivity
	_volume_slider.value = _settings.master_volume
	_fullscreen_check.button_pressed = _settings.fullscreen
	_update_value_labels()


func _on_sensitivity_changed(value: float) -> void:
	if _settings != null:
		_settings.mouse_sensitivity = value
	_update_value_labels()


func _on_volume_changed(value: float) -> void:
	if _settings != null:
		_settings.master_volume = value
	_update_value_labels()


func _on_fullscreen_toggled(pressed: bool) -> void:
	if _settings != null:
		_settings.fullscreen = pressed


func _on_quit_pressed() -> void:
	quit_requested.emit()


func _update_value_labels() -> void:
	_sensitivity_value.text = "%.2fx" % _sensitivity_slider.value
	_volume_value.text = "%d%%" % int(roundf(_volume_slider.value * 100.0))


# ---------------------------------------------------------------------------
# Key bindings list
# ---------------------------------------------------------------------------


## Fill the bindings grid from BINDINGS + the live InputMap. The grid has four
## columns, so two label/key pairs share each visual row.
func _build_bindings() -> void:
	for child in _bindings_grid.get_children():
		child.queue_free()
	for entry in BINDINGS:
		_bindings_grid.add_child(_binding_label(String(entry[1]), ACTION_COLOR))
		_bindings_grid.add_child(_binding_label(binding_text(entry[0]), KEY_COLOR))


func _binding_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 12)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
