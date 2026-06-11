extends GutTest
## Covers the inventory hotkey: the toggle_inventory action binding (physical I)
## and the Hud open/close toggle it drives. Lives in its own file because adding
## these tests to test_hud.gd tripped gdlint's 20-public-method ceiling.

const HUD_PATH := "res://scenes/ui/hud.tscn"


func _inventory_key_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_I
	event.pressed = true
	return event


## Calling _unhandled_input directly is the deliberate GUT pattern for input
## handlers (mirrors test_hud.gd driving hud._process); Input.parse_input_event
## is async and flaky headless.
func _press_inventory_key(hud: Hud) -> void:
	hud._unhandled_input(_inventory_key_event())


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

	_press_inventory_key(hud)
	assert_true(panel.visible, "First press opens the inventory")

	_press_inventory_key(hud)
	assert_false(panel.visible, "Second press closes the inventory")


func test_closing_inventory_releases_ui_focus() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	var panel := hud.get_node("InventoryPanel") as Control

	_press_inventory_key(hud)
	# Simulate a Craft button grabbing focus while the panel is open. A control
	# holding focus can swallow later hotkeys — the same class of bug as the
	# old Tab binding being eaten by focus traversal.
	var button := Button.new()
	panel.add_child(button)
	button.grab_focus()
	assert_eq(panel.get_viewport().gui_get_focus_owner(), button, "Button holds focus while open")

	_press_inventory_key(hud)
	assert_false(panel.visible, "Panel closes despite a focused button")
	assert_null(panel.get_viewport().gui_get_focus_owner(), "Close releases UI focus")
