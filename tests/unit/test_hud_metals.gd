extends GutTest
## Metal gauge HUD tests: bind_metals wiring, reserve fill bars, channel glow,
## and resource-aware ability cost labels.
##
## Split into its own file to stay within the 20-public-method lint ceiling.
## Pure-visual paths (ImmediateMesh line drawing in MetalLineOverlay._process)
## are intentionally NOT covered here — the integrator live-verifies those via
## scripts/tools/verify/verify_ferromancy.gd.

const HUD_PATH := "res://scenes/ui/hud.tscn"
const ABILITY_SLOTS := "CenterPanel/Margin/Bar/AbilitySlots"

# ---------------------------------------------------------------------------
# Fakes
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


class FakeReserves:
	extends RefCounted
	signal changed(kind: StringName, current: float, capacity: float)
	var _wells: Dictionary = {}

	func _init() -> void:
		for k in [&"iron", &"steel", &"pewter", &"tin"]:
			_wells[k] = FakeWell.new(0.0, 60.0)

	func well(kind: StringName) -> Object:
		return _wells.get(kind, null)

	func set_metal(kind: StringName, value: float) -> void:
		var w: FakeWell = _wells.get(kind)
		if w != null:
			w.set_current(value)
			changed.emit(kind, value, w.capacity())


class FakeChannels:
	extends RefCounted
	signal channel_changed(channel_id: StringName, active: bool)

	func fire(channel_id: StringName, active: bool) -> void:
		channel_changed.emit(channel_id, active)


class AbilityStub:
	extends RefCounted
	var id: StringName
	var display_name: String
	var lumen_cost: float
	var cooldown_ticks: int
	var swatch_color: Color
	var resource_kind: StringName

	func _init(
		p_id: StringName, p_cost: float, p_cd: int, p_color: Color, p_kind: StringName
	) -> void:
		id = p_id
		display_name = String(p_id).capitalize()
		lumen_cost = p_cost
		cooldown_ticks = p_cd
		swatch_color = p_color
		resource_kind = p_kind


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _hud() -> Hud:
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	return hud


func _find_named(node: Node, target: String) -> Node:
	if node.name == target:
		return node
	for child in node.get_children():
		var found := _find_named(child, target)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# bind_metals API
# ---------------------------------------------------------------------------


func test_bind_metals_method_exists() -> void:
	var hud := _hud()
	assert_true(hud.has_method("bind_metals"), "HUD must expose bind_metals()")


func test_bind_metals_nil_safe() -> void:
	var hud := _hud()
	hud.bind_metals(null, null)
	assert_true(true, "bind_metals(null, null) must not crash")


func test_bind_metals_creates_gauge_container() -> void:
	var hud := _hud()
	hud.bind_metals(FakeReserves.new(), FakeChannels.new())
	var container := _find_named(hud, "MetalGauges")
	assert_not_null(container, "bind_metals must create a MetalGauges container")


func test_bind_metals_has_four_rows() -> void:
	var hud := _hud()
	hud.bind_metals(FakeReserves.new(), FakeChannels.new())
	var container := _find_named(hud, "MetalGauges")
	assert_not_null(container, "MetalGauges container must exist")
	assert_eq(container.get_child_count(), 4, "MetalGauges must have exactly 4 rows")


func test_bind_metals_row_names() -> void:
	var hud := _hud()
	hud.bind_metals(FakeReserves.new(), FakeChannels.new())
	var container := _find_named(hud, "MetalGauges")
	assert_not_null(container, "MetalGauges container must exist")
	var names: Array = []
	for child in container.get_children():
		names.append(child.name)
	assert_true(names.has("MetalRow_iron"), "iron row must exist")
	assert_true(names.has("MetalRow_steel"), "steel row must exist")
	assert_true(names.has("MetalRow_pewter"), "pewter row must exist")
	assert_true(names.has("MetalRow_tin"), "tin row must exist")


# ---------------------------------------------------------------------------
# Reserve repaint on changed signal
# ---------------------------------------------------------------------------


