class_name Hud
extends CanvasLayer
## Heads-up display, Diablo-style: HP and Lumen orbs flank a bottom-center
## panel holding the ability slots and a quick-inventory belt. Also owns the
## crosshair, loot toast, and inventory panel toggle.
##
## Owns no game logic beyond UI presentation. Crafting is routed back to the
## World via the on_craft Callable handed to bind(); this HUD never mutates
## game state directly.

## Seconds the loot toast stays fully visible before fading out.
const TOAST_HOLD_SECONDS := 2.0
## Seconds the loot toast takes to fade from visible to transparent.
const TOAST_FADE_SECONDS := 0.6

## Lumen orb fill gradient endpoints (empty -> full): cool cyan when drained,
## saturating to magenta at capacity.
const LUMEN_EMPTY_COLOR := Color(0.35, 0.85, 1.0, 1.0)
const LUMEN_FULL_COLOR := Color(0.9, 0.35, 0.95, 1.0)

## Health orb fill gradient endpoints (full -> low): Diablo-red when healthy,
## heating toward hot orange as the pool drains.
const HEALTH_FULL_COLOR := Color(0.85, 0.12, 0.18, 1.0)
const HEALTH_LOW_COLOR := Color(1.0, 0.38, 0.08, 1.0)
## Below these ratios the meter shader gets a nonzero alarm pulse.
const HEALTH_PULSE_THRESHOLD := 0.3
const LUMEN_PULSE_THRESHOLD := 0.15
## Hurt vignette flash settings.
const HURT_VIGNETTE_ALPHA := 0.25
const HURT_VIGNETTE_FADE := 0.45

## Cosmic-glassy ability slot chrome.
const SLOT_BG_COLOR := Color(0.06, 0.05, 0.12, 0.85)
const SLOT_BORDER_COLOR := Color(0.5, 0.5, 1.0, 0.4)
const COOLDOWN_VEIL_COLOR := Color(0.0, 0.0, 0.02, 0.6)
## Flash tints for cast failure feedback.
const FLASH_COST_COLOR := Color(1.0, 0.3, 0.35, 0.55)
const FLASH_COOLDOWN_COLOR := Color(0.6, 0.6, 0.7, 0.5)
const FLASH_FADE_SECONDS := 0.45

## Quick-inventory belt: first N inventory slots mirrored into the center bar.
const QUICK_SLOT_COUNT := 6
const QUICK_EMPTY_COLOR := Color(0.10, 0.10, 0.18, 0.7)

var _toast_tween: Tween = null

var _well: Object = null
var _magic: Object = null
var _abilities: Array = []
## One control bundle per ability slot, parallel to _abilities by index.
var _slot_veils: Array[ColorRect] = []
var _slot_flashes: Array[ColorRect] = []

## Bound Health object (RefCounted; may be null).
var _health: Object = null
## Previous health value for detecting damage (hurt vignette trigger).
var _health_prev: float = -1.0

## Bound Inventory + ItemRegistry for the quick belt (both may be null).
var _inventory: Object = null
var _registry: Object = null
## One swatch/count pair per belt slot, parallel by index.
var _quick_swatches: Array[ColorRect] = []
var _quick_counts: Array[Label] = []

@onready var _toast: Label = $Toast
@onready var _inventory_panel: InventoryPanel = $InventoryPanel
@onready var _lumen_label: Label = $LumenOrb/Label
@onready var _lumen_fill: ColorRect = $LumenOrb/Fill
@onready var _ability_slots: HBoxContainer = $CenterPanel/Margin/Bar/AbilitySlots
@onready var _quick_slots: HBoxContainer = $CenterPanel/Margin/Bar/QuickSlots
@onready var _health_label: Label = $HealthOrb/Label
@onready var _health_fill: ColorRect = $HealthOrb/Fill
@onready var _hurt_vignette: ColorRect = $HurtVignette
@onready var _death_overlay: ColorRect = $DeathOverlay
@onready var _death_label: Label = $DeathOverlay/Label


func _ready() -> void:
	_toast.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_build_quick_slots()


## Polls the bound MagicSystem each frame so cooldown veils animate smoothly
## without needing a per-tick signal. Cheap: only runs once bound.
func _process(_delta: float) -> void:
	if _magic == null:
		return
	_update_cooldowns()


func _unhandled_input(event: InputEvent) -> void:
	# has_action guards harnesses that run this scene without project.godot's
	# input map loaded; is_action_pressed errors loudly on an unknown action.
	if InputMap.has_action("toggle_inventory") and event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()


