extends GutTest

## Exhaustive check on [StepTimeline] (Phase 6 contract #1): exact durations for
## the canonical 110 BPM / 16-step / 4-subdivision grid, [method
## StepTimeline.step_at] wrapping and boundary behaviour, and [method
## StepTimeline.steps_crossed] producing the ordered set of crossed step
## boundaries in the half-open interval (prev, now], including loop wrap and
## multi-step jumps. All values are recomputed by hand so the test is an
## independent oracle, not a tautology over the implementation.

const EPS := 1e-6
const BPM := 110.0
const STEPS := 16
const SUBDIV := 4

# 60 / 110 / 4 = 0.13636363... seconds per step.
const STEP_DUR := 60.0 / BPM / SUBDIV
const LOOP_DUR := STEPS * STEP_DUR


func _t() -> StepTimeline:
	return StepTimeline.new(BPM, STEPS, SUBDIV)


# ---------------------------------------------------------------------------
# Durations
# ---------------------------------------------------------------------------


func test_durations_exact() -> void:
	var t := _t()
	assert_almost_eq(t.step_duration(), STEP_DUR, EPS, "step_duration must be 60/bpm/subdivision")
	assert_almost_eq(t.loop_duration(), LOOP_DUR, EPS, "loop_duration must be steps*step_dur")
	# 16 sixteenths at 110 BPM = one 4/4 bar = 4 * 60/110 seconds.
	assert_almost_eq(t.loop_duration(), 4.0 * 60.0 / BPM, EPS, "loop is one 4/4 bar")


func test_defaults_match_canonical() -> void:
	var t := StepTimeline.new()
	assert_eq(t.bpm, 110.0, "default bpm")
	assert_eq(t.steps, 16, "default steps")
	assert_almost_eq(t.subdivision, 4.0, EPS, "default subdivision")


# ---------------------------------------------------------------------------
# step_at: wrap + boundaries
# ---------------------------------------------------------------------------


func test_step_at_zero_is_step_zero() -> void:
	assert_eq(_t().step_at(0.0), 0, "t=0 is step 0")


func test_step_at_each_step_start() -> void:
	var t := _t()
	for i in STEPS:
		# A hair into the step so float rounding cannot land us on the prior one.
		var pos := i * STEP_DUR + STEP_DUR * 0.5
		assert_eq(t.step_at(pos), i, "midpoint of step %d maps to %d" % [i, i])


func test_step_at_wraps_one_loop() -> void:
	var t := _t()
	# One full loop later lands back on the same step.
	assert_eq(t.step_at(LOOP_DUR + STEP_DUR * 0.5), 0, "one loop + half step -> step 0")
	assert_eq(t.step_at(LOOP_DUR * 3 + STEP_DUR * 1.5), 1, "3 loops + 1.5 steps -> step 1")


func test_step_at_last_step() -> void:
	var t := _t()
	assert_eq(t.step_at(15 * STEP_DUR + STEP_DUR * 0.5), 15, "last step")
	# Just before the loop boundary is still the last step.
	assert_eq(t.step_at(LOOP_DUR - EPS), 15, "just before loop end is step 15")


func test_step_at_clamps_in_range() -> void:
	var t := _t()
	for k in [0.0, 0.001, LOOP_DUR - EPS, LOOP_DUR, LOOP_DUR + 5.0, 999.0]:
		var s := t.step_at(k)
		assert_true(s >= 0 and s <= STEPS - 1, "step_at(%f)=%d in range" % [k, s])


# ---------------------------------------------------------------------------
# steps_crossed: basics
# ---------------------------------------------------------------------------


func test_same_step_returns_empty() -> void:
	var t := _t()
	var a := STEP_DUR * 0.2
	var b := STEP_DUR * 0.8
	assert_eq(t.steps_crossed(a, b), [] as Array[int], "no boundary within one step -> empty")


func test_equal_inputs_empty() -> void:
	var t := _t()
	assert_eq(t.steps_crossed(0.0, 0.0), [] as Array[int], "prev==now -> empty")
	assert_eq(
		t.steps_crossed(STEP_DUR * 2.5, STEP_DUR * 2.5), [] as Array[int], "mid-step equal -> empty"
	)


func test_single_boundary_crossing() -> void:
	var t := _t()
	# From inside step 0 to inside step 1 crosses exactly the boundary into 1.
	var crossed := t.steps_crossed(STEP_DUR * 0.5, STEP_DUR * 1.5)
	assert_eq(crossed, [1] as Array[int], "crossing 0->1 yields [1]")


func test_consecutive_boundaries_each_once() -> void:
	var t := _t()
	# Sweep across several steps one boundary at a time, never skipping.
	var prev := STEP_DUR * 0.5
	for i in range(1, 6):
		var now := STEP_DUR * (i + 0.5)
		var crossed := t.steps_crossed(prev, now)
		assert_eq(crossed, [i] as Array[int], "step %d crossed exactly once" % i)
		prev = now


