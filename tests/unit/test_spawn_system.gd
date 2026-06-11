extends GutTest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _def(creature_id: StringName) -> CreatureDef:
	var d := CreatureDef.new()
	d.id = creature_id
	return d


func _two_defs() -> Array[CreatureDef]:
	var out: Array[CreatureDef] = []
	out.append(_def(&"voidmoth"))
	out.append(_def(&"shardling"))
	return out


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Flat ground at y=0 — always valid.
func _flat_height(_pos: Vector3) -> float:
	return 0.0


## Always-invalid column.
func _nan_height(_pos: Vector3) -> float:
	return NAN


func _system(seed_value: int) -> SpawnSystem:
	return SpawnSystem.new(_rng(seed_value), _two_defs())


# ---------------------------------------------------------------------------
# Interval gating
# ---------------------------------------------------------------------------


## Non-multiple ticks yield no spawns regardless of state.
func test_non_interval_tick_yields_nothing() -> void:
	var sys := _system(1)
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	for tick in [1, 7, 39, 41, 79, 81]:
		var plan := sys.plan(tick, Vector3.ZERO, 0, [], flat)
		assert_eq(plan.size(), 0, "Tick %d is not a planning tick" % tick)


## Tick 0 and multiples of the interval do plan (open terrain, no glow).
func test_interval_tick_plans() -> void:
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	for tick in [0, 40, 80, 120, 200, 400]:
		var sys := _system(tick + 1)
		var plan := sys.plan(tick, Vector3.ZERO, 0, [], flat)
		assert_eq(plan.size(), 1, "Tick %d is a planning tick and should spawn 1" % tick)


## Interval constant matches the pinned contract value.
func test_interval_constant() -> void:
	assert_eq(SpawnSystem.SPAWN_INTERVAL_TICKS, 40, "Spawn interval is 40 ticks")


# ---------------------------------------------------------------------------
# Population cap
# ---------------------------------------------------------------------------


## At or above the cap, planning yields nothing.
func test_population_cap_blocks() -> void:
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	for alive in [6, 7, 12]:
		var sys := _system(alive)
		var plan := sys.plan(40, Vector3.ZERO, alive, [], flat)
		assert_eq(plan.size(), 0, "alive=%d at/over cap must yield nothing" % alive)


## Just under the cap still spawns.
func test_below_cap_spawns() -> void:
	var sys := _system(3)
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	var plan := sys.plan(40, Vector3.ZERO, 5, [], flat)
	assert_eq(plan.size(), 1, "alive=5 is below cap and should spawn")


## Cap constant matches the pinned contract value.
func test_cap_constant() -> void:
	assert_eq(SpawnSystem.POPULATION_CAP, 6, "Population cap is 6")


# ---------------------------------------------------------------------------
# Single spawn per round
# ---------------------------------------------------------------------------


## A planning round emits at most one spawn.
func test_at_most_one_per_round() -> void:
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	for seed_value in range(50):
		var sys := _system(seed_value)
		var plan := sys.plan(40, Vector3.ZERO, 0, [], flat)
		assert_true(plan.size() <= 1, "Round must emit at most one spawn (seed %d)" % seed_value)


# ---------------------------------------------------------------------------
# Darkness rule
# ---------------------------------------------------------------------------


## A glow point within MIN_GLOW_DISTANCE of the candidate rejects the round.
func test_glow_within_min_distance_rejects() -> void:
	# For each seed that produces a spawn on open ground, placing a glow point
	# exactly at that spawn's XZ must reject the round.
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	var rejected := 0
	for seed_value in range(40):
		var open := _system(seed_value)
		var plan := open.plan(40, Vector3.ZERO, 0, [], flat)
		if plan.size() == 0:
			continue
		var pos: Vector3 = plan[0]["position"]
		var glow: Array[Vector3] = [Vector3(pos.x, 0.0, pos.z)]
		var blocked := _system(seed_value)
		var plan2 := blocked.plan(40, Vector3.ZERO, 0, glow, flat)
		assert_eq(plan2.size(), 0, "Glow on the candidate must reject (seed %d)" % seed_value)
		rejected += 1
	assert_gt(rejected, 0, "Expected at least one seed to exercise the darkness rule")


## A glow point just beyond MIN_GLOW_DISTANCE does not reject.
func test_glow_just_beyond_min_distance_allows() -> void:
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	var seed_value := 7
	var open := _system(seed_value)
	var plan := open.plan(40, Vector3.ZERO, 0, [], flat)
	assert_eq(plan.size(), 1, "precondition: seed 7 spawns on open ground")
	var pos: Vector3 = plan[0]["position"]
	# Place the glow MIN_GLOW_DISTANCE + 0.5 m away along +X from the candidate.
	var glow: Array[Vector3] = [Vector3(pos.x + SpawnSystem.MIN_GLOW_DISTANCE + 0.5, 0.0, pos.z)]
	var sys := _system(seed_value)
	var plan2 := sys.plan(40, Vector3.ZERO, 0, glow, flat)
	assert_eq(plan2.size(), 1, "Glow beyond the darkness radius must still allow the spawn")


## Distance is measured on the XZ plane (glow y is irrelevant).
func test_glow_distance_is_xz_only() -> void:
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	var seed_value := 7
	var open := _system(seed_value)
	var pos: Vector3 = open.plan(40, Vector3.ZERO, 0, [], flat)[0]["position"]
	# Same XZ as the candidate but a huge y offset — still within darkness radius.
	var glow: Array[Vector3] = [Vector3(pos.x, 500.0, pos.z)]
	var sys := _system(seed_value)
	var plan := sys.plan(40, Vector3.ZERO, 0, glow, flat)
	assert_eq(plan.size(), 0, "Vertical offset must not save a candidate inside the XZ radius")


