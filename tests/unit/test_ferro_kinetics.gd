extends GutTest

## Exercises [FerroKinetics] pure math: cone selection (highest dot, tie -> nearest),
## range cutoff, and resolve()'s anchored-vs-light branches with pull/push directions.


## Minimal metal-source double: a Node3D with metal_mass + is_metal_anchored (the #7
## protocol). select_source reads global_position, so these live in the tree.
class FakeSource:
	extends Node3D

	var metal_mass: float = 1.0
	var anchored: bool = false

	func is_metal_anchored() -> bool:
		return anchored


func _source(pos: Vector3, mass := 1.0, anchored := false) -> FakeSource:
	var s := FakeSource.new()
	add_child_autofree(s)
	s.global_position = pos
	s.metal_mass = mass
	s.anchored = anchored
	return s


# ---------------------------------------------------------------------------
# select_source
# ---------------------------------------------------------------------------


func test_select_returns_null_when_empty() -> void:
	assert_null(FerroKinetics.select_source(Vector3.ZERO, Vector3.FORWARD, []))


func test_select_rejects_out_of_range() -> void:
	var far := _source(Vector3(0, 0, -FerroKinetics.MAX_RANGE - 1.0))
	assert_null(FerroKinetics.select_source(Vector3.ZERO, Vector3.FORWARD, [far]))


func test_select_rejects_outside_cone() -> void:
	# Directly to the side: dot(aim, dir) == 0 < MIN_AIM_DOT.
	var side := _source(Vector3(5, 0, 0))
	assert_null(FerroKinetics.select_source(Vector3.ZERO, Vector3.FORWARD, [side]))


func test_select_picks_highest_dot() -> void:
	var aim := Vector3.FORWARD  # (0,0,-1)
	var centred := _source(Vector3(0, 0, -5))  # dot 1.0
	var off := _source(Vector3(2, 0, -5))  # dot < 1.0 but in cone
	var picked := FerroKinetics.select_source(Vector3.ZERO, aim, [off, centred])
	assert_eq(picked, centred)


func test_select_tie_breaks_on_nearest() -> void:
	var aim := Vector3.FORWARD
	var near := _source(Vector3(0, 0, -3))  # dot 1.0
	var far := _source(Vector3(0, 0, -9))  # dot 1.0, farther
	var picked := FerroKinetics.select_source(Vector3.ZERO, aim, [far, near])
	assert_eq(picked, near)


# ---------------------------------------------------------------------------
# resolve — anchored / heavy: player moves
# ---------------------------------------------------------------------------


func test_resolve_anchored_pull_moves_player_toward_source() -> void:
	var origin := Vector3.ZERO
	var src := Vector3(0, 0, -10)  # line = (0,0,-1)
	var out := FerroKinetics.resolve(origin, src, 400.0, true, 9.0, true)
	assert_eq(out["source_impulse"], Vector3.ZERO)
	# anchored -> clamp(400/80=5 -> MASS_RATIO_MAX 3.0); pull = +line.
	assert_eq(out["player_impulse"], Vector3(0, 0, -1) * 9.0 * FerroKinetics.MASS_RATIO_MAX)


func test_resolve_anchored_push_moves_player_away() -> void:
	var out := FerroKinetics.resolve(Vector3.ZERO, Vector3(0, 0, -10), 400.0, true, 11.0, false)
	# push = -line = (0,0,+1).
	assert_eq(out["player_impulse"], Vector3(0, 0, 1) * 11.0 * FerroKinetics.MASS_RATIO_MAX)
	assert_eq(out["source_impulse"], Vector3.ZERO)


func test_resolve_heavy_unanchored_moves_player() -> void:
	# Heavier than PLAYER_MASS but not anchored -> player still moves.
	var out := FerroKinetics.resolve(Vector3.ZERO, Vector3(10, 0, 0), 80.0, false, 9.0, true)
	assert_ne(out["player_impulse"], Vector3.ZERO)
	assert_eq(out["source_impulse"], Vector3.ZERO)


# ---------------------------------------------------------------------------
# resolve — light, unanchored: source moves
# ---------------------------------------------------------------------------


func test_resolve_light_pull_moves_source_toward_player() -> void:
	var out := FerroKinetics.resolve(Vector3.ZERO, Vector3(0, 0, -10), 0.4, false, 9.0, true)
	assert_eq(out["player_impulse"], Vector3.ZERO)
	# light -> clamp(80/0.4=200 -> MAX 3.0); pull = -line = (0,0,+1) toward player.
	assert_eq(out["source_impulse"], Vector3(0, 0, 1) * 9.0 * FerroKinetics.MASS_RATIO_MAX)


func test_resolve_light_push_moves_source_away() -> void:
	var out := FerroKinetics.resolve(Vector3.ZERO, Vector3(0, 0, -10), 0.4, false, 11.0, false)
	assert_eq(out["player_impulse"], Vector3.ZERO)
	# push = +line = (0,0,-1) away from player.
	assert_eq(out["source_impulse"], Vector3(0, 0, -1) * 11.0 * FerroKinetics.MASS_RATIO_MAX)


func test_resolve_mass_ratio_clamps_low() -> void:
	# Anchored, very light source: clamp(0.4/80 -> MASS_RATIO_MIN 0.3).
	var out := FerroKinetics.resolve(Vector3.ZERO, Vector3(0, 0, -10), 0.4, true, 9.0, true)
	assert_eq(out["player_impulse"], Vector3(0, 0, -1) * 9.0 * FerroKinetics.MASS_RATIO_MIN)