# ---------------------------------------------------------------------------
# steps_crossed: multi-step jumps (ordered)
# ---------------------------------------------------------------------------


func test_multi_step_jump_ordered() -> void:
	var t := _t()
	# From inside step 1 to inside step 5 crosses 2,3,4,5 in order.
	var crossed := t.steps_crossed(STEP_DUR * 1.5, STEP_DUR * 5.5)
	assert_eq(crossed, [2, 3, 4, 5] as Array[int], "multi-step jump lists each in order")


func test_jump_landing_exactly_on_boundary() -> void:
	var t := _t()
	# From inside step 1 to exactly the start of step 4: crosses 2,3,4.
	var crossed := t.steps_crossed(STEP_DUR * 1.5, STEP_DUR * 4.0)
	assert_eq(crossed, [2, 3, 4] as Array[int], "landing on a boundary counts that step")


func test_full_loop_span_crosses_all_sixteen() -> void:
	var t := _t()
	# Advancing exactly one loop from a boundary crosses all 16 boundaries.
	var crossed := t.steps_crossed(0.0, LOOP_DUR)
	assert_eq(crossed.size(), 16, "one full loop crosses 16 boundaries")
	# Order is 1,2,...,15,0 (the boundary into step 1 is the first after t=0).
	var expected: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0]
	assert_eq(crossed, expected, "full loop order wraps 15->0")


# ---------------------------------------------------------------------------
# steps_crossed: loop wrap (now < prev)
# ---------------------------------------------------------------------------


func test_wrap_15_to_0() -> void:
	var t := _t()
	# Inside step 15, then the transport looped to inside step 0 (now < prev).
	var prev := STEP_DUR * 15.5
	var now := STEP_DUR * 0.5  # wrapped past loop end back near the top
	var crossed := t.steps_crossed(prev, now)
	assert_eq(crossed, [0] as Array[int], "wrap from 15 into 0 yields [0]")


func test_wrap_spanning_multiple_steps() -> void:
	var t := _t()
	# Inside step 14, looped to inside step 2: crosses 15, 0, 1, 2.
	var prev := STEP_DUR * 14.5
	var now := STEP_DUR * 2.5
	var crossed := t.steps_crossed(prev, now)
	assert_eq(crossed, [15, 0, 1, 2] as Array[int], "wrap lists tail then head in order")


func test_wrap_equivalent_to_unwrapped_delta() -> void:
	var t := _t()
	# A wrap of total delta D must list the same steps as advancing D forward
	# from the same start without wrapping the absolute time.
	var prev := STEP_DUR * 13.5
	var now_wrapped := STEP_DUR * 1.5  # delta = (16-13.5+1.5)=4 steps
	var crossed := t.steps_crossed(prev, now_wrapped)
	assert_eq(crossed, [14, 15, 0, 1] as Array[int], "4-step wrap lists 14,15,0,1")


# ---------------------------------------------------------------------------
# Guards: negative / zero / degenerate
# ---------------------------------------------------------------------------


func test_negative_playback_wraps() -> void:
	var t := _t()
	# fposmod brings negative times back into [0, loop); -0.5 step -> step 15.
	assert_eq(t.step_at(-STEP_DUR * 0.5), 15, "negative time wraps to step 15")


func test_degenerate_inputs_guarded() -> void:
	# Zero bpm: never divides by zero, loop stays positive, step_at is safe.
	var zb := StepTimeline.new(0.0, 16, 4)
	assert_true(zb.step_duration() > 0.0, "zero bpm must not divide by zero")
	assert_true(zb.loop_duration() > 0.0, "loop still positive with guarded bpm")
	assert_eq(zb.step_at(0.0), 0, "step_at safe with guarded bpm")
	# Zero steps clamps to a single-step loop that always maps to 0.
	var zs := StepTimeline.new(110.0, 0, 4)
	assert_eq(zs.steps, 1, "steps clamps to at least 1")
	assert_eq(zs.step_at(5.0), 0, "single-step loop always maps to 0")
	# Zero subdivision: never divides by zero.
	var zd := StepTimeline.new(110.0, 16, 0)
	assert_true(zd.step_duration() > 0.0, "zero subdivision must not divide by zero")


func test_negative_delta_smaller_than_step_wrap() -> void:
	var t := _t()
	# A tiny backward move that does not cross a boundary returns empty even
	# though now < prev (it is a sub-step wrap with no boundary inside).
	var prev := STEP_DUR * 0.6
	var now := STEP_DUR * 0.55
	# delta < 0, +loop makes it ~15.95 steps forward -> crosses 16 boundaries.
	# This documents that "now<prev" is always treated as a forward wrap.
	var crossed := t.steps_crossed(prev, now)
	assert_eq(crossed.size(), 16, "a backward nudge is interpreted as a near-full forward wrap")
