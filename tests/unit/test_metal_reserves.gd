extends GutTest

## Exercises [MetalReserves]: per-metal wells, flake auto-swallow in [method
## MetalReserves.ensure] consuming exactly enough flakes, unknown-kind safety,
## capacity clamp, and re-emission of each well's changed signal tagged by kind.

const IRON := &"iron"
const STEEL := &"steel"
const FLAKE_IRON := &"iron_flakes"
const FLAKE_STEEL := &"steel_flakes"


func _reserves() -> MetalReserves:
	return MetalReserves.new({IRON: FLAKE_IRON, STEEL: FLAKE_STEEL})


func test_wells_start_empty_and_kinds_sorted() -> void:
	var r := _reserves()
	assert_eq(r.kinds(), [IRON, STEEL], "kinds sorted")
	assert_eq(r.well(IRON).current(), 0.0)
	assert_eq(r.well(STEEL).current(), 0.0)
	assert_eq(r.well(IRON).capacity(), MetalReserves.DEFAULT_CAPACITY)


func test_unknown_kind_is_safe() -> void:
	var r := _reserves()
	assert_null(r.well(&"gold"))
	assert_eq(r.add(&"gold", 10.0), 10.0, "unknown add overflows fully")
	assert_false(r.ensure(&"gold", 5.0, null), "unknown ensure false")


func test_add_clamps_at_capacity_and_reports_overflow() -> void:
	var r := _reserves()
	var overflow := r.add(IRON, 100.0)  # capacity 60
	assert_eq(r.well(IRON).current(), 60.0)
	assert_eq(overflow, 40.0)


func test_ensure_swallows_exactly_enough_flakes() -> void:
	var r := _reserves()
	var inv := Inventory.new(24, null)
	inv.add(FLAKE_IRON, 5)

	# Need 50; each flake = 30 charge. 0 -> 30 -> 60, so 2 flakes suffice.
	var ok := r.ensure(IRON, 50.0, inv)

	assert_true(ok)
	assert_eq(inv.count_of(FLAKE_IRON), 3, "consumed exactly 2 flakes")
	assert_eq(r.well(IRON).current(), 60.0, "clamped at capacity after 2 adds")


func test_ensure_stops_when_inventory_empty() -> void:
	var r := _reserves()
	var inv := Inventory.new(24, null)
	inv.add(FLAKE_IRON, 1)  # only 30 charge available

	var ok := r.ensure(IRON, 50.0, inv)

	assert_false(ok, "30 < 50, cannot afford")
	assert_eq(inv.count_of(FLAKE_IRON), 0, "spent the one flake it had")
	assert_eq(r.well(IRON).current(), 30.0)


func test_ensure_null_inventory_is_noop_topup() -> void:
	var r := _reserves()
	r.add(IRON, 20.0)
	assert_false(r.ensure(IRON, 50.0, null), "no top-up, 20 < 50")
	assert_true(r.ensure(IRON, 20.0, null), "already affordable")
	assert_eq(r.well(IRON).current(), 20.0)


func test_ensure_for_cost_lumen_and_unknown_are_noop_true() -> void:
	var r := _reserves()
	var inv := Inventory.new(24, null)
	var lumen_ability := AbilityDef.new()
	lumen_ability.resource_kind = &"lumen"
	lumen_ability.lumen_cost = 12.0
	assert_true(r.ensure_for_cost(lumen_ability, inv))

	var gold_ability := AbilityDef.new()
	gold_ability.resource_kind = &"gold"
	gold_ability.lumen_cost = 12.0
	assert_true(r.ensure_for_cost(gold_ability, inv))


func test_ensure_for_cost_metal_tops_up() -> void:
	var r := _reserves()
	var inv := Inventory.new(24, null)
	inv.add(FLAKE_STEEL, 2)
	var ability := AbilityDef.new()
	ability.resource_kind = STEEL
	ability.lumen_cost = 12.0

	assert_true(r.ensure_for_cost(ability, inv))
	assert_eq(inv.count_of(FLAKE_STEEL), 1, "one flake swallowed to cover 12")
	assert_eq(r.well(STEEL).current(), 30.0)


func test_changed_signal_re_emits_with_kind() -> void:
	var r := _reserves()
	watch_signals(r)
	r.add(IRON, 15.0)
	assert_signal_emitted_with_parameters(
		r, "changed", [IRON, 15.0, MetalReserves.DEFAULT_CAPACITY]
	)
