## Tests StormCatcher: deposit capacity gating, collect exchange, charge_one
## state machine, and gems_changed signal emission.
##
## Uses real StormCatcher instances added to the scene tree so group membership
## and signals work correctly without mocking.
extends GutTest

var _catcher: StormCatcher


func before_each() -> void:
	_catcher = StormCatcher.new()
	add_child_autofree(_catcher)


# ---------------------------------------------------------------------------
# Group registration
# ---------------------------------------------------------------------------


func test_joins_storm_catchers_group_on_ready() -> void:
	assert_true(_catcher.is_in_group(&"storm_catchers"), "StormCatcher must join storm_catchers")


# ---------------------------------------------------------------------------
# deposit
# ---------------------------------------------------------------------------


func test_deposit_accepts_gems_up_to_capacity() -> void:
	var accepted := _catcher.deposit(4)
	assert_eq(accepted, 4, "should accept all 4 on empty rack")
	assert_eq(_catcher.dun_count(), 4, "dun count should be 4")


func test_deposit_refuses_beyond_capacity() -> void:
	var accepted := _catcher.deposit(10)
	assert_eq(accepted, StormCatcher.CAPACITY, "capped at CAPACITY")
	assert_eq(_catcher.dun_count(), StormCatcher.CAPACITY)


func test_deposit_partial_when_partially_full() -> void:
	_catcher.deposit(3)
	var accepted := _catcher.deposit(3)
	assert_eq(accepted, 1, "only 1 slot remaining")
	assert_eq(_catcher.dun_count(), 4)


func test_deposit_zero_when_full() -> void:
	_catcher.deposit(4)
	var accepted := _catcher.deposit(1)
	assert_eq(accepted, 0, "rack full -> accepts nothing")


func test_deposit_emits_gems_changed() -> void:
	watch_signals(_catcher)
	_catcher.deposit(2)
	assert_signal_emitted(_catcher, "gems_changed")


# ---------------------------------------------------------------------------
# collect
# ---------------------------------------------------------------------------


func test_collect_returns_all_counts() -> void:
	_catcher.deposit(3)
	_catcher.charge_one()
	var result := _catcher.collect()
	assert_eq(result["dun"], 2, "collect returns remaining dun count")
	assert_eq(result["charged"], 1, "collect returns charged count")


func test_collect_empties_rack() -> void:
	_catcher.deposit(4)
	_catcher.collect()
	assert_eq(_catcher.dun_count(), 0, "rack empty after collect")
	assert_eq(_catcher.charged_count(), 0, "charged also zero after collect")


func test_collect_emits_gems_changed() -> void:
	_catcher.deposit(2)
	watch_signals(_catcher)
	_catcher.collect()
	assert_signal_emitted(_catcher, "gems_changed")


func test_collect_on_empty_rack_returns_zeros() -> void:
	var result := _catcher.collect()
	assert_eq(result["dun"], 0, "empty rack dun should be 0")
	assert_eq(result["charged"], 0, "empty rack charged should be 0")


# ---------------------------------------------------------------------------
# charge_one
# ---------------------------------------------------------------------------


func test_charge_one_converts_dun_to_charged() -> void:
	_catcher.deposit(2)
	var ok := _catcher.charge_one()
	assert_true(ok, "charge_one succeeds when dun > 0")
	assert_eq(_catcher.dun_count(), 1)
	assert_eq(_catcher.charged_count(), 1)


func test_charge_one_returns_false_when_no_dun() -> void:
	var ok := _catcher.charge_one()
	assert_false(ok, "charge_one fails when no dun gems")
	assert_eq(_catcher.charged_count(), 0, "charged count unchanged")


func test_charge_one_emits_gems_changed() -> void:
	_catcher.deposit(1)
	watch_signals(_catcher)
	_catcher.charge_one()
	assert_signal_emitted(_catcher, "gems_changed")


func test_charge_one_all_converts_all_dun() -> void:
	_catcher.deposit(4)
	for i in range(4):
		_catcher.charge_one()
	assert_eq(_catcher.dun_count(), 0)
	assert_eq(_catcher.charged_count(), 4)


func test_charge_one_does_not_exceed_capacity() -> void:
	# Start with 4 charged (fill by converting 4 dun).
	_catcher.deposit(4)
	for i in range(4):
		_catcher.charge_one()
	# Total should still be CAPACITY.
	assert_eq(_catcher.dun_count() + _catcher.charged_count(), StormCatcher.CAPACITY)


# ---------------------------------------------------------------------------
# CAPACITY constant
# ---------------------------------------------------------------------------


func test_capacity_is_four() -> void:
	assert_eq(StormCatcher.CAPACITY, 4, "CAPACITY must be 4 per contract")
