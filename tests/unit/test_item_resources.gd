## Tests that all item and recipe .tres resources load correctly and satisfy
## the Phase 2 data contracts.
##
## Validates: script_class types, id uniqueness, swatch color distinctness,
## recipe inputs non-empty, recipe output validity, and recipe ingredient
## item_ids match known item ids.
extends GutTest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const ITEMS_DIR := "res://resources/items"
const RECIPES_DIR := "res://resources/recipes"

## Expected item ids — all six Phase 2 items must be present.
const EXPECTED_ITEM_IDS: Array = [
	&"soil",
	&"crystal_shard",
	&"glow_spore",
	&"lumen_petal",
	&"bloom_brick",
	&"lumen_torch",
]

## Expected recipe ids.
const EXPECTED_RECIPE_IDS: Array = [
	&"bloom_brick",
	&"lumen_torch",
]


## Load all .tres files from a directory; return Array of loaded resources.
func _load_dir(dir_path: String) -> Array:
	var results: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Cannot open dir: " + dir_path)
		return results
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if (
			not dir.current_is_dir()
			and (fname.ends_with(".tres") or fname.ends_with(".tres.remap"))
		):
			var path := dir_path + "/" + fname
			var res := ResourceLoader.load(path)
			if res != null:
				results.append(res)
		fname = dir.get_next()
	dir.list_dir_end()
	return results


# ---------------------------------------------------------------------------
# ItemDef tests
# ---------------------------------------------------------------------------


func test_all_expected_item_ids_are_present() -> void:
	var items := _load_dir(ITEMS_DIR)
	var loaded_ids: Array = []
	for item in items:
		if item is ItemDef:
			loaded_ids.append(item.id)
	for expected_id in EXPECTED_ITEM_IDS:
		assert_true(
			loaded_ids.has(expected_id),
			"Expected item id %s to be present in resources/items/" % expected_id
		)


func test_item_defs_have_correct_script_class() -> void:
	var items := _load_dir(ITEMS_DIR)
	assert_true(items.size() > 0, "Should load at least one item resource")
	for item in items:
		assert_true(
			item is ItemDef,
			"All resources in resources/items/ must be ItemDef, got: %s" % str(item)
		)


func test_item_ids_are_unique() -> void:
	var items := _load_dir(ITEMS_DIR)
	var seen_ids: Array = []
	for item in items:
		if item is ItemDef:
			assert_false(seen_ids.has(item.id), "Duplicate item id found: %s" % item.id)
			seen_ids.append(item.id)


func test_item_ids_are_non_empty() -> void:
	var items := _load_dir(ITEMS_DIR)
	for item in items:
		if item is ItemDef:
			assert_true(
				item.id != &"", "ItemDef display_name='%s' has empty id" % item.display_name
			)


func test_item_display_names_are_non_empty() -> void:
	var items := _load_dir(ITEMS_DIR)
	for item in items:
		if item is ItemDef:
			assert_true(item.display_name != "", "ItemDef id='%s' has empty display_name" % item.id)


func test_item_max_stack_is_positive() -> void:
	var items := _load_dir(ITEMS_DIR)
	for item in items:
		if item is ItemDef:
			assert_true(item.max_stack > 0, "ItemDef id='%s' max_stack must be > 0" % item.id)


func test_item_swatch_colors_are_distinct() -> void:
	var items := _load_dir(ITEMS_DIR)
	var colors: Array = []
	var ids: Array = []
	for item in items:
		if item is ItemDef:
			# Compare by rounded rgb to allow minor float variance
			var key := Vector3(
				snappedf(item.swatch_color.r, 0.01),
				snappedf(item.swatch_color.g, 0.01),
				snappedf(item.swatch_color.b, 0.01)
			)
			assert_false(
				colors.has(key), "Duplicate swatch_color detected for item id='%s'" % item.id
			)
			colors.append(key)
			ids.append(item.id)


