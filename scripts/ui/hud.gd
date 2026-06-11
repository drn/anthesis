class_name Hud
extends CanvasLayer
## Heads-up display: crosshair, loot toast, and inventory panel toggle.
##
## Owns no game logic beyond UI presentation. Crafting is routed back to the
## World via the on_craft Callable handed to bind(); this HUD never mutates
## game state directly.

## Seconds the loot toast stays fully visible before fading out.
const TOAST_HOLD_SECONDS := 2.0
## Seconds the loot toast takes to fade from visible to transparent.
const TOAST_FADE_SECONDS := 0.6

var _toast_tween: Tween = null

@onready var _toast: Label = $Toast
@onready var _inventory_panel: InventoryPanel = $InventoryPanel


func _ready() -> void:
	_toast.modulate = Color(1.0, 1.0, 1.0, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("toggle_inventory") and event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()


## Wire the panel to live game state. crafting is accepted for parity with the
## contract; the panel only ever asks can_craft() and defers actual crafting to
## on_craft so writes route through the CommandBus.
func bind(inventory: Object, registry: Object, crafting: Object, on_craft: Callable) -> void:
	_inventory_panel.bind(inventory, registry, crafting, on_craft)


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
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
