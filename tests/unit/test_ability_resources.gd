## Tests that all ability .tres resources load correctly and satisfy
## the Phase 3 data contracts.
##
## Validates: script_class types, id uniqueness, pinned ids/kinds/costs/cooldowns,
## and color distinctness across the three Lumen abilities.
extends GutTest

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ABILITIES_DIR := "res://resources/abilities"

## Phase 3+8 pinned ability ids.
const EXPECTED_ABILITY_IDS: Array = [
	&"ferro_pull",
	&"ferro_push",
	&"lumen_bloom",
	&"shape_burst",
	&"skyward",
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


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


## Load a single ability .tres by stem and assert it is a valid AbilityDef.
func _load_ability(stem: String) -> AbilityDef:
	var res := ResourceLoader.load(ABILITIES_DIR + "/" + stem + ".tres")
	assert_not_null(res, "%s.tres must load" % stem)
	assert_true(res is AbilityDef, "%s.tres must be AbilityDef" % stem)
	return res


# ---------------------------------------------------------------------------
# Structural tests
# ---------------------------------------------------------------------------


func test_all_expected_ability_ids_are_present() -> void:
	var abilities := _load_dir(ABILITIES_DIR)
	var loaded_ids: Array = []
	for ab in abilities:
		if ab is AbilityDef:
			loaded_ids.append(ab.id)
	for expected_id in EXPECTED_ABILITY_IDS:
		assert_true(
			loaded_ids.has(expected_id),
			"Expected ability id %s to be present in resources/abilities/" % expected_id
		)


func test_ability_defs_have_correct_script_class() -> void:
	var abilities := _load_dir(ABILITIES_DIR)
	assert_true(abilities.size() > 0, "Should load at least one ability resource")
	for ab in abilities:
		assert_true(
			ab is AbilityDef,
			"All resources in resources/abilities/ must be AbilityDef, got: %s" % str(ab)
		)


func test_ability_ids_are_unique() -> void:
	var abilities := _load_dir(ABILITIES_DIR)
	var seen_ids: Array = []
	for ab in abilities:
		if ab is AbilityDef:
			assert_false(seen_ids.has(ab.id), "Duplicate ability id found: %s" % ab.id)
			seen_ids.append(ab.id)


func test_ability_ids_are_non_empty() -> void:
	var abilities := _load_dir(ABILITIES_DIR)
	for ab in abilities:
		if ab is AbilityDef:
			assert_true(ab.id != &"", "AbilityDef display_name='%s' has empty id" % ab.display_name)


func test_ability_display_names_are_non_empty() -> void:
	var abilities := _load_dir(ABILITIES_DIR)
	for ab in abilities:
		if ab is AbilityDef:
			assert_true(ab.display_name != "", "AbilityDef id='%s' has empty display_name" % ab.id)


func test_ability_kinds_are_non_empty() -> void:
	var abilities := _load_dir(ABILITIES_DIR)
	for ab in abilities:
		if ab is AbilityDef:
			assert_true(ab.kind != &"", "AbilityDef id='%s' has empty kind" % ab.id)


func test_ability_lumen_costs_are_positive() -> void:
	var abilities := _load_dir(ABILITIES_DIR)
	for ab in abilities:
		if ab is AbilityDef:
			assert_true(ab.lumen_cost > 0.0, "AbilityDef id='%s' lumen_cost must be > 0" % ab.id)


func test_ability_cooldowns_are_positive() -> void:
	var abilities := _load_dir(ABILITIES_DIR)
	for ab in abilities:
		if ab is AbilityDef:
			assert_true(
				ab.cooldown_ticks > 0, "AbilityDef id='%s' cooldown_ticks must be > 0" % ab.id
			)


func test_ability_swatch_colors_are_distinct() -> void:
	var abilities := _load_dir(ABILITIES_DIR)
	var colors: Array = []
	for ab in abilities:
		if ab is AbilityDef:
			var key := Vector3(
				snappedf(ab.swatch_color.r, 0.01),
				snappedf(ab.swatch_color.g, 0.01),
				snappedf(ab.swatch_color.b, 0.01)
			)
			assert_false(
				colors.has(key), "Duplicate swatch_color detected for ability id='%s'" % ab.id
			)
			colors.append(key)


# ---------------------------------------------------------------------------
# Pinned per-ability contract checks (all three in one test to stay under
# the 20-public-method linter ceiling for this file).
# ---------------------------------------------------------------------------


func test_individual_abilities_match_pinned_spec() -> void:
	# shape_burst
	var ab := _load_ability("shape_burst")
	assert_eq(ab.id, &"shape_burst")
	assert_eq(ab.kind, &"shape_burst")
	assert_eq(ab.lumen_cost, 25.0)
	assert_eq(ab.cooldown_ticks, 30)
	assert_eq(ab.magnitude, 4.0)
	# Electric blue: blue channel dominant over red and green.
	assert_true(ab.swatch_color.b > ab.swatch_color.r, "shape_burst swatch should be blue-dominant")
	assert_true(
		ab.swatch_color.b > ab.swatch_color.g,
		"shape_burst swatch should be blue-dominant over green"
	)

	# lumen_bloom
	ab = _load_ability("lumen_bloom")
	assert_eq(ab.id, &"lumen_bloom")
	assert_eq(ab.kind, &"lumen_bloom")
	assert_eq(ab.lumen_cost, 15.0)
	assert_eq(ab.cooldown_ticks, 20)
	assert_eq(ab.magnitude, 6.0)
	# Magenta: red and blue both dominant, green low.
	assert_true(ab.swatch_color.r > 0.5, "lumen_bloom swatch should be magenta (red channel)")
	assert_true(ab.swatch_color.b > 0.5, "lumen_bloom swatch should be magenta (blue channel)")
	assert_true(ab.swatch_color.g < 0.4, "lumen_bloom swatch should be magenta (low green)")

	# skyward
	ab = _load_ability("skyward")
	assert_eq(ab.id, &"skyward")
	assert_eq(ab.kind, &"skyward")
	assert_eq(ab.lumen_cost, 10.0)
	assert_eq(ab.cooldown_ticks, 15)
	assert_eq(ab.magnitude, 14.0)
	# Cyan: green and blue both dominant, red low.
	assert_true(ab.swatch_color.g > 0.5, "skyward swatch should be cyan (green channel)")
	assert_true(ab.swatch_color.b > 0.5, "skyward swatch should be cyan (blue channel)")
	assert_true(ab.swatch_color.r < 0.3, "skyward swatch should be cyan (low red)")

	# ferro_pull
	ab = _load_ability("ferro_pull")
	assert_eq(ab.id, &"ferro_pull")
	assert_eq(ab.kind, &"ferro_pull")
	assert_eq(ab.resource_kind, &"iron")
	assert_eq(ab.lumen_cost, 12.0)
	assert_eq(ab.cooldown_ticks, 8)
	assert_eq(ab.magnitude, 9.0)
	# Steel-blue: blue dominant over red.
	assert_true(ab.swatch_color.b > ab.swatch_color.r, "ferro_pull swatch should be blue-dominant")

	# ferro_push
	ab = _load_ability("ferro_push")
	assert_eq(ab.id, &"ferro_push")
	assert_eq(ab.kind, &"ferro_push")
	assert_eq(ab.resource_kind, &"steel")
	assert_eq(ab.lumen_cost, 12.0)
	assert_eq(ab.cooldown_ticks, 8)
	assert_eq(ab.magnitude, 11.0)
	# Silver: all channels high, relatively balanced.
	assert_true(ab.swatch_color.r > 0.5, "ferro_push swatch should be silver (high red)")
	assert_true(ab.swatch_color.g > 0.5, "ferro_push swatch should be silver (high green)")