## Per-item id/category checks plus a swatch-hue assertion, data-driven so each
## item is validated without a separate test method (keeps the suite under the
## linter's public-method ceiling).
func test_individual_items_match_spec() -> void:
	var item := _load_item("soil")
	assert_eq(item.id, &"soil")
	assert_eq(item.category, &"material")
	# Soil: dusky violet-brown — red channel dominant over green.
	assert_true(item.swatch_color.r > item.swatch_color.g, "Soil swatch should be violet-brownish")

	item = _load_item("crystal_shard")
	assert_eq(item.id, &"crystal_shard")
	# Electric blue: blue channel dominant.
	assert_true(
		item.swatch_color.b > item.swatch_color.r, "Crystal shard swatch should be blue-dominant"
	)

	item = _load_item("glow_spore")
	assert_eq(item.id, &"glow_spore")
	# Cyan: green and blue dominant, red low.
	assert_true(item.swatch_color.g > 0.5, "Glow spore swatch should be cyan/green-dominant")

	item = _load_item("lumen_petal")
	assert_eq(item.id, &"lumen_petal")
	# Magenta: red and blue dominant, green low.
	assert_true(item.swatch_color.r > 0.5, "Lumen petal swatch should be magenta")
	assert_true(item.swatch_color.b > 0.5, "Lumen petal swatch should be magenta")

	item = _load_item("bloom_brick")
	assert_eq(item.id, &"bloom_brick")
	assert_eq(item.category, &"placeable")
	# Lavender: all channels present, blue slightly dominant.
	assert_true(item.swatch_color.b > 0.5, "Bloom brick swatch should be lavender")

	item = _load_item("lumen_torch")
	assert_eq(item.id, &"lumen_torch")
	assert_eq(item.category, &"placeable")
	# Warm gold: red high, blue low.
	assert_true(item.swatch_color.r > 0.8, "Lumen torch swatch should be warm gold")
	assert_true(item.swatch_color.b < 0.4, "Lumen torch swatch should be warm gold (low blue)")


## Load a single item .tres by stem and assert it is a valid ItemDef.
func _load_item(stem: String) -> ItemDef:
	var res := ResourceLoader.load(ITEMS_DIR + "/" + stem + ".tres")
	assert_not_null(res, "%s.tres must load" % stem)
	assert_true(res is ItemDef, "%s.tres must be ItemDef" % stem)
	return res


# ---------------------------------------------------------------------------
# Recipe tests
# ---------------------------------------------------------------------------


func test_all_expected_recipe_ids_are_present() -> void:
	var recipes := _load_dir(RECIPES_DIR)
	var loaded_ids: Array = []
	for recipe in recipes:
		if recipe is Recipe:
			loaded_ids.append(recipe.id)
	for expected_id in EXPECTED_RECIPE_IDS:
		assert_true(
			loaded_ids.has(expected_id),
			"Expected recipe id %s to be present in resources/recipes/" % expected_id
		)


func test_recipe_defs_have_correct_script_class() -> void:
	var recipes := _load_dir(RECIPES_DIR)
	assert_true(recipes.size() > 0, "Should load at least one recipe resource")
	for recipe in recipes:
		assert_true(
			recipe is Recipe,
			"All resources in resources/recipes/ must be Recipe, got: %s" % str(recipe)
		)


func test_recipe_ids_are_unique() -> void:
	var recipes := _load_dir(RECIPES_DIR)
	var seen_ids: Array = []
	for recipe in recipes:
		if recipe is Recipe:
			assert_false(seen_ids.has(recipe.id), "Duplicate recipe id found: %s" % recipe.id)
			seen_ids.append(recipe.id)


func test_recipe_inputs_are_non_empty() -> void:
	var recipes := _load_dir(RECIPES_DIR)
	for recipe in recipes:
		if recipe is Recipe:
			assert_true(
				recipe.inputs.size() > 0,
				"Recipe id='%s' must have at least one input ingredient" % recipe.id
			)


func test_recipe_inputs_are_item_amounts() -> void:
	var recipes := _load_dir(RECIPES_DIR)
	for recipe in recipes:
		if recipe is Recipe:
			for inp in recipe.inputs:
				assert_true(
					inp is ItemAmount,
					"Recipe id='%s' input must be ItemAmount, got: %s" % [recipe.id, str(inp)]
				)
				assert_true(
					inp.item_id != &"", "Recipe id='%s' input has empty item_id" % recipe.id
				)
				assert_true(inp.count > 0, "Recipe id='%s' input count must be > 0" % recipe.id)


