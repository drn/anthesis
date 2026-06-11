extends GutTest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _make_rng(seed_val: int, stream: String) -> RandomNumberGenerator:
	return WorldSeed.new(seed_val).derive(stream)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


## Same rng seed and stream produces identical placements.
func test_same_seed_same_stream_identical() -> void:
	var rng_a := _make_rng(42, "flora")
	var rng_b := _make_rng(42, "flora")
	var a := FloraScatter.compute_placements(rng_a, 20, 50.0)
	var b := FloraScatter.compute_placements(rng_b, 20, 50.0)
	assert_eq(a.size(), b.size(), "Arrays must have same size")
	for i in range(a.size()):
		assert_true(a[i].origin.is_equal_approx(b[i].origin), "Origin %d must match" % i)
		assert_true(a[i].basis.is_equal_approx(b[i].basis), "Basis %d must match" % i)


## Different streams yield different placements (at least one origin differs).
func test_different_streams_different_placements() -> void:
	var rng_a := _make_rng(42, "flora")
	var rng_b := _make_rng(42, "flora_alt")
	var a := FloraScatter.compute_placements(rng_a, 20, 50.0)
	var b := FloraScatter.compute_placements(rng_b, 20, 50.0)
	var all_same := true
	for i in range(a.size()):
		if not a[i].origin.is_equal_approx(b[i].origin):
			all_same = false
			break
	assert_false(all_same, "Different streams must produce at least one differing origin")


## Returned array length equals count parameter.
func test_count_respected() -> void:
	var rng := _make_rng(7, "flora")
	var result := FloraScatter.compute_placements(rng, 33, 40.0)
	assert_eq(result.size(), 33, "Result must contain exactly count entries")


## All positions stay within [-area_extent, +area_extent] on X and Z.
func test_positions_within_area_extent() -> void:
	var extent := 30.0
	var rng := _make_rng(99, "flora")
	var placements := FloraScatter.compute_placements(rng, 50, extent)
	for i in range(placements.size()):
		var pos := placements[i].origin
		assert_true(
			pos.x >= -extent and pos.x <= extent, "X at index %d out of range: %f" % [i, pos.x]
		)
		assert_true(
			pos.z >= -extent and pos.z <= extent, "Z at index %d out of range: %f" % [i, pos.z]
		)


## Y is always 0 from compute_placements (height adjustment is caller's job).
func test_y_is_zero() -> void:
	var rng := _make_rng(13, "flora")
	var placements := FloraScatter.compute_placements(rng, 10, 20.0)
	for i in range(placements.size()):
		assert_eq(
			placements[i].origin.y, 0.0, "Y at index %d must be 0.0 before height adjustment" % i
		)


## Scale jitter is within [0.7, 1.4] on all axes.
func test_scale_jitter_in_range() -> void:
	var rng := _make_rng(55, "flora")
	var placements := FloraScatter.compute_placements(rng, 40, 50.0)
	for i in range(placements.size()):
		var s := placements[i].basis.get_scale()
		assert_true(
			s.x >= 0.69 and s.x <= 1.41, "Scale X at index %d out of [0.7,1.4]: %f" % [i, s.x]
		)
		assert_true(
			s.y >= 0.69 and s.y <= 1.41, "Scale Y at index %d out of [0.7,1.4]: %f" % [i, s.y]
		)
		assert_true(
			s.z >= 0.69 and s.z <= 1.41, "Scale Z at index %d out of [0.7,1.4]: %f" % [i, s.z]
		)
