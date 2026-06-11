## Tests AbilityRegistry scanning, sorting, and lookup behaviour.
##
## Validates: scanning the real resources/abilities dir finds all 3 Phase 3
## abilities sorted by id; a missing dir yields an empty registry; ability()
## lookup returns the correct def or null.
extends GutTest

# ---------------------------------------------------------------------------
# Pinned Phase 3 ability ids in expected sorted (alphabetical) order.
# ---------------------------------------------------------------------------

const EXPECTED_ABILITY_IDS_SORTED: Array = [
	&"lumen_bloom",
	&"shape_burst",
	&"skyward",
]

# ---------------------------------------------------------------------------
# Real-directory tests
# ---------------------------------------------------------------------------


func test_scans_all_expected_abilities() -> void:
	var reg := AbilityRegistry.new()  # default res://resources/abilities
	var ids := reg.ability_ids()
	for expected in EXPECTED_ABILITY_IDS_SORTED:
		assert_true(ids.has(expected), "Registry must contain ability id '%s'" % expected)


func test_abilities_sorted_by_id() -> void:
	var reg := AbilityRegistry.new()
	var ids := reg.ability_ids()
	# Must contain at least the 3 pinned ids in sorted order.
	assert_true(ids.size() >= 3, "Registry must have at least 3 abilities")
	for i in range(ids.size() - 1):
		assert_true(
			str(ids[i]) <= str(ids[i + 1]),
			"ability_ids() must be sorted: '%s' should not come before '%s'" % [ids[i + 1], ids[i]]
		)


func test_abilities_array_order_matches_ids() -> void:
	var reg := AbilityRegistry.new()
	var defs := reg.abilities()
	var ids := reg.ability_ids()
	assert_eq(defs.size(), ids.size(), "abilities() and ability_ids() must have same length")
	for i in range(defs.size()):
		assert_eq(defs[i].id, ids[i], "abilities()[%d].id must match ability_ids()[%d]" % [i, i])


func test_abilities_resolve_to_abilitydef() -> void:
	var reg := AbilityRegistry.new()
	for expected in EXPECTED_ABILITY_IDS_SORTED:
		var def := reg.ability(expected)
		assert_not_null(def, "ability('%s') must resolve" % expected)
		if def != null:
			assert_eq(def.id, expected, "AbilityDef.id must match its lookup key")


func test_ability_lookup_returns_correct_kind() -> void:
	var reg := AbilityRegistry.new()
	# Spot-check the kind field wires through the registry.
	var ab := reg.ability(&"shape_burst")
	assert_not_null(ab, "shape_burst must exist")
	if ab != null:
		assert_eq(ab.kind, &"shape_burst")

	ab = reg.ability(&"lumen_bloom")
	assert_not_null(ab, "lumen_bloom must exist")
	if ab != null:
		assert_eq(ab.kind, &"lumen_bloom")

	ab = reg.ability(&"skyward")
	assert_not_null(ab, "skyward must exist")
	if ab != null:
		assert_eq(ab.kind, &"skyward")


# ---------------------------------------------------------------------------
# Defensive behaviour
# ---------------------------------------------------------------------------


func test_missing_dir_yields_empty_registry() -> void:
	var reg := AbilityRegistry.new("res://__no_such_abilities__")
	assert_eq(reg.ability_ids().size(), 0, "Missing dir => no abilities")
	assert_eq(reg.abilities().size(), 0, "Missing dir => empty abilities array")
	assert_null(reg.ability(&"shape_burst"), "Unknown ability => null")


func test_unknown_id_returns_null() -> void:
	var reg := AbilityRegistry.new()
	assert_null(reg.ability(&"not_a_real_ability"), "Unknown ability id => null")