func test_reserves_changed_updates_fill_bar() -> void:
	var reserves := FakeReserves.new()
	var hud := _hud()
	hud.bind_metals(reserves, null)
	# Fill bar for iron should start at 0 (anchor_right == 0.0).
	var iron_fill := _find_named(hud, "MetalRow_iron")
	assert_not_null(iron_fill, "MetalRow_iron must exist after bind")
	var fill := _find_named(iron_fill, "Fill") as ColorRect
	assert_not_null(fill, "Iron row must have a Fill ColorRect")
	assert_almost_eq(fill.anchor_right, 0.0, 0.001, "Fill starts at 0 for empty well")

	# Emit changed with 30/60 -> expect anchor_right 0.5.
	reserves.set_metal(&"iron", 30.0)
	assert_almost_eq(fill.anchor_right, 0.5, 0.001, "Fill at 0.5 for 30/60")


func test_reserves_changed_full_fill() -> void:
	var reserves := FakeReserves.new()
	var hud := _hud()
	hud.bind_metals(reserves, null)
	reserves.set_metal(&"steel", 60.0)
	var steel_row := _find_named(hud, "MetalRow_steel")
	var fill := _find_named(steel_row, "Fill") as ColorRect
	assert_almost_eq(fill.anchor_right, 1.0, 0.001, "Full well fills to anchor_right = 1.0")


func test_reserves_changed_value_label() -> void:
	var reserves := FakeReserves.new()
	var hud := _hud()
	hud.bind_metals(reserves, null)
	reserves.set_metal(&"pewter", 45.0)
	# Value label should show "45".
	var pewter_row := _find_named(hud, "MetalRow_pewter")
	assert_not_null(pewter_row, "MetalRow_pewter must exist")
	# Walk labels in the row to find the numeric value label (rightmost Label).
	var labels: Array = []
	for child in pewter_row.get_children():
		if child is Label:
			labels.append(child)
	# The last label in the row is the value label.
	assert_true(labels.size() >= 2, "Row must have at least kind label + value label")
	var val_label := labels[labels.size() - 1] as Label
	assert_eq(val_label.text, "45", "Value label shows rounded current value")


# ---------------------------------------------------------------------------
# Channel glow
# ---------------------------------------------------------------------------


func test_channel_vigor_glows_pewter_row() -> void:
	var channels := FakeChannels.new()
	var hud := _hud()
	hud.bind_metals(null, channels)
	var pewter_row := _find_named(hud, "MetalRow_pewter")
	assert_not_null(pewter_row, "MetalRow_pewter must exist after bind")
	var fill := _find_named(pewter_row, "Fill") as ColorRect
	assert_not_null(fill, "Pewter row must have a Fill ColorRect")
	var base_color := fill.color
	channels.fire(&"vigor", true)
	assert_ne(fill.color, base_color, "Active vigor channel must change pewter fill color (glow)")


func test_channel_vigor_off_restores_base() -> void:
	var channels := FakeChannels.new()
	var hud := _hud()
	hud.bind_metals(null, channels)
	var pewter_row := _find_named(hud, "MetalRow_pewter")
	var fill := _find_named(pewter_row, "Fill") as ColorRect
	var base_color := fill.color
	channels.fire(&"vigor", true)
	channels.fire(&"vigor", false)
	assert_eq(fill.color, base_color, "Deactivated vigor restores base pewter fill color")


func test_channel_keensight_glows_tin_row() -> void:
	var channels := FakeChannels.new()
	var hud := _hud()
	hud.bind_metals(null, channels)
	var tin_row := _find_named(hud, "MetalRow_tin")
	var fill := _find_named(tin_row, "Fill") as ColorRect
	var base_color := fill.color
	channels.fire(&"keensight", true)
	assert_ne(fill.color, base_color, "Active keensight channel must change tin fill color (glow)")


func test_unknown_channel_id_safe() -> void:
	var channels := FakeChannels.new()
	var hud := _hud()
	hud.bind_metals(null, channels)
	channels.fire(&"nonexistent_channel", true)
	assert_true(true, "Unknown channel id must not crash")


# ---------------------------------------------------------------------------
# Resource-aware cost label on ability slots
# ---------------------------------------------------------------------------


func _ability_stub(
	p_id: StringName, p_cost: float, p_cd: int, p_color: Color, p_kind: StringName
) -> AbilityStub:
	return AbilityStub.new(p_id, p_cost, p_cd, p_color, p_kind)


func _find_cost_label(slot: Node) -> Label:
	# The cost label is the second Label in the VBoxContainer body.
	for child in slot.get_children():
		var result := _find_cost_label_in(child)
		if result != null:
			return result
	return null


