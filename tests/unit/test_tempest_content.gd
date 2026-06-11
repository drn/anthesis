## Validates Phase 9 Tempestlight content contracts:
##   - 3 new items load with pinned categories and stack sizes.
##   - 2 new recipes load with pinned ingredients and outputs.
##   - 2 new abilities load with pinned resource_kind, cost, cooldown, magnitude.
##   - AbilityRegistry now contains all 7 abilities (5 Phase 3+8 + 2 new).
##   - ItemRegistry contains all Phase 9 items and recipes.
extends GutTest

const ITEMS_DIR := "res://resources/items"
const RECIPES_DIR := "res://resources/recipes"
const ABILITIES_DIR := "res://resources/abilities"

# ---------------------------------------------------------------------------
# Item contract checks — Phase 9 additions
# ---------------------------------------------------------------------------


func test_dun_gem_item_loads_with_correct_values() -> void:
	var res := ResourceLoader.load(ITEMS_DIR + "/dun_gem.tres")
	assert_not_null(res, "dun_gem.tres must load")
	if res == null:
		return
	assert_true(res is ItemDef, "dun_gem must be ItemDef")
	var item: ItemDef = res
	assert_eq(item.id, &"dun_gem")
	assert_eq(item.category, &"material")
	assert_eq(item.max_stack, 16)
	assert_true(item.display_name != "", "dun_gem must have display_name")
	assert_true(item.description != "", "dun_gem must have description")


func test_charged_gem_item_loads_with_correct_values() -> void:
	var res := ResourceLoader.load(ITEMS_DIR + "/charged_gem.tres")
	assert_not_null(res, "charged_gem.tres must load")
	if res == null:
		return
	assert_true(res is ItemDef, "charged_gem must be ItemDef")
	var item: ItemDef = res
	assert_eq(item.id, &"charged_gem")
	assert_eq(item.category, &"material")
	assert_eq(item.max_stack, 16)
	assert_true(item.display_name != "", "charged_gem must have display_name")
	assert_true(item.description != "", "charged_gem must have description")


func test_storm_catcher_item_loads_with_correct_values() -> void:
	var res := ResourceLoader.load(ITEMS_DIR + "/storm_catcher.tres")
	assert_not_null(res, "storm_catcher.tres must load")
	if res == null:
		return
	assert_true(res is ItemDef, "storm_catcher must be ItemDef")
	var item: ItemDef = res
	assert_eq(item.id, &"storm_catcher")
	assert_eq(item.category, &"placeable")
	assert_eq(item.max_stack, 8)
	assert_true(item.display_name != "", "storm_catcher must have display_name")
	assert_true(item.description != "", "storm_catcher must have description")


# ---------------------------------------------------------------------------
# Recipe contract checks — Phase 9 additions
# ---------------------------------------------------------------------------


func test_dun_gem_recipe_loads_with_pinned_values() -> void:
	var res := ResourceLoader.load(RECIPES_DIR + "/dun_gem.tres")
	assert_not_null(res, "dun_gem recipe must load")
	if res == null:
		return
	assert_true(res is Recipe, "dun_gem recipe must be Recipe")
	var recipe: Recipe = res
	assert_eq(recipe.id, &"dun_gem")
	assert_eq(recipe.inputs.size(), 2, "dun_gem recipe must have 2 inputs")
	var crystal_input: ItemAmount = null
	var spore_input: ItemAmount = null
	for inp in recipe.inputs:
		if inp.item_id == &"crystal_shard":
			crystal_input = inp
		elif inp.item_id == &"glow_spore":
			spore_input = inp
	assert_not_null(crystal_input, "dun_gem recipe must require crystal_shard")
	if crystal_input != null:
		assert_eq(crystal_input.count, 3, "dun_gem needs 3 crystal_shard")
	assert_not_null(spore_input, "dun_gem recipe must require glow_spore")
	if spore_input != null:
		assert_eq(spore_input.count, 1, "dun_gem needs 1 glow_spore")
	assert_not_null(recipe.output)
	if recipe.output != null:
		assert_eq(recipe.output.item_id, &"dun_gem")
		assert_eq(recipe.output.count, 1)


func test_storm_catcher_recipe_loads_with_pinned_values() -> void:
	var res := ResourceLoader.load(RECIPES_DIR + "/storm_catcher.tres")
	assert_not_null(res, "storm_catcher recipe must load")
	if res == null:
		return
	assert_true(res is Recipe, "storm_catcher recipe must be Recipe")
	var recipe: Recipe = res
	assert_eq(recipe.id, &"storm_catcher")
	assert_eq(recipe.inputs.size(), 3, "storm_catcher recipe must have 3 inputs")
	var crystal_input: ItemAmount = null
	var keenglass_input: ItemAmount = null
	var soil_input: ItemAmount = null
	for inp in recipe.inputs:
		if inp.item_id == &"crystal_shard":
			crystal_input = inp
		elif inp.item_id == &"keenglass_shard":
			keenglass_input = inp
		elif inp.item_id == &"soil":
			soil_input = inp
	assert_not_null(crystal_input, "storm_catcher needs crystal_shard")
	if crystal_input != null:
		assert_eq(crystal_input.count, 2, "storm_catcher needs 2 crystal_shard")
	assert_not_null(keenglass_input, "storm_catcher needs keenglass_shard")
	if keenglass_input != null:
		assert_eq(keenglass_input.count, 1, "storm_catcher needs 1 keenglass_shard")
	assert_not_null(soil_input, "storm_catcher needs soil")
	if soil_input != null:
		assert_eq(soil_input.count, 2, "storm_catcher needs 2 soil")
	assert_not_null(recipe.output)
	if recipe.output != null:
		assert_eq(recipe.output.item_id, &"storm_catcher")
		assert_eq(recipe.output.count, 1)


