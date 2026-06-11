## Tests that all creature .tres resources load correctly and satisfy
## the Phase 4 data contracts.
##
## Validates: script_class types, id uniqueness, pinned ids, and exact
## stat values for Voidmoth and Shardling including drop items and counts.
extends GutTest

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const CREATURES_DIR := "res://resources/creatures"

## Phase 4 pinned creature ids.
const EXPECTED_CREATURE_IDS: Array = [
	&"shardling",
	&"voidmoth",
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


## Load a single creature .tres by stem and assert it is a valid CreatureDef.
func _load_creature(stem: String) -> CreatureDef:
	var res := ResourceLoader.load(CREATURES_DIR + "/" + stem + ".tres")
	assert_not_null(res, "%s.tres must load" % stem)
	assert_true(res is CreatureDef, "%s.tres must be CreatureDef" % stem)
	return res


# ---------------------------------------------------------------------------
# Structural tests
# ---------------------------------------------------------------------------


func test_all_expected_creature_ids_are_present() -> void:
	var creatures := _load_dir(CREATURES_DIR)
	var loaded_ids: Array = []
	for cr in creatures:
		if cr is CreatureDef:
			loaded_ids.append(cr.id)
	for expected_id in EXPECTED_CREATURE_IDS:
		assert_true(
			loaded_ids.has(expected_id),
			"Expected creature id %s to be present in resources/creatures/" % expected_id
		)


func test_creature_defs_have_correct_script_class() -> void:
	var creatures := _load_dir(CREATURES_DIR)
	assert_true(creatures.size() > 0, "Should load at least one creature resource")
	for cr in creatures:
		assert_true(
			cr is CreatureDef,
			"All resources in resources/creatures/ must be CreatureDef, got: %s" % str(cr)
		)


func test_creature_ids_are_unique() -> void:
	var creatures := _load_dir(CREATURES_DIR)
	var seen_ids: Array = []
	for cr in creatures:
		if cr is CreatureDef:
			assert_false(seen_ids.has(cr.id), "Duplicate creature id found: %s" % cr.id)
			seen_ids.append(cr.id)


func test_creature_ids_are_non_empty() -> void:
	var creatures := _load_dir(CREATURES_DIR)
	for cr in creatures:
		if cr is CreatureDef:
			assert_true(
				cr.id != &"", "CreatureDef display_name='%s' has empty id" % cr.display_name
			)


func test_creature_display_names_are_non_empty() -> void:
	var creatures := _load_dir(CREATURES_DIR)
	for cr in creatures:
		if cr is CreatureDef:
			assert_true(cr.display_name != "", "CreatureDef id='%s' has empty display_name" % cr.id)


# ---------------------------------------------------------------------------
# Pinned per-creature contract checks — all stats exact per Phase 4 spec.
# ---------------------------------------------------------------------------


func test_voidmoth_matches_pinned_spec() -> void:
	var cr := _load_creature("voidmoth")
	if cr == null:
		return
	assert_eq(cr.id, &"voidmoth")
	assert_eq(cr.display_name, "Voidmoth")
	assert_eq(cr.max_health, 12.0)
	assert_eq(cr.move_speed, 3.2)
	assert_eq(cr.attack_damage, 4.0)
	assert_eq(cr.attack_range, 1.6)
	assert_eq(cr.aggro_range, 14.0)
	assert_eq(cr.attack_cooldown_ticks, 12)
	assert_eq(cr.lumen_reward, 4.0)
	assert_eq(cr.body_scale, 0.8)
	# Violet core: red and blue dominant, green low.
	assert_eq(cr.core_color, Color(0.7, 0.3, 1.0, 1.0))
	# Drops: glow_spore x1.
	assert_eq(cr.drops.size(), 1, "Voidmoth must have exactly 1 drop entry")
	if cr.drops.size() >= 1:
		assert_eq(cr.drops[0].item_id, &"glow_spore")
		assert_eq(cr.drops[0].count, 1)


func test_shardling_matches_pinned_spec() -> void:
	var cr := _load_creature("shardling")
	if cr == null:
		return
	assert_eq(cr.id, &"shardling")
	assert_eq(cr.display_name, "Shardling")
	assert_eq(cr.max_health, 30.0)
	assert_eq(cr.move_speed, 2.4)
	assert_eq(cr.attack_damage, 9.0)
	assert_eq(cr.attack_range, 1.9)
	assert_eq(cr.aggro_range, 11.0)
	assert_eq(cr.attack_cooldown_ticks, 18)
	assert_eq(cr.lumen_reward, 8.0)
	assert_eq(cr.body_scale, 1.15)
	# Icy blue core: blue dominant, green mid, red low.
	assert_eq(cr.core_color, Color(0.3, 0.7, 1.0, 1.0))
	# Drops: crystal_shard x2.
	assert_eq(cr.drops.size(), 1, "Shardling must have exactly 1 drop entry")
	if cr.drops.size() >= 1:
		assert_eq(cr.drops[0].item_id, &"crystal_shard")
		assert_eq(cr.drops[0].count, 2)