## Wire the panel and quick belt to live game state. crafting is accepted for
## parity with the contract; the panel only ever asks can_craft() and defers
## actual crafting to on_craft so writes route through the CommandBus.
func bind(inventory: Object, registry: Object, crafting: Object, on_craft: Callable) -> void:
	if (
		_inventory != null
		and _inventory.has_signal("changed")
		and _inventory.changed.is_connected(_refresh_quick_slots)
	):
		_inventory.changed.disconnect(_refresh_quick_slots)
	_inventory = inventory
	_registry = registry
	if _inventory != null and _inventory.has_signal("changed"):
		_inventory.changed.connect(_refresh_quick_slots)
	_refresh_quick_slots()
	_inventory_panel.bind(inventory, registry, crafting, on_craft)


## Wire the lumen bar + ability slots to live magic state. All collaborators may
## be null (headless / pre-magic): the HUD degrades to an empty, inert display.
## well exposes current()/capacity() and a changed(current, capacity) signal;
## magic exposes cooldown_remaining(ability) and a cast_failed(ability, reason)
## signal; abilities is an ordered Array of AbilityDef-like resources (slots 1..n).
func bind_magic(well: Object, magic: Object, abilities: Array) -> void:
	if (
		_well != null
		and _well.has_signal("changed")
		and _well.changed.is_connected(_on_well_changed)
	):
		_well.changed.disconnect(_on_well_changed)
	if (
		_magic != null
		and _magic.has_signal("cast_failed")
		and _magic.cast_failed.is_connected(_on_cast_failed)
	):
		_magic.cast_failed.disconnect(_on_cast_failed)

	_well = well
	_magic = magic
	_abilities = abilities if abilities != null else []

	_build_ability_slots()

	if _well != null and _well.has_signal("changed"):
		_well.changed.connect(_on_well_changed)
	if _magic != null and _magic.has_signal("cast_failed"):
		_magic.cast_failed.connect(_on_cast_failed)

	if _well != null and _well.has_method("current") and _well.has_method("capacity"):
		_on_well_changed(_well.current(), _well.capacity())
	else:
		_on_well_changed(0.0, 100.0)


## Wire the health bar to a Health object (scripts/systems/combat/health.gd).
## health may be null — the bar shows 0/0 and stays inert until re-bound.
func bind_health(health: Object) -> void:
	if (
		_health != null
		and _health.has_signal("changed")
		and _health.changed.is_connected(_on_health_changed)
	):
		_health.changed.disconnect(_on_health_changed)
	_health = health
	_health_prev = -1.0
	if _health != null and _health.has_signal("changed"):
		_health.changed.connect(_on_health_changed)
	if _health != null and _health.has_method("current") and _health.has_method("max_health"):
		_on_health_changed(_health.current(), _health.max_health())
	else:
		_on_health_changed(0.0, 0.0)


## Show the death overlay with a countdown message. respawn_in_s is informational.
func show_death(respawn_in_s: float) -> void:
	_death_label.text = "THE DARK TAKES YOU\n\nRespawning in %ds..." % int(ceilf(respawn_in_s))
	_death_overlay.visible = true
	_death_overlay.modulate = Color(1.0, 1.0, 1.0, 1.0)


## Hide the death overlay (call after respawn).
func hide_death() -> void:
	_death_overlay.visible = false


## Show a transient toast for awarded loot. registry may be null (raw ids shown).
func show_loot(awarded: Array, registry: Object) -> void:
	if awarded == null or awarded.is_empty():
		return
	_toast.text = _format_awarded(awarded, registry)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_HOLD_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, TOAST_FADE_SECONDS)


## Show a transient one-line hint in the toast slot (used by the sequencer to
## surface block controls on the first placement). Same fade as a loot toast.
func show_hint(text: String) -> void:
	if text.is_empty():
		return
	_toast.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_toast_tween = create_tween()
	_toast_tween.tween_interval(TOAST_HOLD_SECONDS)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, TOAST_FADE_SECONDS)


func _format_awarded(awarded: Array, registry: Object) -> String:
	var parts: PackedStringArray = []
	for amount in awarded:
		if amount == null:
			continue
		var id: StringName = amount.item_id
		var label := String(id)
		if registry != null and registry.has_method("item"):
			var def: Object = registry.item(id)
			if def != null and not String(def.display_name).is_empty():
				label = def.display_name
		parts.append("+%d %s" % [amount.count, label])
	return "  ".join(parts)


