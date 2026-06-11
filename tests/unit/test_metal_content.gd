## Validates Phase 8 ferromancy content contracts:
##   - 9 new items load with pinned categories and stack sizes.
##   - 5 new recipes load with pinned ingredients and outputs.
##   - 2 ferro abilities load with pinned resource_kind, cost, cooldown, magnitude.
##   - CreatureDef.metal_mass defaults to 0.0 on a plain def.
##   - shardling.tres has metal_mass = 60.0.
extends GutTest

const ITEMS_DIR := "res://resources/items"
const RECIPES_DIR := "res://resources/recipes"
const ABILITIES_DIR := "res://resources/abilities"
const CREATURES_DIR := "res://resources/creatures"

# ---------------------------------------------------------------------------
# Item contract checks
# ---------------------------------------------------------------------------


func test_raw_ore_items_load_with_correct_category() -> void:
	var ore_ids := [&"lodestone_ore", &"skysteel_ore", &"vigorite_ore", &"keenglass_shard"]
	for ore_id in ore_ids:
		var res := ResourceLoader.load(ITEMS_DIR + "/" + str(ore_id) + ".tres")
		assert_not_null(res, "%s must load" % ore_id)
		if res == null:
			continue
		assert_true(res is ItemDef, "%s must be ItemDef" % ore_id)
		var item: ItemDef = res
		assert_eq(item.id, ore_id, "%s id must match" % ore_id)
		assert_eq(item.category, &"material", "%s must be category material" % ore_id)
		assert_eq(item.max_stack, 64, "%s must have max_stack 64" % ore_id)


func test_flake_items_load_with_correct_category_and_stack() -> void:
	var flake_ids := [&"iron_flakes", &"steel_flakes", &"pewter_flakes", &"tin_flakes"]
	for flake_id in flake_ids:
		var res := ResourceLoader.load(ITEMS_DIR + "/" + str(flake_id) + ".tres")
		assert_not_null(res, "%s must load" % flake_id)
		if res == null:
			continue
		assert_true(res is ItemDef, "%s must be ItemDef" % flake_id)
		var item: ItemDef = res
		assert_eq(item.id, flake_id, "%s id must match" % flake_id)
		assert_eq(item.category, &"consumable", "%s must be category consumable" % flake_id)
		assert_eq(item.max_stack, 99, "%s must have max_stack 99" % flake_id)


func test_ferric_coin_item_loads_with_correct_values() -> void:
	var res := ResourceLoader.load(ITEMS_DIR + "/ferric_coin.tres")
	assert_not_null(res, "ferric_coin item must load")
	if res == null:
		return
	assert_true(res is ItemDef, "ferric_coin must be ItemDef")
	var item: ItemDef = res
	assert_eq(item.id, &"ferric_coin")
	assert_eq(item.category, &"material")
	assert_eq(item.max_stack, 99)


# ---------------------------------------------------------------------------
# Recipe contract checks
# ---------------------------------------------------------------------------


func test_ore_to_flake_recipes_load_with_pinned_values() -> void:
	var pairs := [
		[&"iron_flakes", &"lodestone_ore", 1, 2],
		[&"steel_flakes", &"skysteel_ore", 1, 2],
		[&"pewter_flakes", &"vigorite_ore", 1, 2],
		[&"tin_flakes", &"keenglass_shard", 1, 2],
	]
	for pair in pairs:
		var recipe_id: StringName = pair[0]
		var input_id: StringName = pair[1]
		var input_count: int = pair[2]
		var output_count: int = pair[3]
		var res := ResourceLoader.load(RECIPES_DIR + "/" + str(recipe_id) + ".tres")
		assert_not_null(res, "%s recipe must load" % recipe_id)
		if res == null:
			continue
		assert_true(res is Recipe, "%s must be Recipe" % recipe_id)
		var recipe: Recipe = res
		assert_eq(recipe.id, recipe_id, "%s recipe id must match" % recipe_id)
		assert_eq(recipe.inputs.size(), 1, "%s recipe must have 1 input" % recipe_id)
		if recipe.inputs.size() >= 1:
			assert_eq(
				recipe.inputs[0].item_id, input_id, "%s input must be %s" % [recipe_id, input_id]
			)
			assert_eq(
				recipe.inputs[0].count,
				input_count,
				"%s input count must be %d" % [recipe_id, input_count]
			)
		assert_not_null(recipe.output, "%s recipe must have output" % recipe_id)
		if recipe.output != null:
			assert_eq(recipe.output.item_id, recipe_id, "%s output must match id" % recipe_id)
			assert_eq(
				recipe.output.count,
				output_count,
				"%s output count must be %d" % [recipe_id, output_count]
			)


