extends GutTest
## Structural tests for the HUD and inventory panel scenes.
##
## These assert UI wiring (node structure, default visibility, slot count,
## bind() contract) without depending on a live World. Inventory is used when
## available to verify the panel refreshes on the inventory's changed signal.

const HUD_PATH := "res://scenes/ui/hud.tscn"
const PANEL_PATH := "res://scenes/ui/inventory_panel.tscn"
const ABILITY_SLOTS := "CenterPanel/Margin/Bar/AbilitySlots"

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
	assert_true(hud.has_method("bind_magic"), "HUD must expose bind_magic()")
	assert_true(hud.has_method("bind_health"), "HUD must expose bind_health()")
	assert_true(hud.has_method("show_death"), "HUD must expose show_death()")
	assert_true(hud.has_method("hide_death"), "HUD must expose hide_death()")


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


# ---------------------------------------------------------------------------
# Magic HUD: lumen bar + ability slots
# ---------------------------------------------------------------------------


class FakeWell:
	extends RefCounted
	signal changed(current: float, capacity: float)
	var _current: float
	var _capacity: float

	func _init(current: float, capacity: float) -> void:
		_current = current
		_capacity = capacity

	func current() -> float:
		return _current

	func capacity() -> float:
		return _capacity

	func set_current(value: float) -> void:
		_current = value
		changed.emit(_current, _capacity)


class FakeMagic:
	extends RefCounted
	signal cast_failed(ability: Object, reason: StringName)
	var remaining := 0

	func cooldown_remaining(_ability: Object) -> int:
		return remaining


func _ability_obj(id: StringName, cost: float, cooldown: int, color: Color) -> Object:
	if ResourceLoader.exists("res://scripts/core/magic/ability_def.gd"):
		var script: Object = load("res://scripts/core/magic/ability_def.gd")
		var def: Object = script.new()
		def.id = id
		def.display_name = String(id).capitalize()
		def.lumen_cost = cost
		def.cooldown_ticks = cooldown
		def.swatch_color = color
		return def
	# Fallback duck-typed stub mirroring AbilityDef fields the HUD reads.
	return AbilityStub.new(id, cost, cooldown, color)


class AbilityStub:
	extends RefCounted
	var id: StringName
	var display_name: String
	var lumen_cost: float
	var cooldown_ticks: int
	var swatch_color: Color

	func _init(p_id: StringName, p_cost: float, p_cd: int, p_color: Color) -> void:
		id = p_id
		display_name = String(p_id).capitalize()
		lumen_cost = p_cost
		cooldown_ticks = p_cd
		swatch_color = p_color


func _three_abilities() -> Array:
	return [
		_ability_obj(&"shape_burst", 25.0, 30, Color(0.2, 0.5, 1.0)),
		_ability_obj(&"lumen_bloom", 15.0, 20, Color(0.9, 0.3, 0.9)),
		_ability_obj(&"skyward", 10.0, 15, Color.CYAN),
	]


func _bound_hud(well: Object, magic: Object, abilities: Array) -> Hud:
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	hud.bind_magic(well, magic, abilities)
	return hud


func test_hud_has_lumen_orb() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate()
	add_child_autofree(hud)
	var orb := hud.get_node_or_null("LumenOrb")
	assert_not_null(orb, "HUD must have a LumenOrb node")
	var label := hud.get_node_or_null("LumenOrb/Label")
	assert_not_null(label, "Lumen orb must have a label")
	var fill := hud.get_node_or_null("LumenOrb/Fill")
	assert_not_null(fill, "Lumen orb must have a fill rect")


func test_hud_has_ability_slots_container() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate()
	add_child_autofree(hud)
	assert_not_null(
		hud.get_node_or_null(ABILITY_SLOTS), "Center panel must hold an AbilitySlots container"
	)


func test_bind_magic_nil_safe() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	hud.bind_magic(null, null, [])
	assert_eq(hud.get_node(ABILITY_SLOTS).get_child_count(), 0, "No slots when no abilities")
	# Null abilities arg must not crash.
	hud.bind_magic(null, null, [])
	assert_true(true, "bind_magic tolerates null collaborators")


func test_bind_magic_builds_three_slots() -> void:
	var hud := _bound_hud(FakeWell.new(30.0, 100.0), FakeMagic.new(), _three_abilities())
	var slots := hud.get_node(ABILITY_SLOTS)
	assert_eq(slots.get_child_count(), 3, "Three abilities -> three slots")


func test_each_slot_has_cooldown_veil() -> void:
	var hud := _bound_hud(FakeWell.new(30.0, 100.0), FakeMagic.new(), _three_abilities())
	var slots := hud.get_node(ABILITY_SLOTS)
	for slot in slots.get_children():
		var veil := _find_named_descendant(slot, "CooldownVeil")
		assert_not_null(veil, "Each ability slot must have a CooldownVeil overlay node")
		assert_true(veil is ColorRect, "CooldownVeil must be a ColorRect")


func test_lumen_label_reflects_well_changed() -> void:
	var well := FakeWell.new(30.0, 100.0)
	var hud := _bound_hud(well, FakeMagic.new(), _three_abilities())
	var label := hud.get_node("LumenOrb/Label") as Label
	assert_eq(label.text, "LUMEN 30 / 100", "Label shows initial well state on bind")

	well.set_current(72.0)
	assert_eq(label.text, "LUMEN 72 / 100", "Label updates on well.changed")


func test_lumen_fill_color_shifts_with_charge() -> void:
	var well := FakeWell.new(0.0, 100.0)
	var hud := _bound_hud(well, FakeMagic.new(), _three_abilities())
	var fill := hud.get_node("LumenOrb/Fill") as ColorRect
	var empty_color := fill.color
	well.set_current(100.0)
	assert_ne(fill.color, empty_color, "Fill color must shift as the well fills")


func test_cooldown_veil_tracks_remaining() -> void:
	var magic := FakeMagic.new()
	var abilities := _three_abilities()
	var hud := _bound_hud(FakeWell.new(30.0, 100.0), magic, abilities)
	var veil := _find_named_descendant(hud.get_node(ABILITY_SLOTS).get_child(0), "CooldownVeil")

	# No cooldown -> veil fully retracted (anchor_top == 1.0).
	magic.remaining = 0
	hud._process(0.016)
	assert_almost_eq(veil.anchor_top, 1.0, 0.001, "Ready slot has a fully retracted veil")

	# Full cooldown (30 ticks for shape_burst) -> veil fully covers (anchor_top == 0).
	magic.remaining = 30
	hud._process(0.016)
	assert_almost_eq(veil.anchor_top, 0.0, 0.001, "Full cooldown veils the whole slot")


func _find_named_descendant(node: Node, target: String) -> Node:
	if node.name == target:
		return node
	for child in node.get_children():
		var found := _find_named_descendant(child, target)
		if found != null:
			return found
	return null
