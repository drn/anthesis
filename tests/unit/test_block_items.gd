## Validates the Phase 6 sequencer items and recipes (.tres data contracts).
##
## Pins the loaded values for the Sequencer Core and Note Block item defs and
## their crafting recipes so any drift in the resource files is caught here.
extends GutTest

const ITEMS_DIR := "res://resources/items"
const RECIPES_DIR := "res://resources/recipes"


func _load_item(stem: String) -> ItemDef:
	var res := ResourceLoader.load(ITEMS_DIR + "/" + stem + ".tres")
	assert_not_null(res, "%s.tres must load" % stem)
	assert_true(res is ItemDef, "%s.tres must be ItemDef" % stem)
	return res


func _load_recipe(stem: String) -> Recipe:
	var res := ResourceLoader.load(RECIPES_DIR + "/" + stem + ".tres")
	assert_not_null(res, "%s.tres must load" % stem)
	assert_true(res is Recipe, "%s.tres must be Recipe" % stem)
	return res


# ---------------------------------------------------------------------------
# Item defs
# ---------------------------------------------------------------------------


func test_sequencer_core_item() -> void:
	var item := _load_item("sequencer_core")
	assert_eq(item.id, &"sequencer_core")
	assert_eq(item.display_name, "Sequencer Core")
	assert_eq(item.category, &"placeable")
	assert_eq(item.max_stack, 4)
	# Warm gold-white: every channel bright, red >= blue.
	assert_true(item.swatch_color.r > 0.8, "Core swatch should be warm gold-white")
	assert_true(item.swatch_color.r >= item.swatch_color.b, "Core swatch is warm (red-leaning)")
	assert_true(item.description != "", "Core needs flavor text")


func test_note_block_item() -> void:
	var item := _load_item("note_block")
	assert_eq(item.id, &"note_block")
	assert_eq(item.display_name, "Note Block")
	assert_eq(item.category, &"placeable")
	assert_eq(item.max_stack, 24)
	# Iridescent violet: red and blue present, blue dominant.
	assert_true(item.swatch_color.b > item.swatch_color.g, "Note block swatch should be violet")
	assert_true(item.swatch_color.r > item.swatch_color.g, "Note block swatch should be violet")
	assert_true(item.description != "", "Note block needs flavor text")


# ---------------------------------------------------------------------------
# Recipes
# ---------------------------------------------------------------------------


## Map a recipe's inputs to {item_id: count} for order-independent assertions.
func _input_counts(recipe: Recipe) -> Dictionary:
	var out: Dictionary = {}
	for inp in recipe.inputs:
		out[inp.item_id] = inp.count
	return out


func test_sequencer_core_recipe() -> void:
	var recipe := _load_recipe("sequencer_core")
	assert_eq(recipe.id, &"sequencer_core")
	var counts := _input_counts(recipe)
	assert_eq(counts.size(), 3, "Core recipe has exactly 3 input types")
	assert_eq(counts.get(&"bloom_brick", 0), 2, "Core needs 2 bloom_brick")
	assert_eq(counts.get(&"crystal_shard", 0), 2, "Core needs 2 crystal_shard")
	assert_eq(counts.get(&"lumen_torch", 0), 1, "Core needs 1 lumen_torch")
	assert_eq(recipe.output.item_id, &"sequencer_core")
	assert_eq(recipe.output.count, 1, "Core recipe outputs 1")


func test_note_block_recipe() -> void:
	var recipe := _load_recipe("note_block")
	assert_eq(recipe.id, &"note_block")
	var counts := _input_counts(recipe)
	assert_eq(counts.size(), 2, "Note block recipe has exactly 2 input types")
	assert_eq(counts.get(&"bloom_brick", 0), 1, "Note block needs 1 bloom_brick")
	assert_eq(counts.get(&"glow_spore", 0), 1, "Note block needs 1 glow_spore")
	assert_eq(recipe.output.item_id, &"note_block")
	assert_eq(recipe.output.count, 2, "Note block recipe outputs 2")


func test_recipes_resolve_via_registry() -> void:
	var registry := ItemRegistry.new(ITEMS_DIR, RECIPES_DIR)
	assert_not_null(registry.item(&"sequencer_core"), "registry indexes sequencer_core item")
	assert_not_null(registry.item(&"note_block"), "registry indexes note_block item")
	assert_not_null(registry.recipe(&"sequencer_core"), "registry indexes sequencer_core recipe")
	assert_not_null(registry.recipe(&"note_block"), "registry indexes note_block recipe")


func test_recipe_inputs_are_known_items() -> void:
	var registry := ItemRegistry.new(ITEMS_DIR, RECIPES_DIR)
	for stem in ["sequencer_core", "note_block"]:
		var recipe := _load_recipe(stem)
		for inp in recipe.inputs:
			assert_not_null(
				registry.item(inp.item_id), "%s input %s must be a known item" % [stem, inp.item_id]
			)
		assert_not_null(
			registry.item(recipe.output.item_id),
			"%s output %s must be a known item" % [stem, recipe.output.item_id]
		)
