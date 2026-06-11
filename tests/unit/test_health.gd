extends GutTest

## Covers [Health]: clamped damage/heal, the single-shot [signal died]
## guarantee, dead-pool no-ops, and the actually-applied amounts returned by
## [method Health.take_damage] and [method Health.heal].


func test_starts_full_and_alive() -> void:
	var h := Health.new(40.0)
	assert_eq(h.max_health(), 40.0)
	assert_eq(h.current(), 40.0)
	assert_false(h.is_dead())


func test_non_positive_max_clamps_to_minimal_positive() -> void:
	var h := Health.new(0.0)
	assert_gt(h.max_health(), 0.0)
	assert_false(h.is_dead())


func test_take_damage_returns_applied_and_reduces_current() -> void:
	var h := Health.new(40.0)
	var applied := h.take_damage(15.0)
	assert_eq(applied, 15.0)
	assert_eq(h.current(), 25.0)


func test_take_damage_clamps_applied_to_remaining() -> void:
	var h := Health.new(10.0)
	# Overkill returns only the portion above zero, not the full request.
	var applied := h.take_damage(25.0)
	assert_eq(applied, 10.0)
	assert_eq(h.current(), 0.0)
	assert_true(h.is_dead())


func test_take_damage_emits_changed() -> void:
	var h := Health.new(40.0)
	watch_signals(h)
	h.take_damage(5.0)
	assert_signal_emitted_with_parameters(h, "changed", [35.0, 40.0])


func test_non_positive_damage_is_noop() -> void:
	var h := Health.new(40.0)
	watch_signals(h)
	assert_eq(h.take_damage(0.0), 0.0)
	assert_eq(h.take_damage(-5.0), 0.0)
	assert_eq(h.current(), 40.0)
	assert_signal_not_emitted(h, "changed")


func test_died_emitted_exactly_once_on_crossing_zero() -> void:
	var h := Health.new(10.0)
	watch_signals(h)
	h.take_damage(10.0)
	assert_signal_emit_count(h, "died", 1)


func test_dead_pool_take_damage_is_noop_and_no_redied() -> void:
	var h := Health.new(10.0)
	h.take_damage(10.0)
	watch_signals(h)
	# Further damage on a dead pool returns nothing and never re-emits died.
	assert_eq(h.take_damage(5.0), 0.0)
	assert_signal_not_emitted(h, "died")
	assert_signal_not_emitted(h, "changed")


func test_heal_returns_applied_and_raises_current() -> void:
	var h := Health.new(40.0)
	h.take_damage(20.0)
	var healed := h.heal(12.0)
	assert_eq(healed, 12.0)
	assert_eq(h.current(), 32.0)


func test_heal_clamps_to_max() -> void:
	var h := Health.new(40.0)
	h.take_damage(5.0)
	# Only the 5 hp below max are restored, not the full request.
	var healed := h.heal(50.0)
	assert_eq(healed, 5.0)
	assert_eq(h.current(), 40.0)


func test_heal_at_full_returns_zero_and_no_signal() -> void:
	var h := Health.new(40.0)
	watch_signals(h)
	assert_eq(h.heal(10.0), 0.0)
	assert_signal_not_emitted(h, "changed")


func test_heal_emits_changed_when_applied() -> void:
	var h := Health.new(40.0)
	h.take_damage(10.0)
	watch_signals(h)
	h.heal(4.0)
	assert_signal_emitted_with_parameters(h, "changed", [34.0, 40.0])


func test_heal_on_dead_pool_is_noop() -> void:
	var h := Health.new(10.0)
	h.take_damage(10.0)
	watch_signals(h)
	# Death is terminal; healing cannot revive.
	assert_eq(h.heal(5.0), 0.0)
	assert_eq(h.current(), 0.0)
	assert_true(h.is_dead())
	assert_signal_not_emitted(h, "changed")


func test_non_positive_heal_is_noop() -> void:
	var h := Health.new(40.0)
	h.take_damage(10.0)
	assert_eq(h.heal(0.0), 0.0)
	assert_eq(h.heal(-3.0), 0.0)
	assert_eq(h.current(), 30.0)
