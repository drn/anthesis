## Deterministic planner that decides when and where Umbrals condense.
##
## SpawnSystem is pure logic: given the current tick, the player position, the
## live Umbral count, the set of glow points (flora props and active blooms),
## and a height-sampling [Callable], it returns the spawns to instantiate this
## planning round. It performs no scene-tree work and holds no node references,
## so it is fully unit-testable and reproducible for a given RNG stream.
##
## Umbrals only condense in darkness: candidate positions within
## [constant MIN_GLOW_DISTANCE] of any glow point are rejected. Planning only
## happens on tick multiples of [constant SPAWN_INTERVAL_TICKS], is capped at
## [constant POPULATION_CAP] live creatures, and emits at most one spawn per
## round. Candidate positions land on a ring [constant RING_MIN]..[constant
## RING_MAX] metres around the player at a random angle; ground height comes
## from the supplied [code]height_fn[/code], and a [code]NAN[/code] result
## rejects the candidate.
##
## All randomness flows through the [RandomNumberGenerator] handed to
## [method _init] (derived from a [WorldSeed] stream by the caller), so the same
## stream sequence always yields the same plan sequence.
class_name SpawnSystem
extends RefCounted

## Plan a spawning round only on ticks that are a multiple of this interval.
const SPAWN_INTERVAL_TICKS := 40
## Maximum number of simultaneously-alive Umbrals; planning yields nothing at
## or above this count.
const POPULATION_CAP := 6
## Candidates closer than this (metres, XZ plane) to any glow point are rejected
## — Umbrals only condense in the dark.
const MIN_GLOW_DISTANCE := 9.0
## Inner radius (metres) of the spawn ring around the player.
const RING_MIN := 20.0
## Outer radius (metres) of the spawn ring around the player.
const RING_MAX := 42.0

var _rng: RandomNumberGenerator
var _defs: Array[CreatureDef] = []


## Construct with a deterministic [param rng] stream and the creature [param
## defs] to spawn from. The defs array is copied; an empty array disables
## spawning.
func _init(rng: RandomNumberGenerator, defs: Array[CreatureDef]) -> void:
	_rng = rng
	_defs = defs.duplicate()


## Decide which Umbrals (if any) to spawn this planning round.
##
## Returns an array of [code]{def: CreatureDef, position: Vector3}[/code]
## dictionaries — empty when this tick is not a planning tick, the population
## cap is reached, no creature defs are configured, or the single candidate this
## round is rejected by the darkness rule or an invalid (NAN) ground height.
##
## [param tick] is the current simulation tick; [param player_pos] the player's
## world position; [param alive_count] the number of live Umbrals;
## [param glow_points] the world positions of light sources (flora props, active
## blooms); and [param height_fn] a [code]Callable(Vector3) -> float[/code] that
## returns ground height at a world position, or [constant @GDScript.NAN] when
## the column is invalid.
func plan(
	tick: int,
	player_pos: Vector3,
	alive_count: int,
	glow_points: Array[Vector3],
	height_fn: Callable
) -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	if tick % SPAWN_INTERVAL_TICKS != 0:
		return empty
	if alive_count >= POPULATION_CAP:
		return empty
	if _defs.is_empty():
		return empty

	# Draw order is fixed for determinism: angle, radius, species.
	var angle := _rng.randf_range(0.0, TAU)
	var radius := _rng.randf_range(RING_MIN, RING_MAX)
	var def := _defs[_rng.randi_range(0, _defs.size() - 1)]

	var x := player_pos.x + cos(angle) * radius
	var z := player_pos.z + sin(angle) * radius

	for glow in glow_points:
		var dx := x - glow.x
		var dz := z - glow.z
		if dx * dx + dz * dz < MIN_GLOW_DISTANCE * MIN_GLOW_DISTANCE:
			return empty

	var y: float = height_fn.call(Vector3(x, 0.0, z))
	if is_nan(y):
		return empty

	var out: Array[Dictionary] = []
	out.append({"def": def, "position": Vector3(x, y, z)})
	return out
