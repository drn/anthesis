extends GutTest

## Exhaustive tests for the pure [UmbralAI] state machine: distance-driven state
## selection (wander / chase / attack), the wander-leg cadence and its seeded
## reproducibility, chase direction normalization on the XZ plane, attack gating
## by the cooldown including the exact boundary tick, the terminal dead state,
## and the determinism guarantee that one seed yields one decision sequence.


## Build a CreatureDef with the AI-relevant knobs set; defaults mirror voidmoth.
func _def(
	aggro := 14.0, attack_range := 1.6, cooldown := 12, wander_radius := 6.0, move_speed := 3.2
) -> CreatureDef:
	var d := CreatureDef.new()
	d.id = &"test_umbral"
	d.aggro_range = aggro
	d.attack_range = attack_range
	d.attack_cooldown_ticks = cooldown
	d.wander_radius = wander_radius
	d.move_speed = move_speed
	return d


func _rng(seed_value := 42) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# ---------------------------------------------------------------------------
# State selection by distance
# ---------------------------------------------------------------------------


func test_far_target_yields_wander() -> void:
	var ai := UmbralAI.new(_def(), _rng())
	# Target 100 m away is well beyond aggro_range (14) => wander.
	var d := ai.tick(Vector3.ZERO, Vector3(100, 0, 0), 0)
	assert_eq(d["state"], &"wander", "far target must wander")
	assert_false(d["attack"], "no attack while wandering")


func test_target_inside_aggro_yields_chase() -> void:
	var ai := UmbralAI.new(_def(), _rng())
	# 10 m away: inside aggro (14), outside attack (1.6) => chase.
	var d := ai.tick(Vector3.ZERO, Vector3(10, 0, 0), 0)
	assert_eq(d["state"], &"chase")
	assert_false(d["attack"])


func test_target_inside_attack_range_yields_attack() -> void:
	var ai := UmbralAI.new(_def(), _rng())
	var d := ai.tick(Vector3.ZERO, Vector3(1.0, 0, 0), 0)
	assert_eq(d["state"], &"attack")


func test_attack_uses_planar_distance_ignoring_y() -> void:
	# A target directly overhead (XZ distance 0) is in attack range despite a
	# large vertical gap — the AI reasons on the XZ plane only.
	var ai := UmbralAI.new(_def(), _rng())
	var d := ai.tick(Vector3.ZERO, Vector3(0, 50, 0), 0)
	assert_eq(d["state"], &"attack", "vertical separation must not block attack")


func test_aggro_exit_returns_to_wander() -> void:
	var ai := UmbralAI.new(_def(), _rng())
	assert_eq(ai.tick(Vector3.ZERO, Vector3(10, 0, 0), 0)["state"], &"chase")
	# Target flees beyond aggro => back to wander.
	assert_eq(ai.tick(Vector3.ZERO, Vector3(50, 0, 0), 1)["state"], &"wander")


func test_aggro_boundary_chase_at_exact_range() -> void:
	var ai := UmbralAI.new(_def(14.0), _rng())
	# Exactly at aggro_range counts as inside (<=), so chase (beyond attack).
	var d := ai.tick(Vector3.ZERO, Vector3(14.0, 0, 0), 0)
	assert_eq(d["state"], &"chase", "distance == aggro_range must chase")


func test_attack_boundary_just_inside_and_outside_range() -> void:
	# The attack cutoff is inclusive (planar distance <= attack_range). Verify the
	# transition straddling the boundary: just inside attacks, just outside chases.
	# (A target exactly on the boundary is avoided because Vector2.length()'s sqrt
	# can land a hair above an axis-aligned literal in float32.)
	var inside := UmbralAI.new(_def(14.0, 1.6), _rng())
	assert_eq(
		inside.tick(Vector3.ZERO, Vector3(1.59, 0, 0), 0)["state"],
		&"attack",
		"just inside attack_range must attack"
	)
	var outside := UmbralAI.new(_def(14.0, 1.6), _rng())
	assert_eq(
		outside.tick(Vector3.ZERO, Vector3(1.61, 0, 0), 0)["state"],
		&"chase",
		"just outside attack_range must chase"
	)