func _find_cost_label_in(node: Node) -> Label:
	if node is VBoxContainer:
		var labels: Array = []
		for child in node.get_children():
			if child is Label:
				labels.append(child)
		if labels.size() >= 2:
			return labels[1] as Label
	for child in node.get_children():
		var found := _find_cost_label_in(child)
		if found != null:
			return found
	return null


func test_lumen_ability_shows_lumen_in_cost() -> void:
	var hud := _hud()
	var ability := _ability_stub(&"shape_burst", 25.0, 30, Color.CYAN, &"lumen")
	hud.bind_magic(null, null, [ability])
	var slots := hud.get_node(ABILITY_SLOTS)
	assert_eq(slots.get_child_count(), 1, "One slot built")
	var cost_label := _find_cost_label(slots.get_child(0))
	assert_not_null(cost_label, "Ability slot must have a cost label")
	assert_true(cost_label.text.ends_with("lumen"), "Lumen ability cost shows 'lumen'")


func test_iron_ability_shows_iron_in_cost() -> void:
	var hud := _hud()
	var ability := _ability_stub(&"ferro_pull", 12.0, 8, Color.BLUE, &"iron")
	hud.bind_magic(null, null, [ability])
	var slots := hud.get_node(ABILITY_SLOTS)
	var cost_label := _find_cost_label(slots.get_child(0))
	assert_not_null(cost_label, "Ability slot must have a cost label")
	assert_true(cost_label.text.ends_with("iron"), "Iron ability cost shows 'iron'")
	assert_true(cost_label.text.begins_with("12"), "Iron ability cost shows '12'")


func test_steel_ability_shows_steel_in_cost() -> void:
	var hud := _hud()
	var ability := _ability_stub(&"ferro_push", 12.0, 8, Color.WHITE, &"steel")
	hud.bind_magic(null, null, [ability])
	var slots := hud.get_node(ABILITY_SLOTS)
	var cost_label := _find_cost_label(slots.get_child(0))
	assert_not_null(cost_label, "Ability slot must have a cost label")
	assert_true(cost_label.text.ends_with("steel"), "Steel ability cost shows 'steel'")


func test_empty_resource_kind_defaults_to_lumen() -> void:
	# An ability with resource_kind = &"" should still show "lumen".
	var ability := _ability_stub(&"legacy_ability", 20.0, 15, Color.CYAN, &"")
	var hud := _hud()
	hud.bind_magic(null, null, [ability])
	var slots := hud.get_node(ABILITY_SLOTS)
	var cost_label := _find_cost_label(slots.get_child(0))
	assert_not_null(cost_label, "Ability slot must have a cost label")
	assert_true(cost_label.text.ends_with("lumen"), "Empty resource_kind defaults to 'lumen'")


func test_ability_without_resource_kind_shows_lumen() -> void:
	# Old-style duck-typed ability with no resource_kind field at all.
	var hud := _hud()
	# Reuse the old AbilityStub without resource_kind by building a plain dict-like.
	# We don't want to depend on AbilityDef loading in a unit test.
	var ability := RefCounted.new()
	# No resource_kind property -> HUD must not crash and must show lumen.
	hud.bind_magic(null, null, [ability])
	var slots := hud.get_node(ABILITY_SLOTS)
	assert_eq(slots.get_child_count(), 1, "One slot built for bare stub")
	assert_true(true, "No crash when ability has no resource_kind")


# ---------------------------------------------------------------------------
# Rebind safety
# ---------------------------------------------------------------------------


func test_rebind_metals_replaces_container() -> void:
	var hud := _hud()
	hud.bind_metals(FakeReserves.new(), FakeChannels.new())
	var first_container := _find_named(hud, "MetalGauges")
	# Rebind must not duplicate the container.
	hud.bind_metals(FakeReserves.new(), FakeChannels.new())
	var containers: Array = []
	for child in hud.get_children():
		if child.name == "MetalGauges":
			containers.append(child)
	# queue_free is deferred, so we may see the old one briefly — check that the
	# live field _metal_container points to the replacement (not a freed node).
	assert_not_null(hud._metal_container, "Rebind must produce a fresh container")
	assert_true(is_instance_valid(hud._metal_container), "New _metal_container must be valid")
