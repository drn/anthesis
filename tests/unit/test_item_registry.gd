extends GutTest

# ---------------------------------------------------------------------------
# Canonical Phase 2 data ids (authored by the data agent as .tres resources).
# ---------------------------------------------------------------------------

const EXPECTED_ITEM_IDS := [
	&"soil",
	&"crystal_shard",
	&"glow_spore",
	&"lumen_petal",
	&"bloom_brick",
	&"lumen_torch",
	&"lodestone_ore",
	&"skysteel_ore",
	&"vigorite_ore",
	&"keenglass_shard",
	&"iron_flakes",
	&"steel_flakes",
	&"pewter_flakes",
	&"tin_flakes",
	&"ferric_coin",
	&"dun_gem",
	&"charged_gem",
	&"storm_catcher",
]
const EXPECTED_RECIPE_IDS := [
	&"bloom_brick",
	&"lumen_torch",
	&"iron_flakes",
	&"steel_flakes",
	&"pewter_flakes",
	&"tin_flakes",
	&"ferric_coin",
	&"dun_gem",
	&"storm_catcher",
]

# ---------------------------------------------------------------------------
# Scanning real resource directories
# ---------------------------------------------------------------------------


func test_scans_all_expected_items() -> void:
	var reg := ItemRegistry.new()  # default res://resources/items + recipes
	var ids := reg.item_ids()
	for expected in EXPECTED_ITEM_IDS:
		assert_true(ids.has(expected), "Registry must contain item id '%s'" % expected)


func test_items_resolve_to_itemdef() -> void:
	var reg := ItemRegistry.new()
	for expected in EXPECTED_ITEM_IDS:
		var def := reg.item(expected)
		assert_not_null(def, "item('%s') must resolve" % expected)
		if def != null:
			assert_eq(def.id, expected, "ItemDef.id must match its lookup key")


func test_scans_all_expected_recipes() -> void:
	var reg := ItemRegistry.new()
	var recipe_ids: Array[StringName] = []
	for r in reg.recipes():
		recipe_ids.append(r.id)
	for expected in EXPECTED_RECIPE_IDS:
		assert_true(recipe_ids.has(expected), "Registry must contain recipe id '%s'" % expected)


func test_recipe_lookup_by_id() -> void:
	var reg := ItemRegistry.new()
	for expected in EXPECTED_RECIPE_IDS:
		var rec := reg.recipe(expected)
		assert_not_null(rec, "recipe('%s') must resolve" % expected)
		if rec != null:
			assert_eq(rec.id, expected, "Recipe.id must match its lookup key")


func test_bloom_brick_recipe_shape() -> void:
	# Sanity-check the data agent's canonical recipe wiring loads correctly.
	var reg := ItemRegistry.new()
	var rec := reg.recipe(&"bloom_brick")
	assert_not_null(rec, "bloom_brick recipe must exist")
	if rec == null:
		return
	assert_not_null(rec.output, "Recipe must have an output")
	assert_eq(rec.output.item_id, &"bloom_brick", "bloom_brick outputs bloom_brick")
	assert_false(rec.inputs.is_empty(), "bloom_brick must declare inputs")


# ---------------------------------------------------------------------------
# Defensive behavior
# ---------------------------------------------------------------------------


func test_missing_dirs_yield_empty_registry() -> void:
	var reg := ItemRegistry.new("res://__no_such_items__", "res://__no_such_recipes__")
	assert_eq(reg.item_ids().size(), 0, "Missing items dir => no items")
	assert_eq(reg.recipes().size(), 0, "Missing recipes dir => no recipes")
	assert_null(reg.item(&"soil"), "Unknown item => null")
	assert_null(reg.recipe(&"bloom_brick"), "Unknown recipe => null")


func test_unknown_id_returns_null() -> void:
	var reg := ItemRegistry.new()
	assert_null(reg.item(&"not_a_real_item"), "Unknown item id => null")
	assert_null(reg.recipe(&"not_a_real_recipe"), "Unknown recipe id => null")