## Min-glow-distance constant matches the pinned contract value.
func test_min_glow_distance_constant() -> void:
	assert_eq(SpawnSystem.MIN_GLOW_DISTANCE, 9.0, "Min glow distance is 9.0 m")


# ---------------------------------------------------------------------------
# Ring bounds
# ---------------------------------------------------------------------------


## Across 200 seeded samples, every spawn lands on the 20..42 m ring.
func test_ring_bounds_respected() -> void:
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	var player := Vector3(13.0, 5.0, -27.0)
	var samples := 0
	for seed_value in range(200):
		var sys := _system(seed_value)
		var plan := sys.plan(40, player, 0, [], flat)
		assert_eq(plan.size(), 1, "Open ground with no glow always spawns (seed %d)" % seed_value)
		var pos: Vector3 = plan[0]["position"]
		var dx := pos.x - player.x
		var dz := pos.z - player.z
		var dist := sqrt(dx * dx + dz * dz)
		assert_between(
			dist,
			SpawnSystem.RING_MIN - 0.001,
			SpawnSystem.RING_MAX + 0.001,
			"Spawn dist %f must be on the ring (seed %d)" % [dist, seed_value]
		)
		samples += 1
	assert_eq(samples, 200, "All 200 samples must produce a spawn")


## Spawn height comes from height_fn and is applied to the position.
func test_height_from_height_fn() -> void:
	var bumpy := func(p: Vector3) -> float: return p.x * 0.0 + 17.5
	var sys := _system(4)
	var plan := sys.plan(40, Vector3.ZERO, 0, [], bumpy)
	assert_eq(plan.size(), 1, "precondition: spawns")
	assert_almost_eq(plan[0]["position"].y, 17.5, 0.001, "Spawn y must come from height_fn")


## Ring constants match the pinned contract values.
func test_ring_constants() -> void:
	assert_eq(SpawnSystem.RING_MIN, 20.0, "Ring min is 20.0 m")
	assert_eq(SpawnSystem.RING_MAX, 42.0, "Ring max is 42.0 m")


# ---------------------------------------------------------------------------
# Invalid height
# ---------------------------------------------------------------------------


## A NAN ground height rejects the candidate.
func test_nan_height_rejects() -> void:
	var nan_fn := func(p: Vector3) -> float: return _nan_height(p)
	for seed_value in range(20):
		var sys := _system(seed_value)
		var plan := sys.plan(40, Vector3.ZERO, 0, [], nan_fn)
		assert_eq(plan.size(), 0, "NAN height must reject (seed %d)" % seed_value)


# ---------------------------------------------------------------------------
# Empty defs
# ---------------------------------------------------------------------------


## With no creature defs configured, planning yields nothing.
func test_no_defs_yields_nothing() -> void:
	var empty_defs: Array[CreatureDef] = []
	var sys := SpawnSystem.new(_rng(1), empty_defs)
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	var plan := sys.plan(40, Vector3.ZERO, 0, [], flat)
	assert_eq(plan.size(), 0, "No defs means no possible spawn")


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------


## Same seed => identical plan sequence over many planning rounds.
func test_same_seed_identical_plan_sequence() -> void:
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	var player := Vector3(2.0, 0.0, 3.0)
	var sys_a := _system(12345)
	var sys_b := _system(12345)
	var ticks := [0, 40, 80, 120, 160, 200, 240, 280]
	for tick in ticks:
		var a := sys_a.plan(tick, player, 0, [], flat)
		var b := sys_b.plan(tick, player, 0, [], flat)
		assert_eq(a.size(), b.size(), "Plan sizes must match at tick %d" % tick)
		if a.size() == 1:
			assert_eq(a[0]["def"].id, b[0]["def"].id, "Species must match at tick %d" % tick)
			assert_almost_eq(
				a[0]["position"].distance_to(b[0]["position"]),
				0.0,
				0.0001,
				"Positions must match at tick %d" % tick
			)


## Different seeds produce different position streams (overwhelmingly likely).
func test_different_seeds_diverge() -> void:
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	var a := _system(1).plan(40, Vector3.ZERO, 0, [], flat)
	var b := _system(2).plan(40, Vector3.ZERO, 0, [], flat)
	assert_gt(
		a[0]["position"].distance_to(b[0]["position"]),
		0.001,
		"Distinct seeds should pick distinct candidate positions"
	)


# ---------------------------------------------------------------------------
# Species distribution
# ---------------------------------------------------------------------------


## Across 400 samples the two species are picked roughly evenly (35-65%).
func test_species_distribution_even() -> void:
	var flat := func(p: Vector3) -> float: return _flat_height(p)
	var counts := {&"voidmoth": 0, &"shardling": 0}
	var total := 0
	for seed_value in range(400):
		var sys := _system(seed_value)
		var plan := sys.plan(40, Vector3.ZERO, 0, [], flat)
		assert_eq(plan.size(), 1, "Open ground always spawns (seed %d)" % seed_value)
		var picked: StringName = plan[0]["def"].id
		counts[picked] += 1
		total += 1
	assert_eq(total, 400, "Expected 400 samples")
	var void_frac := float(counts[&"voidmoth"]) / float(total)
	var shard_frac := float(counts[&"shardling"]) / float(total)
	assert_between(void_frac, 0.35, 0.65, "voidmoth share %f should be ~even" % void_frac)
	assert_between(shard_frac, 0.35, 0.65, "shardling share %f should be ~even" % shard_frac)
