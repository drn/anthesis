## Tests CreatureRegistry scanning, sorting, and lookup behaviour.
##
## Validates: scanning the real resources/creatures dir finds all 2 Phase 4
## creatures sorted by id; a missing dir yields an empty registry; creature()
## lookup returns the correct def or null.
extends GutTest

# ---------------------------------------------------------------------------
# Pinned Phase 4 creature ids in expected sorted (alphabetical) order.
# ---------------------------------------------------------------------------

const EXPECTED_CREATURE_IDS_SORTED: Array = [
	&"shardling",
	&"voidmoth",
]

# ---------------------------------------------------------------------------
# Real-directory tests
# ---------------------------------------------------------------------------


func test_scans_all_expected_creatures() -> void:
	var reg := CreatureRegistry.new()  # default res://resources/creatures
	var ids := reg.creature_ids()
	for expected in EXPECTED_CREATURE_IDS_SORTED:
		assert_true(ids.has(expected), "Registry must contain creature id '%s'" % expected)


func test_finds_exactly_two_creatures() -> void:
	var reg := CreatureRegistry.new()
	assert_eq(reg.creature_ids().size(), 2, "Registry must contain exactly 2 Phase 4 creatures")


func test_creatures_sorted_by_id() -> void:
	var reg := CreatureRegistry.new()
	var ids := reg.creature_ids()
	assert_true(ids.size() >= 2, "Registry must have at least 2 creatures")
	for i in range(ids.size() - 1):
		assert_true(
			str(ids[i]) <= str(ids[i + 1]),
			"creature_ids() must be sorted: '%s' should not come before '%s'" % [ids[i + 1], ids[i]]
		)


func test_creatures_array_order_matches_ids() -> void:
	var reg := CreatureRegistry.new()
	var defs := reg.creatures()
	var ids := reg.creature_ids()
	assert_eq(defs.size(), ids.size(), "creatures() and creature_ids() must have same length")
	for i in range(defs.size()):
		assert_eq(defs[i].id, ids[i], "creatures()[%d].id must match creature_ids()[%d]" % [i, i])


func test_creatures_resolve_to_creaturedef() -> void:
	var reg := CreatureRegistry.new()
	for expected in EXPECTED_CREATURE_IDS_SORTED:
		var def := reg.creature(expected)
		assert_not_null(def, "creature('%s') must resolve" % expected)
		if def != null:
			assert_eq(def.id, expected, "CreatureDef.id must match its lookup key")


func test_sorted_order_is_shardling_then_voidmoth() -> void:
	var reg := CreatureRegistry.new()
	var ids := reg.creature_ids()
	assert_true(ids.size() >= 2, "Registry must have at least 2 creatures")
	assert_eq(ids[0], &"shardling", "First sorted creature must be shardling")
	assert_eq(ids[1], &"voidmoth", "Second sorted creature must be voidmoth")


# ---------------------------------------------------------------------------
# Defensive behaviour
# ---------------------------------------------------------------------------


func test_missing_dir_yields_empty_registry() -> void:
	var reg := CreatureRegistry.new("res://__no_such_creatures__")
	assert_eq(reg.creature_ids().size(), 0, "Missing dir => no creatures")
	assert_eq(reg.creatures().size(), 0, "Missing dir => empty creatures array")
	assert_null(reg.creature(&"voidmoth"), "Unknown creature => null")


func test_unknown_id_returns_null() -> void:
	var reg := CreatureRegistry.new()
	assert_null(reg.creature(&"not_a_real_creature"), "Unknown creature id => null")
