extends GutTest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _service(seed_value: int, inv: Inventory) -> LootService:
	return LootService.new(WorldSeed.new(seed_value), inv)


## Flatten an Array[ItemAmount] into a comparable {id: count} dictionary.
func _to_map(awarded: Array) -> Dictionary:
	var out := {}
	for a in awarded:
		out[a.item_id] = a.count
	return out


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------


func test_same_seed_and_center_identical_awards() -> void:
	var inv_a := Inventory.new(24)
	var inv_b := Inventory.new(24)
	var svc_a := _service(12345, inv_a)
	var svc_b := _service(12345, inv_b)
	var center := Vector3(3, -2, 7)
	var award_a := _to_map(svc_a.award_dig_loot(center, 3.0))
	var award_b := _to_map(svc_b.award_dig_loot(center, 3.0))
	assert_eq(award_a, award_b, "Same seed + center must give identical awards")
	# And the inventory effect must match too.
	assert_eq(
		inv_a.count_of(&"crystal_shard"),
		inv_b.count_of(&"crystal_shard"),
		"Crystal outcome must be reproducible"
	)


func test_repeated_dig_same_center_repeats_crystal_roll() -> void:
	# Because the stream is re-seeded from the quantized center, two digs at the
	# same cell produce the SAME crystal decision every time.
	var inv := Inventory.new(24)
	var svc := _service(999, inv)
	var first := _to_map(svc.award_dig_loot(Vector3(5, 5, 5), 2.0))
	var second := _to_map(svc.award_dig_loot(Vector3(5, 5, 5), 2.0))
	assert_eq(
		first.has(&"crystal_shard"),
		second.has(&"crystal_shard"),
		"Same cell yields the same crystal decision"
	)


func test_center_quantization_groups_nearby_positions() -> void:
	var svc := _service(7, Inventory.new(24))
	var a := _to_map(svc.award_dig_loot(Vector3(4.1, 4.05, 3.95), 2.0))
	var b := _to_map(svc.award_dig_loot(Vector3(4.0, 4.0, 4.0), 2.0))
	assert_eq(
		a.has(&"crystal_shard"), b.has(&"crystal_shard"), "Near-identical centers quantize together"
	)


# ---------------------------------------------------------------------------
# Soil scaling with radius
# ---------------------------------------------------------------------------


func test_soil_scales_with_radius() -> void:
	var svc := _service(1, Inventory.new(24))
	assert_eq(_to_map(svc.award_dig_loot(Vector3(1, 0, 0), 2.0))[&"soil"], 4, "r=2 => 4 soil")
	assert_eq(_to_map(svc.award_dig_loot(Vector3(2, 0, 0), 3.0))[&"soil"], 6, "r=3 => 6 soil")


func test_soil_clamped_minimum() -> void:
	var svc := _service(1, Inventory.new(24))
	# radius 0 => int(0) => clamped up to 1.
	assert_eq(_to_map(svc.award_dig_loot(Vector3(9, 0, 0), 0.0))[&"soil"], 1, "Soil floor is 1")


func test_soil_clamped_maximum() -> void:
	var svc := _service(1, Inventory.new(24))
	# radius 10 => int(20) => clamped down to 8.
	assert_eq(_to_map(svc.award_dig_loot(Vector3(9, 9, 9), 10.0))[&"soil"], 8, "Soil ceiling is 8")


# ---------------------------------------------------------------------------
# Crystal shard probability (~18% across distinct cells)
# ---------------------------------------------------------------------------


func test_crystal_shard_probability_band() -> void:
	# Sample 500 distinct dig cells; the crystal-shard frequency should sit
	# near the 18% target. Use a generous 12%..26% band to stay robust.
	var samples := 500
	var hits := 0
	for i in range(samples):
		var inv := Inventory.new(24)
		var svc := _service(424242, inv)
		# Distinct centers spread across a 3D lattice so each re-seeds uniquely.
		var center := Vector3(i % 50, (i / 50) % 50, i / 2500)
		svc.award_dig_loot(center, 2.0)
		if inv.count_of(&"crystal_shard") > 0:
			hits += 1
	var rate := float(hits) / float(samples)
	assert_between(rate, 0.12, 0.26, "Crystal rate %.3f should be ~0.18" % rate)


# ---------------------------------------------------------------------------
# Harvest loot
# ---------------------------------------------------------------------------


func test_award_harvest_loot_adds_drops() -> void:
	var inv := Inventory.new(24)
	var svc := _service(5, inv)
	var spore := ItemAmount.new()
	spore.item_id = &"glow_spore"
	spore.count = 2
	var petal := ItemAmount.new()
	petal.item_id = &"lumen_petal"
	petal.count = 3
	var drops: Array[ItemAmount] = [spore, petal]
	svc.award_harvest_loot(drops)
	assert_eq(inv.count_of(&"glow_spore"), 2, "Spores added")
	assert_eq(inv.count_of(&"lumen_petal"), 3, "Petals added")


func test_award_harvest_loot_ignores_empty_and_null() -> void:
	var inv := Inventory.new(24)
	var svc := _service(5, inv)
	var bad := ItemAmount.new()
	bad.item_id = &""
	bad.count = 5
	var zero := ItemAmount.new()
	zero.item_id = &"glow_spore"
	zero.count = 0
	var drops: Array[ItemAmount] = [bad, zero, null]
	svc.award_harvest_loot(drops)
	assert_true(inv.is_empty(), "Invalid drops contribute nothing")
