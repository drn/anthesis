extends GutTest
## Covers the inventory hotkey: the toggle_inventory action binding (physical I)
## and the Hud open/close toggle it drives. Split from test_hud.gd to keep each
## test class under gdlint's 20-public-method ceiling.

const HUD_PATH := "res://scenes/ui/hud.tscn"


func _inventory_key_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_I
	event.pressed = true
	return event


func test_toggle_inventory_action_bound_to_i() -> void:
	assert_true(InputMap.has_action("toggle_inventory"), "toggle_inventory action must exist")
	var events := InputMap.action_get_events("toggle_inventory")
	assert_eq(events.size(), 1, "toggle_inventory must have exactly one binding")
	var key := events[0] as InputEventKey
	assert_not_null(key, "toggle_inventory binding must be a key event")
	assert_eq(key.physical_keycode, KEY_I, "toggle_inventory must be bound to physical I")


func test_inventory_hotkey_toggles_panel_open_and_closed() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	var panel := hud.get_node("InventoryPanel")
	assert_false(panel.visible, "Panel starts hidden")

	hud._unhandled_input(_inventory_key_event())
	assert_true(panel.visible, "First press opens the inventory")

	hud._unhandled_input(_inventory_key_event())
	assert_false(panel.visible, "Second press closes the inventory")
