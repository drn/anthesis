extends GutTest

## Exercises [LashMath.snap_axis]: every signed cardinal axis, the dominant
## component winning a mixed vector, the near-zero fallback to DOWN, and tie
## precedence (Y over X/Z, X over Z).


func test_pure_axes_snap_to_themselves() -> void:
	assert_eq(LashMath.snap_axis(Vector3.UP), Vector3.UP)
	assert_eq(LashMath.snap_axis(Vector3.DOWN), Vector3.DOWN)
	assert_eq(LashMath.snap_axis(Vector3.LEFT), Vector3.LEFT)
	assert_eq(LashMath.snap_axis(Vector3.RIGHT), Vector3.RIGHT)
	assert_eq(LashMath.snap_axis(Vector3.FORWARD), Vector3.FORWARD)
	assert_eq(LashMath.snap_axis(Vector3.BACK), Vector3.BACK)


func test_dominant_up_component_wins() -> void:
	assert_eq(LashMath.snap_axis(Vector3(0.2, 0.7, -0.1)), Vector3.UP)


func test_dominant_down_component_wins() -> void:
	assert_eq(LashMath.snap_axis(Vector3(0.1, -0.9, 0.3)), Vector3.DOWN)


func test_dominant_horizontal_component_wins() -> void:
	assert_eq(LashMath.snap_axis(Vector3(-0.8, 0.3, 0.2)), Vector3.LEFT)
	assert_eq(LashMath.snap_axis(Vector3(0.1, 0.2, 0.9)), Vector3.BACK)
	assert_eq(LashMath.snap_axis(Vector3(0.1, 0.2, -0.9)), Vector3.FORWARD)


func test_zero_input_falls_back_to_down() -> void:
	assert_eq(LashMath.snap_axis(Vector3.ZERO), Vector3.DOWN)


func test_near_zero_input_falls_back_to_down() -> void:
	assert_eq(LashMath.snap_axis(Vector3(0.00001, -0.00001, 0.00002)), Vector3.DOWN)


func test_y_tie_prefers_vertical() -> void:
	# Equal vertical and horizontal magnitudes: Y wins.
	assert_eq(LashMath.snap_axis(Vector3(0.5, 0.5, 0.0)), Vector3.UP)
	assert_eq(LashMath.snap_axis(Vector3(0.0, -0.5, 0.5)), Vector3.DOWN)


func test_x_ties_z_prefers_x() -> void:
	# Equal X and Z magnitudes (Y smaller): X wins.
	assert_eq(LashMath.snap_axis(Vector3(0.5, 0.1, 0.5)), Vector3.RIGHT)
	assert_eq(LashMath.snap_axis(Vector3(-0.5, 0.1, -0.5)), Vector3.LEFT)


func test_result_is_unit_length() -> void:
	assert_almost_eq(LashMath.snap_axis(Vector3(3.0, 7.0, 1.0)).length(), 1.0, 0.0001)