# ---------------------------------------------------------------------------
# Ability contract checks — Phase 9 additions
# ---------------------------------------------------------------------------


func test_sky_lash_ability_loads_with_pinned_values() -> void:
	var res := ResourceLoader.load(ABILITIES_DIR + "/sky_lash.tres")
	assert_not_null(res, "sky_lash.tres must load")
	if res == null:
		return
	assert_true(res is AbilityDef, "sky_lash must be AbilityDef")
	var ab: AbilityDef = res
	assert_eq(ab.id, &"sky_lash")
	assert_eq(ab.kind, &"sky_lash")
	assert_eq(ab.resource_kind, &"tempest")
	assert_eq(ab.lumen_cost, 20.0)
	assert_eq(ab.cooldown_ticks, 10)
	assert_eq(ab.magnitude, 6.0)
	assert_true(ab.description != "", "sky_lash must have description")


func test_bond_lash_ability_loads_with_pinned_values() -> void:
	var res := ResourceLoader.load(ABILITIES_DIR + "/bond_lash.tres")
	assert_not_null(res, "bond_lash.tres must load")
	if res == null:
		return
	assert_true(res is AbilityDef, "bond_lash must be AbilityDef")
	var ab: AbilityDef = res
	assert_eq(ab.id, &"bond_lash")
	assert_eq(ab.kind, &"bond_lash")
	assert_eq(ab.resource_kind, &"tempest")
	assert_eq(ab.lumen_cost, 15.0)
	assert_eq(ab.cooldown_ticks, 10)
	assert_eq(ab.magnitude, 5.0)
	assert_true(ab.description != "", "bond_lash must have description")


# ---------------------------------------------------------------------------
# Registry-count assertions (abilities 5 → 7)
# ---------------------------------------------------------------------------


func test_ability_registry_contains_all_seven_abilities() -> void:
	var reg := AbilityRegistry.new()
	var ids := reg.ability_ids()
	assert_true(ids.size() >= 7, "AbilityRegistry must contain at least 7 abilities (Phase 9)")
	assert_true(ids.has(&"bond_lash"), "registry must contain bond_lash")
	assert_true(ids.has(&"sky_lash"), "registry must contain sky_lash")
	assert_true(ids.has(&"ferro_pull"), "registry must still contain ferro_pull")
	assert_true(ids.has(&"ferro_push"), "registry must still contain ferro_push")
	assert_true(ids.has(&"lumen_bloom"), "registry must still contain lumen_bloom")
	assert_true(ids.has(&"shape_burst"), "registry must still contain shape_burst")
	assert_true(ids.has(&"skyward"), "registry must still contain skyward")


func test_ability_registry_phase9_sorted_order() -> void:
	# Phase 9 alphabetical slot order per contract: bond_lash(1), ferro_pull(2),
	# ferro_push(3), lumen_bloom(4), shape_burst(5), sky_lash(6), skyward(7).
	var reg := AbilityRegistry.new()
	var ids := reg.ability_ids()
	var expected_phase9_order: Array = [
		&"bond_lash",
		&"ferro_pull",
		&"ferro_push",
		&"lumen_bloom",
		&"shape_burst",
		&"sky_lash",
		&"skyward",
	]
	for i in range(expected_phase9_order.size()):
		var eid: StringName = expected_phase9_order[i]
		var idx := ids.find(eid)
		assert_true(idx >= 0, "ability '%s' must be in registry" % eid)
	# Verify sorted: alphabetical
	for i in range(ids.size() - 1):
		assert_true(
			str(ids[i]) <= str(ids[i + 1]),
			"ability_ids() must be sorted: '%s' before '%s'" % [ids[i], ids[i + 1]]
		)


func test_item_registry_contains_phase9_items() -> void:
	var reg := ItemRegistry.new()
	var ids := reg.item_ids()
	assert_true(ids.has(&"dun_gem"), "ItemRegistry must contain dun_gem")
	assert_true(ids.has(&"charged_gem"), "ItemRegistry must contain charged_gem")
	assert_true(ids.has(&"storm_catcher"), "ItemRegistry must contain storm_catcher")


func test_item_registry_contains_phase9_recipes() -> void:
	var reg := ItemRegistry.new()
	var recipe_ids: Array[StringName] = []
	for r in reg.recipes():
		recipe_ids.append(r.id)
	assert_true(recipe_ids.has(&"dun_gem"), "ItemRegistry must contain dun_gem recipe")
	assert_true(recipe_ids.has(&"storm_catcher"), "ItemRegistry must contain storm_catcher recipe")
