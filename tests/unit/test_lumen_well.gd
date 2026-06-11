extends GutTest

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------


## A new well starts empty at its declared capacity.
func test_starts_empty_at_capacity() -> void:
	var well := LumenWell.new(100.0)
	assert_eq(well.capacity(), 100.0)
	assert_eq(well.current(), 0.0)


## Default capacity is 100.
func test_default_capacity() -> void:
	assert_eq(LumenWell.new().capacity(), 100.0)


# ---------------------------------------------------------------------------
# add() — clamp + overflow
# ---------------------------------------------------------------------------


## A partial add below capacity stores it all and reports no overflow.
func test_add_below_capacity_no_overflow() -> void:
	var well := LumenWell.new(100.0)
	var overflow := well.add(30.0)
	assert_eq(overflow, 0.0, "Fits entirely")
	assert_eq(well.current(), 30.0)


## Adding past capacity clamps and returns the overflow.
func test_add_overflow_clamps_and_reports() -> void:
	var well := LumenWell.new(100.0)
	well.add(80.0)
	var overflow := well.add(50.0)
	assert_eq(well.current(), 100.0, "Clamped at capacity")
	assert_eq(overflow, 30.0, "Overflow is the unaccepted portion")


## Filling exactly to the brim reports zero overflow.
func test_add_exact_fill_no_overflow() -> void:
	var well := LumenWell.new(100.0)
	var overflow := well.add(100.0)
	assert_eq(well.current(), 100.0)
	assert_eq(overflow, 0.0)


## Adding to an already-full well returns the full amount as overflow.
func test_add_to_full_returns_all_as_overflow() -> void:
	var well := LumenWell.new(100.0)
	well.add(100.0)
	var overflow := well.add(25.0)
	assert_eq(overflow, 25.0, "Nothing accepted; all overflows")
	assert_eq(well.current(), 100.0)


## Non-positive adds are no-ops returning zero overflow.
func test_add_nonpositive_is_noop() -> void:
	var well := LumenWell.new(100.0)
	assert_eq(well.add(0.0), 0.0)
	assert_eq(well.add(-10.0), 0.0)
	assert_eq(well.current(), 0.0)


# ---------------------------------------------------------------------------
# spend() — all-or-nothing
# ---------------------------------------------------------------------------


## Spending what the well holds succeeds and deducts.
func test_spend_affordable_succeeds() -> void:
	var well := LumenWell.new(100.0)
	well.add(50.0)
	assert_true(well.spend(20.0))
	assert_eq(well.current(), 30.0)


## Spending more than held fails and leaves the well untouched.
func test_spend_unaffordable_is_all_or_nothing() -> void:
	var well := LumenWell.new(100.0)
	well.add(10.0)
	assert_false(well.spend(25.0), "Cannot afford")
	assert_eq(well.current(), 10.0, "Untouched after a failed spend")


## Spending exactly the held amount succeeds and empties the well.
func test_spend_exact_balance_succeeds() -> void:
	var well := LumenWell.new(100.0)
	well.add(40.0)
	assert_true(well.spend(40.0), "Exactly-equal is affordable")
	assert_eq(well.current(), 0.0)


## Non-positive spends trivially succeed without changing the well.
func test_spend_nonpositive_succeeds_noop() -> void:
	var well := LumenWell.new(100.0)
	well.add(10.0)
	assert_true(well.spend(0.0))
	assert_true(well.spend(-5.0))
	assert_eq(well.current(), 10.0)


# ---------------------------------------------------------------------------
# can_afford() — edges
# ---------------------------------------------------------------------------


func test_can_afford_less_than_balance() -> void:
	var well := LumenWell.new(100.0)
	well.add(50.0)
	assert_true(well.can_afford(49.9))


func test_can_afford_exactly_equal() -> void:
	var well := LumenWell.new(100.0)
	well.add(50.0)
	assert_true(well.can_afford(50.0), "Exactly-equal is affordable")


func test_cannot_afford_just_over() -> void:
	var well := LumenWell.new(100.0)
	well.add(50.0)
	assert_false(well.can_afford(50.01))


func test_can_afford_zero_on_empty() -> void:
	assert_true(LumenWell.new(100.0).can_afford(0.0))


# ---------------------------------------------------------------------------
# changed signal — emission counting
# ---------------------------------------------------------------------------


## A successful add that moves the stored amount emits exactly once.
func test_changed_emits_on_accepted_add() -> void:
	var well := LumenWell.new(100.0)
	watch_signals(well)
	well.add(30.0)
	assert_signal_emitted_with_parameters(well, "changed", [30.0, 100.0])
	assert_signal_emit_count(well, "changed", 1)


## A zero-change add (already full, or non-positive) emits nothing.
func test_changed_no_emit_on_zero_change_add() -> void:
	var well := LumenWell.new(100.0)
	well.add(100.0)  # fills
	watch_signals(well)
	well.add(10.0)  # nothing accepted
	well.add(0.0)  # no-op
	well.add(-5.0)  # no-op
	assert_signal_emit_count(well, "changed", 0, "No-op adds never emit")


## A successful spend emits exactly once; a failed spend emits nothing.
func test_changed_emit_on_spend_only_when_successful() -> void:
	var well := LumenWell.new(100.0)
	well.add(50.0)
	watch_signals(well)
	assert_true(well.spend(20.0))
	assert_signal_emit_count(well, "changed", 1, "Successful spend emits")
	assert_false(well.spend(999.0))
	assert_signal_emit_count(well, "changed", 1, "Failed spend does not emit")


## Non-positive spends never emit.
func test_changed_no_emit_on_nonpositive_spend() -> void:
	var well := LumenWell.new(100.0)
	well.add(10.0)
	watch_signals(well)
	well.spend(0.0)
	well.spend(-3.0)
	assert_signal_emit_count(well, "changed", 0)
