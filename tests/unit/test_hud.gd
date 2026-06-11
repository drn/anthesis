extends GutTest
## Structural tests for the HUD and inventory panel scenes.
##
## These assert UI wiring (node structure, default visibility, slot count,
## bind() contract) without depending on a live World. Inventory is used when
## available to verify the panel refreshes on the inventory's changed signal.

const HUD_PATH := "res://scenes/ui/hud.tscn"
const PANEL_PATH := "res://scenes/ui/inventory_panel.tscn"

const EXPECTED_SLOTS := 24


func _find_descendant_of_class(node: Node, class_str: String) -> Node:
	if node.is_class(class_str):
		return node
	for child in node.get_children():
		var found := _find_descendant_of_class(child, class_str)
		if found != null:
			return found
	return null


func _panel_grid(panel: Control) -> GridContainer:
	return _find_descendant_of_class(panel, "GridContainer") as GridContainer


# ---------------------------------------------------------------------------
# HUD structure
# ---------------------------------------------------------------------------


func test_hud_scene_loads() -> void:
	var packed: PackedScene = load(HUD_PATH)
	assert_not_null(packed, "hud.tscn must load")


func test_hud_root_is_canvas_layer() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate()
	add_child_autofree(hud)
	assert_true(hud is CanvasLayer, "HUD root must be a CanvasLayer")
	assert_true(hud is Hud, "HUD root must have the Hud script")


func test_hud_has_crosshair() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate()
	add_child_autofree(hud)
	assert_not_null(hud.get_node_or_null("Crosshair"), "HUD must have a Crosshair node")


func test_hud_has_toast() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate()
	add_child_autofree(hud)
	var toast := hud.get_node_or_null("Toast")
	assert_not_null(toast, "HUD must have a Toast node")
	assert_true(toast is Label, "Toast must be a Label")


func test_hud_bind_exists() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate()
	add_child_autofree(hud)
	assert_true(hud.has_method("bind"), "HUD must expose bind()")
	assert_true(hud.has_method("show_loot"), "HUD must expose show_loot()")


func test_hud_inventory_panel_hidden_by_default() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate()
	add_child_autofree(hud)
	var panel := hud.get_node_or_null("InventoryPanel")
	assert_not_null(panel, "HUD must embed an InventoryPanel")
	assert_false(panel.visible, "InventoryPanel must be hidden by default")


# ---------------------------------------------------------------------------
# Inventory panel structure
# ---------------------------------------------------------------------------


func test_panel_scene_loads() -> void:
	assert_not_null(load(PANEL_PATH), "inventory_panel.tscn must load")


func test_panel_hidden_by_default() -> void:
	var panel := (load(PANEL_PATH) as PackedScene).instantiate()
	add_child_autofree(panel)
	assert_false(panel.visible, "Panel must be hidden by default")


func test_panel_has_24_slots() -> void:
	var panel := (load(PANEL_PATH) as PackedScene).instantiate()
	add_child_autofree(panel)
	var grid := _panel_grid(panel)
	assert_not_null(grid, "Panel must contain a GridContainer")
	assert_eq(grid.columns, 6, "Grid must have 6 columns")
	assert_eq(grid.get_child_count(), EXPECTED_SLOTS, "Grid must have 24 slot cells")


func test_panel_bind_nil_safe() -> void:
	var panel := (load(PANEL_PATH) as PackedScene).instantiate()
	add_child_autofree(panel)
	# bind with all-null collaborators must not crash.
	panel.bind(null, null, null, Callable())
	assert_true(true, "bind() tolerates null collaborators")


# ---------------------------------------------------------------------------
# Live refresh on inventory.changed
# ---------------------------------------------------------------------------


func _make_inventory() -> Object:
	if not ResourceLoader.exists("res://scripts/systems/inventory/inventory.gd"):
		return null
	var script: Object = load("res://scripts/systems/inventory/inventory.gd")
	if script == null:
		return null
	return script.new(EXPECTED_SLOTS, null)


func test_panel_refreshes_on_inventory_changed() -> void:
	var inv: Object = _make_inventory()
	if inv == null:
		pending("Inventory not available yet; skipping live-refresh test")
		return

	var panel := (load(PANEL_PATH) as PackedScene).instantiate()
	add_child_autofree(panel)
	# Bind with a nil-safe registry so swatch/label lookups exercise fallbacks.
	panel.bind(inv, null, null, Callable())

	var grid := _panel_grid(panel)
	var first_swatch := grid.get_child(0) as ColorRect
	var first_count := first_swatch.get_child(0) as Label
	assert_eq(first_count.text, "", "Slot 0 starts empty")

	# Mutating the inventory must emit changed -> panel repaints slot 0.
	inv.add(&"soil", 5)
	assert_eq(first_count.text, "5", "Slot 0 reflects added item count after changed")
	assert_eq(panel._inventory.count_of(&"soil"), 5, "Inventory bound to panel holds the item")