func _toggle_inventory() -> void:
	var now_visible := not _inventory_panel.visible
	_inventory_panel.visible = now_visible
	if now_visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		# Drop any focus a Craft button grabbed while the panel was open, so a
		# focused control can't swallow hotkeys after the panel closes.
		get_viewport().gui_release_focus()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ---------------------------------------------------------------------------
# Quick-inventory belt
# ---------------------------------------------------------------------------


## Build the fixed row of belt slots once; bind()/changed only repaint them.
func _build_quick_slots() -> void:
	_quick_swatches.clear()
	_quick_counts.clear()
	for child in _quick_slots.get_children():
		child.queue_free()
	for i in range(QUICK_SLOT_COUNT):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(44, 44)
		panel.add_theme_stylebox_override("panel", _slot_stylebox())
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var margin := MarginContainer.new()
		margin.name = "Margin"
		margin.add_theme_constant_override("margin_left", 4)
		margin.add_theme_constant_override("margin_top", 4)
		margin.add_theme_constant_override("margin_right", 4)
		margin.add_theme_constant_override("margin_bottom", 4)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(margin)

		var swatch := ColorRect.new()
		swatch.name = "Swatch"
		swatch.color = QUICK_EMPTY_COLOR
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(swatch)

		var count := Label.new()
		count.name = "Count"
		count.set_anchors_preset(Control.PRESET_FULL_RECT)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
		count.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.1, 0.9))
		count.add_theme_constant_override("outline_size", 3)
		count.add_theme_font_size_override("font_size", 12)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.add_child(count)

		_quick_slots.add_child(panel)
		_quick_swatches.append(swatch)
		_quick_counts.append(count)


## Repaint the belt from the first QUICK_SLOT_COUNT inventory slots. No
## tooltips: every belt node is MOUSE_FILTER_IGNORE (the mouse is captured
## during play), so hover UI can never trigger.
func _refresh_quick_slots() -> void:
	for i in range(QUICK_SLOT_COUNT):
		var data: Dictionary = {}
		if _inventory != null and _inventory.has_method("slot"):
			data = _inventory.slot(i)
		var swatch := _quick_swatches[i]
		var count := _quick_counts[i]
		if data.is_empty():
			swatch.color = QUICK_EMPTY_COLOR
			count.text = ""
		else:
			swatch.color = _item_color(data["id"])
			count.text = str(data["count"])


func _item_color(id: StringName) -> Color:
	if _registry != null and _registry.has_method("item"):
		var def: Object = _registry.item(id)
		if def != null:
			return def.swatch_color
	return Color.WHITE


# ---------------------------------------------------------------------------
# Resource orbs (HP / Lumen)
# ---------------------------------------------------------------------------


func _on_health_changed(current: float, max_hp: float) -> void:
	var cap := maxf(max_hp, 0.001)
	var ratio := clampf(current / cap, 0.0, 1.0)
	_health_label.text = "HP %d / %d" % [int(roundf(current)), int(roundf(max_hp))]
	_health_fill.color = HEALTH_LOW_COLOR.lerp(HEALTH_FULL_COLOR, ratio)
	_update_meter(_health_fill, ratio, HEALTH_PULSE_THRESHOLD)
	# Flash hurt vignette only when health decreased.
	if _health_prev >= 0.0 and current < _health_prev:
		_flash_hurt()
	_health_prev = current


## Push fill state into an orb's liquid shader. The ColorRect's color is kept
## as the source of truth for the fill palette; the shader reads it as a
## parameter so headless/material-stripped scenes degrade to a plain rect.
## frame_color and back_color are static per-orb, set once in hud.tscn.
func _update_meter(fill: ColorRect, ratio: float, pulse_threshold: float) -> void:
	var mat := fill.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("fill_ratio", ratio)
	mat.set_shader_parameter("fill_color", fill.color)
	var pulse := 0.0
	if ratio > 0.0 and ratio < pulse_threshold:
		pulse = 1.0 - ratio / pulse_threshold
	mat.set_shader_parameter("pulse", pulse)


func _flash_hurt() -> void:
	_hurt_vignette.modulate = Color(1.0, 1.0, 1.0, HURT_VIGNETTE_ALPHA)
	var tween := create_tween()
	tween.tween_property(_hurt_vignette, "modulate:a", 0.0, HURT_VIGNETTE_FADE)


