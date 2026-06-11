extends GutTest
## Quick-inventory belt tests: the center-panel belt mirrors the first
## inventory slots and repaints on inventory.changed.
##
## Split from test_hud.gd to respect the 20-public-method lint ceiling.

const HUD_PATH := "res://scenes/ui/hud.tscn"
const BELT_PATH := "CenterPanel/Margin/Bar/QuickSlots"
const INVENTORY_SCRIPT := "res://scripts/systems/inventory/inventory.gd"


func _hud() -> Hud:
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	return hud


func _make_inventory() -> Object:
	if not ResourceLoader.exists(INVENTORY_SCRIPT):
		return null
	var script: Object = load(INVENTORY_SCRIPT)
	return script.new(24, null) if script != null else null


## Belt slot i -> its count label (PanelContainer > Margin > swatch > Label).
func _belt_count_label(hud: Hud, i: int) -> Label:
	var slot := hud.get_node(BELT_PATH).get_child(i)
	return slot.get_child(0).get_child(0).get_child(0) as Label


func _belt_swatch(hud: Hud, i: int) -> ColorRect:
	var slot := hud.get_node(BELT_PATH).get_child(i)
	return slot.get_child(0).get_child(0) as ColorRect


func test_hud_has_quick_belt() -> void:
	var hud := _hud()
	var belt := hud.get_node_or_null(BELT_PATH)
	assert_not_null(belt, "Center panel must hold a QuickSlots belt")
	assert_eq(belt.get_child_count(), Hud.QUICK_SLOT_COUNT, "Belt has a fixed slot count")


func test_belt_empty_before_bind() -> void:
	var hud := _hud()
	for i in range(Hud.QUICK_SLOT_COUNT):
		assert_eq(_belt_count_label(hud, i).text, "", "Belt slot %d starts empty" % i)


func test_bind_populates_belt() -> void:
	var inv: Object = _make_inventory()
	if inv == null:
		pending("Inventory not available; skipping belt-population test")
		return
	inv.add(&"soil", 7)
	var hud := _hud()
	hud.bind(inv, null, null, Callable())
	assert_eq(_belt_count_label(hud, 0).text, "7", "Belt slot 0 shows bound stack count")


func test_belt_refreshes_on_inventory_changed() -> void:
	var inv: Object = _make_inventory()
	if inv == null:
		pending("Inventory not available; skipping belt-refresh test")
		return
	var hud := _hud()
	hud.bind(inv, null, null, Callable())
	assert_eq(_belt_count_label(hud, 0).text, "", "Belt slot 0 empty before pickup")
	var empty_color := _belt_swatch(hud, 0).color
	inv.add(&"soil", 5)
	assert_eq(_belt_count_label(hud, 0).text, "5", "Belt slot 0 repaints on inventory.changed")
	assert_ne(_belt_swatch(hud, 0).color, empty_color, "Occupied belt slot recolors its swatch")


func test_belt_bind_nil_safe() -> void:
	var hud := _hud()
	hud.bind(null, null, null, Callable())
	assert_eq(_belt_count_label(hud, 0).text, "", "bind(null) leaves the belt empty, no crash")