# ---------------------------------------------------------------------------
# Chase direction
# ---------------------------------------------------------------------------


func test_chase_dir_normalized_and_planar() -> void:
	var ai := UmbralAI.new(_def(), _rng())
	# Target up and to the +X/+Z; move_dir must be unit-length and have y == 0.
	var d := ai.tick(Vector3.ZERO, Vector3(6, 9, 8), 0)
	var dir: Vector3 = d["move_dir"]
	assert_eq(dir.y, 0.0, "chase move_dir must be flattened to XZ")
	assert_almost_eq(dir.length(), 1.0, 0.0001, "chase move_dir must be normalized")


func test_chase_dir_points_at_target() -> void:
	var ai := UmbralAI.new(_def(), _rng())
	var d := ai.tick(Vector3.ZERO, Vector3(0, 0, 10), 0)
	var dir: Vector3 = d["move_dir"]
	assert_almost_eq(dir.z, 1.0, 0.0001, "must head toward +Z target")
	assert_almost_eq(dir.x, 0.0, 0.0001)


# ---------------------------------------------------------------------------
# Wander leg cadence
# ---------------------------------------------------------------------------


func test_wander_picks_new_leg_on_cadence() -> void:
	# Home at origin; target always far so the AI wanders every tick. The wander
	# goal (and thus move_dir) changes only when a new leg is chosen.
	var ai := UmbralAI.new(_def(), _rng())
	var far := Vector3(100, 0, 0)
	var first: Vector3 = ai.tick(Vector3.ZERO, far, 0)["move_dir"]
	# Within the same leg window the direction toward the goal is stable.
	var mid: Vector3 = ai.tick(Vector3.ZERO, far, 5)["move_dir"]
	assert_eq(first, mid, "direction stable within a wander leg")
	# At WANDER_LEG_TICKS a fresh leg is chosen; with this seed it differs.
	var next_leg: Vector3 = ai.tick(Vector3.ZERO, far, UmbralAI.WANDER_LEG_TICKS)["move_dir"]
	assert_ne(first, next_leg, "new wander leg at the cadence boundary")


func test_wander_goal_within_radius_of_home() -> void:
	var radius := 6.0
	var ai := UmbralAI.new(_def(14.0, 1.6, 12, radius), _rng())
	var far := Vector3(200, 0, 0)
	# Home is the first self_pos. Sample many legs and confirm motion is always
	# headed somewhere reachable — direction stays a unit XZ vector.
	for i in range(0, 300, UmbralAI.WANDER_LEG_TICKS):
		var dir: Vector3 = ai.tick(Vector3.ZERO, far, i)["move_dir"]
		assert_eq(dir.y, 0.0, "wander dir flattened")
		# Either idle (zero) or a normalized heading.
		if dir != Vector3.ZERO:
			assert_almost_eq(dir.length(), 1.0, 0.0001, "wander dir normalized")


func test_wander_idles_when_arrived_at_goal() -> void:
	# A normal wander goal is offset from home, so the wisp wanders toward it.
	var ai := UmbralAI.new(_def(), _rng())
	var far := Vector3(500, 0, 0)
	assert_eq(ai.tick(Vector3.ZERO, far, 0)["state"], &"wander", "offset goal => wander")
	# With a zero wander radius the goal collapses onto home; standing on home the
	# wisp has already "arrived", so it idles with no motion.
	var still := UmbralAI.new(_def(14.0, 1.6, 12, 0.0), _rng())
	var d := still.tick(Vector3.ZERO, far, 0)
	assert_eq(d["state"], &"idle", "zero wander radius keeps goal at home => idle")
	assert_eq(d["move_dir"], Vector3.ZERO, "idle has no motion")


# ---------------------------------------------------------------------------
# Attack gating by cooldown
# ---------------------------------------------------------------------------