func test_recipe_output_is_valid() -> void:
	var recipes := _load_dir(RECIPES_DIR)
	for recipe in recipes:
		if recipe is Recipe:
			assert_not_null(recipe.output, "Recipe id='%s' must have a non-null output" % recipe.id)
			assert_true(
				recipe.output is ItemAmount, "Recipe id='%s' output must be ItemAmount" % recipe.id
			)
			assert_true(
				recipe.output.item_id != &"", "Recipe id='%s' output has empty item_id" % recipe.id
			)
			assert_true(
				recipe.output.count > 0, "Recipe id='%s' output count must be > 0" % recipe.id
			)


func test_recipe_bloom_brick_ingredients() -> void:
	var res := ResourceLoader.load(RECIPES_DIR + "/bloom_brick.tres")
	assert_not_null(res, "bloom_brick.tres must load")
	assert_true(res is Recipe)
	var recipe: Recipe = res
	assert_eq(recipe.id, &"bloom_brick")
	assert_eq(recipe.inputs.size(), 2, "Bloom Brick needs exactly 2 input types")
	# Find soil ingredient
	var soil_input: ItemAmount = null
	var crystal_input: ItemAmount = null
	for inp in recipe.inputs:
		if inp.item_id == &"soil":
			soil_input = inp
		elif inp.item_id == &"crystal_shard":
			crystal_input = inp
	assert_not_null(soil_input, "Bloom Brick recipe must require soil")
	assert_eq(soil_input.count, 4, "Bloom Brick recipe needs 4 soil")
	assert_not_null(crystal_input, "Bloom Brick recipe must require crystal_shard")
	assert_eq(crystal_input.count, 1, "Bloom Brick recipe needs 1 crystal_shard")
	assert_eq(recipe.output.item_id, &"bloom_brick")
	assert_eq(recipe.output.count, 2, "Bloom Brick recipe outputs 2 bloom_brick")


func test_recipe_lumen_torch_ingredients() -> void:
	var res := ResourceLoader.load(RECIPES_DIR + "/lumen_torch.tres")
	assert_not_null(res, "lumen_torch.tres must load")
	assert_true(res is Recipe)
	var recipe: Recipe = res
	assert_eq(recipe.id, &"lumen_torch")
	assert_eq(recipe.inputs.size(), 3, "Lumen Torch needs exactly 3 input types")
	var crystal_input: ItemAmount = null
	var spore_input: ItemAmount = null
	var petal_input: ItemAmount = null
	for inp in recipe.inputs:
		if inp.item_id == &"crystal_shard":
			crystal_input = inp
		elif inp.item_id == &"glow_spore":
			spore_input = inp
		elif inp.item_id == &"lumen_petal":
			petal_input = inp
	assert_not_null(crystal_input, "Lumen Torch recipe must require crystal_shard")
	assert_eq(crystal_input.count, 1, "Lumen Torch recipe needs 1 crystal_shard")
	assert_not_null(spore_input, "Lumen Torch recipe must require glow_spore")
	assert_eq(spore_input.count, 2, "Lumen Torch recipe needs 2 glow_spore")
	assert_not_null(petal_input, "Lumen Torch recipe must require lumen_petal")
	assert_eq(petal_input.count, 1, "Lumen Torch recipe needs 1 lumen_petal")
	assert_eq(recipe.output.item_id, &"lumen_torch")
	assert_eq(recipe.output.count, 1, "Lumen Torch recipe outputs 1 lumen_torch")


func test_recipe_ingredient_ids_are_known_items() -> void:
	var recipes := _load_dir(RECIPES_DIR)
	for recipe in recipes:
		if recipe is Recipe:
			for inp in recipe.inputs:
				assert_true(
					EXPECTED_ITEM_IDS.has(inp.item_id),
					(
						"Recipe id='%s' input item_id='%s' is not a known item"
						% [recipe.id, inp.item_id]
					)
				)
			assert_true(
				EXPECTED_ITEM_IDS.has(recipe.output.item_id),
				(
					"Recipe id='%s' output item_id='%s' is not a known item"
					% [recipe.id, recipe.output.item_id]
				)
			)