func _on_well_changed(current: float, capacity: float) -> void:
	var cap := maxf(capacity, 0.001)
	var ratio := clampf(current / cap, 0.0, 1.0)
	_lumen_label.text = "LUMEN %d / %d" % [int(roundf(current)), int(roundf(capacity))]
	_lumen_fill.color = LUMEN_EMPTY_COLOR.lerp(LUMEN_FULL_COLOR, ratio)
	_update_meter(_lumen_fill, ratio, LUMEN_PULSE_THRESHOLD)


# ---------------------------------------------------------------------------
# Ability slots
# ---------------------------------------------------------------------------


func _build_ability_slots() -> void:
	_slot_veils.clear()
	_slot_flashes.clear()
	for child in _ability_slots.get_children():
		child.queue_free()
	for i in range(_abilities.size()):
		_ability_slots.add_child(_make_ability_slot(i, _abilities[i]))


func _make_ability_slot(index: int, ability: Object) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(116, 0)
	panel.add_theme_stylebox_override("panel", _slot_stylebox())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Stacked so the cooldown veil + flash overlay sit above the content.
	var stack := _ability_slot_stack(index, ability)
	panel.add_child(stack)
	return panel


func _ability_slot_stack(index: int, ability: Object) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(0, 44)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_ability_slot_body(index, ability))
	root.add_child(margin)

	# Cooldown veil: a top-anchored dark rect whose anchor_top shrinks (1->0)
	# as the cooldown elapses, sweeping a shade down over the slot.
	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = COOLDOWN_VEIL_COLOR
	veil.anchor_top = 1.0
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.name = "CooldownVeil"
	root.add_child(veil)
	_slot_veils.append(veil)

	# Flash overlay for cast-failed feedback (transparent until pulsed).
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.0, 0.0, 0.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.name = "Flash"
	root.add_child(flash)
	_slot_flashes.append(flash)

	return root


func _ability_slot_body(index: int, ability: Object) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.color = _ability_color(ability)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label := Label.new()
	name_label.text = "%d  %s" % [index + 1, _ability_name(ability)]
	name_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_label)

	var cost_label := Label.new()
	cost_label.text = "%d lumen" % int(roundf(_ability_cost(ability)))
	cost_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.95, 1.0))
	cost_label.add_theme_font_size_override("font_size", 11)
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(cost_label)

	row.add_child(info)
	return row


func _slot_stylebox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SLOT_BG_COLOR
	box.border_color = SLOT_BORDER_COLOR
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	return box


func _update_cooldowns() -> void:
	if not _magic.has_method("cooldown_remaining"):
		return
	for i in range(_abilities.size()):
		if i >= _slot_veils.size():
			break
		var ability: Object = _abilities[i]
		var remaining: int = _magic.cooldown_remaining(ability)
		var total: float = maxf(_ability_cooldown_ticks(ability), 1.0)
		var ratio := clampf(float(remaining) / total, 0.0, 1.0)
		# anchor_top 1.0 = fully hidden veil (ready); lower = more shade.
		_slot_veils[i].anchor_top = 1.0 - ratio


func _on_cast_failed(ability: Object, reason: StringName) -> void:
	var idx := _abilities.find(ability)
	if idx < 0 or idx >= _slot_flashes.size():
		return
	var tint := FLASH_COOLDOWN_COLOR if reason == &"cooldown" else FLASH_COST_COLOR
	var flash := _slot_flashes[idx]
	flash.color = tint
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, FLASH_FADE_SECONDS)


# ---------------------------------------------------------------------------
# AbilityDef field access (duck-typed; tolerant of partial / null defs)
# ---------------------------------------------------------------------------


func _ability_name(ability: Object) -> String:
	if (
		ability != null
		and "display_name" in ability
		and not String(ability.display_name).is_empty()
	):
		return ability.display_name
	if ability != null and "id" in ability:
		return String(ability.id)
	return "—"


func _ability_cost(ability: Object) -> float:
	if ability != null and "lumen_cost" in ability:
		return ability.lumen_cost
	return 0.0


func _ability_cooldown_ticks(ability: Object) -> float:
	if ability != null and "cooldown_ticks" in ability:
		return float(ability.cooldown_ticks)
	return 1.0


func _ability_color(ability: Object) -> Color:
	if ability != null and "swatch_color" in ability:
		return ability.swatch_color
	return Color.CYAN
