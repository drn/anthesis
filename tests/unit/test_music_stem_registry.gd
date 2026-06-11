## Tests MusicStemRegistry scanning, sorting, and lookup behaviour.
##
## Validates: scanning the real resources/music dir finds all 5 Phase 5
## stems sorted by id; a missing dir yields an empty registry; stem()
## lookup returns the correct def or null.
extends GutTest

# ---------------------------------------------------------------------------
# Pinned Phase 5 stem ids in expected sorted (alphabetical) order.
# ---------------------------------------------------------------------------

const EXPECTED_STEM_IDS_SORTED: Array = [
	&"arp",
	&"bass",
	&"drums",
	&"pad",
	&"shimmer",
]

# ---------------------------------------------------------------------------
# Real-directory tests
# ---------------------------------------------------------------------------


func test_scans_all_expected_stems() -> void:
	var reg := MusicStemRegistry.new()  # default res://resources/music
	var ids := reg.stem_ids()
	for expected in EXPECTED_STEM_IDS_SORTED:
		assert_true(ids.has(expected), "Registry must contain stem id '%s'" % expected)


func test_finds_exactly_five_stems() -> void:
	var reg := MusicStemRegistry.new()
	assert_eq(reg.stem_ids().size(), 5, "Registry must have exactly 5 stems")


func test_stems_sorted_by_id() -> void:
	var reg := MusicStemRegistry.new()
	var ids := reg.stem_ids()
	assert_true(ids.size() >= 5, "Registry must have at least 5 stems")
	for i in range(ids.size() - 1):
		assert_true(
			str(ids[i]) <= str(ids[i + 1]),
			"stem_ids() must be sorted: '%s' should not come before '%s'" % [ids[i + 1], ids[i]]
		)


func test_stems_array_order_matches_ids() -> void:
	var reg := MusicStemRegistry.new()
	var defs := reg.stems()
	var ids := reg.stem_ids()
	assert_eq(defs.size(), ids.size(), "stems() and stem_ids() must have same length")
	for i in range(defs.size()):
		assert_eq(defs[i].id, ids[i], "stems()[%d].id must match stem_ids()[%d]" % [i, i])


func test_stems_resolve_to_musicstemdef() -> void:
	var reg := MusicStemRegistry.new()
	for expected in EXPECTED_STEM_IDS_SORTED:
		var def := reg.stem(expected)
		assert_not_null(def, "stem('%s') must resolve" % expected)
		if def != null:
			assert_eq(def.id, expected, "MusicStemDef.id must match its lookup key")


func test_stem_lookup_returns_correct_stream_path() -> void:
	var reg := MusicStemRegistry.new()
	# Spot-check stream_path wires through the registry for each stem.
	for expected in EXPECTED_STEM_IDS_SORTED:
		var def := reg.stem(expected)
		assert_not_null(def, "stem('%s') must resolve" % expected)
		if def != null:
			var expected_path := "res://assets/audio/music/" + str(expected) + ".wav"
			assert_eq(
				def.stream_path,
				expected_path,
				"stem('%s').stream_path must be '%s'" % [expected, expected_path]
			)


# ---------------------------------------------------------------------------
# Defensive behaviour
# ---------------------------------------------------------------------------


func test_missing_dir_yields_empty_registry() -> void:
	var reg := MusicStemRegistry.new("res://__no_such_music__")
	assert_eq(reg.stem_ids().size(), 0, "Missing dir => no stems")
	assert_eq(reg.stems().size(), 0, "Missing dir => empty stems array")
	assert_null(reg.stem(&"pad"), "Unknown stem => null")


func test_unknown_id_returns_null() -> void:
	var reg := MusicStemRegistry.new()
	assert_null(reg.stem(&"not_a_real_stem"), "Unknown stem id => null")