func test_ferric_coin_recipe_loads_with_pinned_values() -> void:
	var res := ResourceLoader.load(RECIPES_DIR + "/ferric_coin.tres")
	assert_not_null(res, "ferric_coin recipe must load")
	if res == null:
		return
	assert_true(res is Recipe, "ferric_coin must be Recipe")
	var recipe: Recipe = res
	assert_eq(recipe.id, &"ferric_coin")
	assert_eq(recipe.inputs.size(), 2, "ferric_coin recipe must have 2 inputs")
	var crystal_input: ItemAmount = null
	var soil_input: ItemAmount = null
	for inp in recipe.inputs:
		if inp.item_id == &"crystal_shard":
			crystal_input = inp
		elif inp.item_id == &"soil":
			soil_input = inp
	assert_not_null(crystal_input, "ferric_coin recipe must require crystal_shard")
	if crystal_input != null:
		assert_eq(crystal_input.count, 1, "ferric_coin recipe needs 1 crystal_shard")
	assert_not_null(soil_input, "ferric_coin recipe must require soil")
	if soil_input != null:
		assert_eq(soil_input.count, 2, "ferric_coin recipe needs 2 soil")
	assert_not_null(recipe.output, "ferric_coin recipe must have output")
	if recipe.output != null:
		assert_eq(recipe.output.item_id, &"ferric_coin")
		assert_eq(recipe.output.count, 8, "ferric_coin recipe outputs 8 coins")


# ---------------------------------------------------------------------------
# Ability contract checks
# ---------------------------------------------------------------------------


func test_ferro_pull_ability_loads_with_pinned_values() -> void:
	var res := ResourceLoader.load(ABILITIES_DIR + "/ferro_pull.tres")
	assert_not_null(res, "ferro_pull.tres must load")
	if res == null:
		return
	assert_true(res is AbilityDef, "ferro_pull must be AbilityDef")
	var ab: AbilityDef = res
	assert_eq(ab.id, &"ferro_pull")
	assert_eq(ab.kind, &"ferro_pull")
	assert_eq(ab.resource_kind, &"iron")
	assert_eq(ab.lumen_cost, 12.0)
	assert_eq(ab.cooldown_ticks, 8)
	assert_eq(ab.magnitude, 9.0)
	assert_true(ab.description != "", "ferro_pull must have a description")


func test_ferro_push_ability_loads_with_pinned_values() -> void:
	var res := ResourceLoader.load(ABILITIES_DIR + "/ferro_push.tres")
	assert_not_null(res, "ferro_push.tres must load")
	if res == null:
		return
	assert_true(res is AbilityDef, "ferro_push must be AbilityDef")
	var ab: AbilityDef = res
	assert_eq(ab.id, &"ferro_push")
	assert_eq(ab.kind, &"ferro_push")
	assert_eq(ab.resource_kind, &"steel")
	assert_eq(ab.lumen_cost, 12.0)
	assert_eq(ab.cooldown_ticks, 8)
	assert_eq(ab.magnitude, 11.0)
	assert_true(ab.description != "", "ferro_push must have a description")


# ---------------------------------------------------------------------------
# CreatureDef metal_mass contract checks
# ---------------------------------------------------------------------------


func test_creature_def_metal_mass_defaults_to_zero() -> void:
	var def := CreatureDef.new()
	assert_eq(def.metal_mass, 0.0, "CreatureDef.metal_mass must default to 0.0")


func test_shardling_metal_mass_is_sixty() -> void:
	var res := ResourceLoader.load(CREATURES_DIR + "/shardling.tres")
	assert_not_null(res, "shardling.tres must load")
	if res == null:
		return
	assert_true(res is CreatureDef, "shardling must be CreatureDef")
	var cr: CreatureDef = res
	assert_eq(cr.metal_mass, 60.0, "shardling metal_mass must be 60.0")


func test_voidmoth_metal_mass_is_zero() -> void:
	var res := ResourceLoader.load(CREATURES_DIR + "/voidmoth.tres")
	assert_not_null(res, "voidmoth.tres must load")
	if res == null:
		return
	assert_true(res is CreatureDef, "voidmoth must be CreatureDef")
	var cr: CreatureDef = res
	assert_eq(cr.metal_mass, 0.0, "voidmoth must have metal_mass 0.0 (not ferromantic)")
