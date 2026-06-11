## Tests that all music stem .tres resources load correctly and satisfy
## the Phase 5 data contracts.
##
## Validates: script_class types, id uniqueness, pinned thresholds/full_at/base_db,
## stream_path formats, and that exactly one stem is always_on.
extends GutTest

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const STEMS_DIR := "res://resources/music"

## Phase 5 pinned stem ids.
const EXPECTED_STEM_IDS: Array = [
	&"arp",
	&"bass",
	&"drums",
	&"pad",
	&"shimmer",
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


## Load a single stem .tres by stem id and assert it is a valid MusicStemDef.
func _load_stem(id: String) -> MusicStemDef:
	var res := ResourceLoader.load(STEMS_DIR + "/" + id + ".tres")
	assert_not_null(res, "%s.tres must load" % id)
	assert_true(res is MusicStemDef, "%s.tres must be MusicStemDef" % id)
	return res


# ---------------------------------------------------------------------------
# Structural tests
# ---------------------------------------------------------------------------


func test_all_expected_stem_ids_are_present() -> void:
	var stems := _load_dir(STEMS_DIR)
	var loaded_ids: Array = []
	for s in stems:
		if s is MusicStemDef:
			loaded_ids.append(s.id)
	for expected_id in EXPECTED_STEM_IDS:
		assert_true(
			loaded_ids.has(expected_id),
			"Expected stem id %s to be present in resources/music/" % expected_id
		)


func test_stem_defs_have_correct_script_class() -> void:
	var stems := _load_dir(STEMS_DIR)
	assert_true(stems.size() > 0, "Should load at least one stem resource")
	for s in stems:
		assert_true(
			s is MusicStemDef,
			"All resources in resources/music/ must be MusicStemDef, got: %s" % str(s)
		)


func test_stem_ids_are_unique() -> void:
	var stems := _load_dir(STEMS_DIR)
	var seen_ids: Array = []
	for s in stems:
		if s is MusicStemDef:
			assert_false(seen_ids.has(s.id), "Duplicate stem id found: %s" % s.id)
			seen_ids.append(s.id)


func test_stem_ids_are_non_empty() -> void:
	var stems := _load_dir(STEMS_DIR)
	for s in stems:
		if s is MusicStemDef:
			assert_true(s.id != &"", "MusicStemDef stream_path='%s' has empty id" % s.stream_path)


func test_stream_paths_point_at_music_wav() -> void:
	var stems := _load_dir(STEMS_DIR)
	for s in stems:
		if s is MusicStemDef:
			assert_true(
				s.stream_path.begins_with("res://assets/audio/music/"),
				"MusicStemDef id='%s' stream_path must be under res://assets/audio/music/" % s.id
			)
			assert_true(
				s.stream_path.ends_with(".wav"),
				"MusicStemDef id='%s' stream_path must end with .wav" % s.id
			)
			# Stream path filename stem must match the resource id.
			var expected_path := "res://assets/audio/music/" + str(s.id) + ".wav"
			assert_eq(
				s.stream_path,
				expected_path,
				"MusicStemDef id='%s' stream_path must be '%s'" % [s.id, expected_path]
			)


func test_exactly_one_always_on_stem() -> void:
	var stems := _load_dir(STEMS_DIR)
	var always_on_count := 0
	for s in stems:
		if s is MusicStemDef and s.always_on:
			always_on_count += 1
	assert_eq(always_on_count, 1, "Exactly one stem must have always_on = true")


func test_always_on_stem_is_pad() -> void:
	var pad := _load_stem("pad")
	if pad != null:
		assert_true(pad.always_on, "pad stem must have always_on = true")


func test_non_always_on_stems_have_valid_thresholds() -> void:
	var stems := _load_dir(STEMS_DIR)
	for s in stems:
		if s is MusicStemDef and not s.always_on:
			assert_true(
				s.threshold >= 0.0 and s.threshold <= 1.0,
				"MusicStemDef id='%s' threshold must be in [0..1]" % s.id
			)
			assert_true(
				s.full_at >= s.threshold, "MusicStemDef id='%s' full_at must be >= threshold" % s.id
			)
			assert_true(s.full_at <= 1.0, "MusicStemDef id='%s' full_at must be <= 1.0" % s.id)


# ---------------------------------------------------------------------------
# Pinned per-stem contract checks (all five in one test to stay under
# the 20-public-method linter ceiling for this file).
# ---------------------------------------------------------------------------


func test_individual_stems_match_pinned_spec() -> void:
	# pad: always_on, base -8
	var s := _load_stem("pad")
	assert_eq(s.id, &"pad")
	assert_eq(s.stream_path, "res://assets/audio/music/pad.wav")
	assert_true(s.always_on, "pad must have always_on = true")
	assert_eq(s.base_db, -8.0)

	# arp: threshold 0.10, full 0.30, base -9
	s = _load_stem("arp")
	assert_eq(s.id, &"arp")
	assert_eq(s.stream_path, "res://assets/audio/music/arp.wav")
	assert_false(s.always_on, "arp must have always_on = false")
	assert_eq(s.threshold, 0.1)
	assert_eq(s.full_at, 0.3)
	assert_eq(s.base_db, -9.0)

	# bass: threshold 0.30, full 0.50, base -6
	s = _load_stem("bass")
	assert_eq(s.id, &"bass")
	assert_eq(s.stream_path, "res://assets/audio/music/bass.wav")
	assert_false(s.always_on, "bass must have always_on = false")
	assert_eq(s.threshold, 0.3)
	assert_eq(s.full_at, 0.5)
	assert_eq(s.base_db, -6.0)

	# drums: threshold 0.50, full 0.70, base -5
	s = _load_stem("drums")
	assert_eq(s.id, &"drums")
	assert_eq(s.stream_path, "res://assets/audio/music/drums.wav")
	assert_false(s.always_on, "drums must have always_on = false")
	assert_eq(s.threshold, 0.5)
	assert_eq(s.full_at, 0.7)
	assert_eq(s.base_db, -5.0)

	# shimmer: threshold 0.70, full 0.90, base -10
	s = _load_stem("shimmer")
	assert_eq(s.id, &"shimmer")
	assert_eq(s.stream_path, "res://assets/audio/music/shimmer.wav")
	assert_false(s.always_on, "shimmer must have always_on = false")
	assert_eq(s.threshold, 0.7)
	assert_eq(s.full_at, 0.9)
	assert_eq(s.base_db, -10.0)
