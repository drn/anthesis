class_name InventoryPanel
extends Control
## Inventory + crafting panel. Hidden by default, toggled by the Hud.
##
## Left: a 6x4 grid of slots mirroring the bound Inventory. Right: one row per
## registry recipe with a Craft button that is disabled unless the recipe can
## currently be crafted. Crafting is never performed here; clicking Craft calls
## the on_craft Callable so the World can route it through the CommandBus.

const GRID_COLUMNS := 6
const GRID_ROWS := 4
const SLOT_COUNT := GRID_COLUMNS * GRID_ROWS

const EMPTY_SLOT_COLOR := Color(0.12, 0.12, 0.2, 0.6)

var _inventory: Object = null
var _registry: Object = null
var _crafting: Object = null
var _on_craft: Callable = Callable()

var _slot_swatches: Array[ColorRect] = []
var _slot_counts: Array[Label] = []

@onready var _grid: GridContainer = $Layout/SlotsPanel/Margin/Grid
@onready var _recipe_list: VBoxContainer = $Layout/RecipesPanel/Margin/RecipeList


func _ready() -> void:
	visible = false
	_build_slots()


## Bind live game state. registry/crafting may be null; the panel degrades to an
## empty recipe list and bare item ids in that case.
func bind(inventory: Object, registry: Object, crafting: Object, on_craft: Callable) -> void:
	if (
		_inventory != null
		and _inventory.has_signal("changed")
		and _inventory.changed.is_connected(_on_inventory_changed)
	):
		_inventory.changed.disconnect(_on_inventory_changed)

	_inventory = inventory
	_registry = registry
	_crafting = crafting
	_on_craft = on_craft

	if _inventory != null and _inventory.has_signal("changed"):
		_inventory.changed.connect(_on_inventory_changed)

	_build_recipes()
	_refresh_slots()


func _build_slots() -> void:
	_slot_swatches.clear()
	_slot_counts.clear()
	for child in _grid.get_children():
		child.queue_free()
	_grid.columns = GRID_COLUMNS
	for i in range(SLOT_COUNT):
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(48, 48)
		swatch.color = EMPTY_SLOT_COLOR
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var count := Label.new()
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count.set_anchors_preset(Control.PRESET_FULL_RECT)
		count.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
		count.add_theme_font_size_override("font_size", 13)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.add_child(count)

		_grid.add_child(swatch)
		_slot_swatches.append(swatch)
		_slot_counts.append(count)


func _build_recipes() -> void:
	for child in _recipe_list.get_children():
		child.queue_free()
	if _registry == null or not _registry.has_method("recipes"):
		return
	var recipes: Array = _registry.recipes()
	for recipe in recipes:
		_recipe_list.add_child(_make_recipe_row(recipe))


func _make_recipe_row(recipe: Object) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label := Label.new()
	name_label.text = String(recipe.display_name)
	name_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 1.0))
	info.add_child(name_label)

	var inputs_label := Label.new()
	inputs_label.text = _format_inputs(recipe)
	inputs_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 1.0))
	inputs_label.add_theme_font_size_override("font_size", 12)
	info.add_child(inputs_label)

	row.add_child(info)

	var button := Button.new()
	button.text = "Craft"
	button.disabled = not _can_craft(recipe)
	button.pressed.connect(_on_craft_pressed.bind(recipe))
	row.add_child(button)

	return row


func _format_inputs(recipe: Object) -> String:
	var parts: PackedStringArray = []
	for amount in recipe.inputs:
		if amount == null:
			continue
		parts.append("%dx %s" % [amount.count, _label_for(amount.item_id)])
	if recipe.output != null:
		return (
			"%s -> %dx %s"
			% ["  ".join(parts), recipe.output.count, _label_for(recipe.output.item_id)]
		)
	return "  ".join(parts)


func _label_for(id: StringName) -> String:
	if _registry != null and _registry.has_method("item"):
		var def: Object = _registry.item(id)
		if def != null and not String(def.display_name).is_empty():
			return def.display_name
	return String(id)


func _can_craft(recipe: Object) -> bool:
	if _crafting == null or _inventory == null:
		return false
	if not _crafting.has_method("can_craft"):
		return false
	return _crafting.can_craft(_inventory, recipe)


func _on_craft_pressed(recipe: Object) -> void:
	if _on_craft.is_valid():
		_on_craft.call(recipe)


func _on_inventory_changed() -> void:
	_refresh_slots()
	_refresh_recipe_buttons()


func _refresh_slots() -> void:
	if _inventory == null or not _inventory.has_method("slot"):
		return
	var n: int = _inventory.size() if _inventory.has_method("size") else SLOT_COUNT
	for i in range(SLOT_COUNT):
		var swatch := _slot_swatches[i]
		var count_label := _slot_counts[i]
		if i >= n:
			swatch.color = EMPTY_SLOT_COLOR
			count_label.text = ""
			swatch.tooltip_text = ""
			continue
		var data: Dictionary = _inventory.slot(i)
		if data.is_empty():
			swatch.color = EMPTY_SLOT_COLOR
			count_label.text = ""
			swatch.tooltip_text = ""
		else:
			var id: StringName = data["id"]
			swatch.color = _swatch_color_for(id)
			count_label.text = str(data["count"])
			swatch.tooltip_text = _label_for(id)


func _refresh_recipe_buttons() -> void:
	for row in _recipe_list.get_children():
		var idx := row.get_index()
		if _registry == null or not _registry.has_method("recipes"):
			return
		var recipes: Array = _registry.recipes()
		if idx >= recipes.size():
			continue
		var recipe: Object = recipes[idx]
		var button := row.get_child(row.get_child_count() - 1) as Button
		if button != null:
			button.disabled = not _can_craft(recipe)


func _swatch_color_for(id: StringName) -> Color:
	if _registry != null and _registry.has_method("item"):
		var def: Object = _registry.item(id)
		if def != null:
			return def.swatch_color
	return Color.WHITE
