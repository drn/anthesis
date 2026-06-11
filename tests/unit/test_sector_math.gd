extends GutTest

## Verifies [SectorMath.step_for_offset] (Phase 6 contract #2): north (toward -Z)
## is step 0, the sweep is clockwise (east = +X is a quarter turn = step 4 of
## 16), sector boundaries snap deterministically under a small epsilon either
## side, and a full circular sweep hits every one of the 16 sectors. Y is ignored
## throughout. Expected indices are derived by hand from the contract, not from
## the implementation.

const STEPS := 16
# Each sector spans TAU/16 radians; a tiny nudge well inside a sector.
const SECTOR := TAU / STEPS

# ---------------------------------------------------------------------------
# Cardinals
# ---------------------------------------------------------------------------


func test_north_is_step_zero() -> void:
	# Due north = toward -Z.
	assert_eq(SectorMath.step_for_offset(Vector3(0, 0, -1)), 0, "north (-Z) is step 0")


func test_east_is_quarter() -> void:
	# East = +X, a quarter of the clockwise sweep = step 4 of 16.
	assert_eq(SectorMath.step_for_offset(Vector3(1, 0, 0)), 4, "east (+X) is step 4")


func test_south_is_half() -> void:
	# South = +Z, half way around = step 8.
	assert_eq(SectorMath.step_for_offset(Vector3(0, 0, 1)), 8, "south (+Z) is step 8")


func test_west_is_three_quarters() -> void:
	# West = -X, three quarters around = step 12.
	assert_eq(SectorMath.step_for_offset(Vector3(-1, 0, 0)), 12, "west (-X) is step 12")


func test_y_component_ignored() -> void:
	assert_eq(
		SectorMath.step_for_offset(Vector3(1, 50.0, 0)),
		SectorMath.step_for_offset(Vector3(1, -7.0, 0)),
		"Y must not affect the sector",
	)


func test_distance_does_not_matter() -> void:
	# Only the angle matters, not the radius.
	assert_eq(
		SectorMath.step_for_offset(Vector3(0, 0, -0.01)),
		SectorMath.step_for_offset(Vector3(0, 0, -500.0)),
		"radius along the same bearing maps to the same step",
	)


# ---------------------------------------------------------------------------
# Diagonals (clockwise ascending from north)
# ---------------------------------------------------------------------------


func test_diagonals_clockwise() -> void:
	# North-east bisects north(0) and east(4) -> step 2.
	assert_eq(SectorMath.step_for_offset(Vector3(1, 0, -1)), 2, "NE is step 2")
	# South-east bisects east(4) and south(8) -> step 6.
	assert_eq(SectorMath.step_for_offset(Vector3(1, 0, 1)), 6, "SE is step 6")
	# South-west -> step 10.
	assert_eq(SectorMath.step_for_offset(Vector3(-1, 0, 1)), 10, "SW is step 10")
	# North-west -> step 14.
	assert_eq(SectorMath.step_for_offset(Vector3(-1, 0, -1)), 14, "NW is step 14")


# ---------------------------------------------------------------------------
# Sector boundaries (+/- epsilon snap deterministically)
# ---------------------------------------------------------------------------


func _offset_at_angle(angle: float, radius := 1.0) -> Vector3:
	# Inverse of the mapping: angle measured as atan2(x, -z), clockwise from -Z.
	return Vector3(sin(angle) * radius, 0.0, -cos(angle) * radius)


func test_each_sector_center_maps_to_its_step() -> void:
	# The centre of sector i is at angle i*SECTOR; it must map to step i.
	for i in STEPS:
		var off := _offset_at_angle(i * SECTOR)
		assert_eq(SectorMath.step_for_offset(off), i, "sector centre %d -> step %d" % [i, i])


func test_boundary_epsilon_either_side() -> void:
	# A boundary sits halfway between sector i and i+1, at (i+0.5)*SECTOR.
	# Just below resolves to i, just above to i+1.
	var eps := SECTOR * 0.02
	for i in STEPS:
		var boundary := (i + 0.5) * SECTOR
		var below := SectorMath.step_for_offset(_offset_at_angle(boundary - eps))
		var above := SectorMath.step_for_offset(_offset_at_angle(boundary + eps))
		assert_eq(below, i, "just below boundary %d stays %d" % [i, i])
		assert_eq(
			above, (i + 1) % STEPS, "just above boundary %d goes to %d" % [i, (i + 1) % STEPS]
		)


func test_boundary_is_stable_not_oscillating() -> void:
	# Exactly on a boundary must resolve to a single deterministic step (no NaN /
	# out-of-range), and calling twice gives the same answer.
	for i in STEPS:
		var boundary := (i + 0.5) * SECTOR
		var off := _offset_at_angle(boundary)
		var a := SectorMath.step_for_offset(off)
		var b := SectorMath.step_for_offset(off)
		assert_eq(a, b, "on-boundary result is deterministic")
		assert_true(a >= 0 and a < STEPS, "on-boundary result in range")


# ---------------------------------------------------------------------------
# Full sweep hits every sector; always in range
# ---------------------------------------------------------------------------


func test_full_circle_hits_all_sixteen() -> void:
	var seen := {}
	# Sample densely around the circle.
	for k in range(720):
		var angle := TAU * float(k) / 720.0
		var step := SectorMath.step_for_offset(_offset_at_angle(angle))
		assert_true(step >= 0 and step < STEPS, "sweep step in range at k=%d" % k)
		seen[step] = true
	assert_eq(seen.size(), STEPS, "a full sweep must touch all 16 sectors")


func test_zero_offset_in_range() -> void:
	# Degenerate offset (block exactly on the core) must not crash or escape range.
	var step := SectorMath.step_for_offset(Vector3.ZERO)
	assert_true(step >= 0 and step < STEPS, "zero offset yields a valid step")


func test_custom_step_count() -> void:
	# Mapping respects a non-default step count.
	assert_eq(SectorMath.step_for_offset(Vector3(0, 0, -1), 8), 0, "north with 8 steps is 0")
	assert_eq(SectorMath.step_for_offset(Vector3(1, 0, 0), 8), 2, "east with 8 steps is 2")