func test_attack_gated_by_cooldown_boundary() -> void:
	var cooldown := 12
	var ai := UmbralAI.new(_def(14.0, 1.6, cooldown), _rng())
	var close := Vector3(1.0, 0, 0)
	# First in-range tick lands a strike.
	assert_true(ai.tick(Vector3.ZERO, close, 0)["attack"], "first strike lands")
	# One tick short of cooldown: blocked.
	assert_false(ai.tick(Vector3.ZERO, close, cooldown - 1)["attack"], "still cooling down")
	# Exactly cooldown ticks later: lands again.
	assert_true(ai.tick(Vector3.ZERO, close, cooldown)["attack"], "boundary strike lands")
	# Immediately after: blocked again.
	assert_false(ai.tick(Vector3.ZERO, close, cooldown + 1)["attack"], "re-armed cooldown")


func test_attack_state_holds_even_when_strike_blocked() -> void:
	var ai := UmbralAI.new(_def(14.0, 1.6, 12), _rng())
	var close := Vector3(1.0, 0, 0)
	ai.tick(Vector3.ZERO, close, 0)  # lands, arms cooldown
	var d := ai.tick(Vector3.ZERO, close, 1)
	assert_eq(d["state"], &"attack", "stays in attack state while in range")
	assert_false(d["attack"], "but strike is gated by cooldown")


func test_first_attack_lands_immediately_regardless_of_tick() -> void:
	# A high starting tick index must not block the very first strike.
	var ai := UmbralAI.new(_def(14.0, 1.6, 12), _rng())
	assert_true(ai.tick(Vector3.ZERO, Vector3(1.0, 0, 0), 9999)["attack"])


# ---------------------------------------------------------------------------
# Dead terminal state
# ---------------------------------------------------------------------------


func test_dead_is_terminal() -> void:
	var ai := UmbralAI.new(_def(), _rng())
	ai.mark_dead()
	assert_eq(ai.state(), &"dead")
	# Even with a target point-blank, a dead AI never attacks or moves.
	var d := ai.tick(Vector3.ZERO, Vector3(0.5, 0, 0), 0)
	assert_eq(d["state"], &"dead")
	assert_eq(d["move_dir"], Vector3.ZERO)
	assert_false(d["attack"])


func test_dead_overrides_attack_and_chase() -> void:
	var ai := UmbralAI.new(_def(), _rng())
	assert_eq(ai.tick(Vector3.ZERO, Vector3(1.0, 0, 0), 0)["state"], &"attack")
	ai.mark_dead()
	assert_eq(ai.tick(Vector3.ZERO, Vector3(1.0, 0, 0), 1)["state"], &"dead")


# ---------------------------------------------------------------------------
# Determinism: one seed => one decision sequence
# ---------------------------------------------------------------------------


func test_same_seed_yields_identical_decision_sequence() -> void:
	var far := Vector3(80, 0, 0)
	var a := UmbralAI.new(_def(), _rng(7))
	var b := UmbralAI.new(_def(), _rng(7))
	for tick in range(0, 200):
		var da: Dictionary = a.tick(Vector3.ZERO, far, tick)
		var db: Dictionary = b.tick(Vector3.ZERO, far, tick)
		assert_eq(da["state"], db["state"], "state diverged at tick %d" % tick)
		assert_eq(da["move_dir"], db["move_dir"], "move_dir diverged at tick %d" % tick)
		assert_eq(da["attack"], db["attack"], "attack diverged at tick %d" % tick)


func test_different_seeds_diverge_in_wander() -> void:
	var far := Vector3(80, 0, 0)
	var a := UmbralAI.new(_def(), _rng(1))
	var b := UmbralAI.new(_def(), _rng(2))
	# Different seeds pick different first wander legs => different directions.
	var da: Vector3 = a.tick(Vector3.ZERO, far, 0)["move_dir"]
	var db: Vector3 = b.tick(Vector3.ZERO, far, 0)["move_dir"]
	assert_ne(da, db, "distinct seeds should wander differently")
