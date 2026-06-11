## Pure ferromantic physics — who gets shoved when steel meets steel.
##
## FerroKinetics is the math of Ferropull and Ferropush, separated from the scene so
## it can be unit-tested without a tree. Two pieces:
##
## [method select_source] picks the metal you're aiming at: of all candidates within
## [constant MAX_RANGE], the one most aligned with your aim (a [constant MIN_AIM_DOT]
## cone), ties broken by nearness.
##
## [method resolve] is Newton's third law with a Sanderson twist: when the source is
## anchored (bolted to the world) or heavier than you, YOU move toward/away from it;
## when it is lighter and free, IT flies. The mass ratio scales the impulse, clamped
## so neither a feather nor a mountain produces a degenerate shove.
class_name FerroKinetics
extends RefCounted

## The Ferromancer's mass, in the same units as a source's [code]metal_mass[/code].
const PLAYER_MASS := 80.0
## Maximum reach of a pull or push, in metres.
const MAX_RANGE := 24.0
## Minimum dot(aim, dir_to_source) to be "in the cone" — ~30 degrees half-angle.
const MIN_AIM_DOT := 0.866
## Lower / upper clamp on the mass-ratio impulse multiplier.
const MASS_RATIO_MIN := 0.3
const MASS_RATIO_MAX := 3.0


## Pick the metal source [param aim] is pointed at from [param candidates].
##
## A candidate qualifies if it is within [constant MAX_RANGE] of [param origin] and
## the direction to it has dot([param aim]) >= [constant MIN_AIM_DOT]. Among those,
## the highest dot wins (most centred in the cone); ties go to the nearest. Returns
## null when nothing qualifies. [param candidates] are Node3D-likes exposing a
## [code]global_position[/code] (or [code]position[/code]).
static func select_source(origin: Vector3, aim: Vector3, candidates: Array) -> Node3D:
	var aim_n := aim.normalized()
	var best: Node3D = null
	var best_dot := -1.0
	var best_dist := INF
	for candidate: Node3D in candidates:
		if candidate == null:
			continue
		var to_source := candidate.global_position - origin
		var dist := to_source.length()
		if dist > MAX_RANGE or dist <= 0.0:
			continue
		var dot := aim_n.dot(to_source / dist)
		if dot < MIN_AIM_DOT:
			continue
		if dot > best_dot or (is_equal_approx(dot, best_dot) and dist < best_dist):
			best = candidate
			best_dot = dot
			best_dist = dist
	return best


## Resolve the impulses of a pull/push between the Ferromancer and a source.
##
## Returns [code]{"player_impulse": Vector3, "source_impulse": Vector3}[/code].
## [param line] runs origin -> source. When the source is [param anchored] or at
## least [constant PLAYER_MASS] heavy, the PLAYER moves: toward the source for
## [param pull], away for push, scaled by clampf(source_mass / PLAYER_MASS, …); the
## source stays put. Otherwise (light, unanchored) the SOURCE flies: toward the
## player for pull, away for push, scaled by clampf(PLAYER_MASS / source_mass, …);
## the player stays put.
static func resolve(
	origin: Vector3,
	source_pos: Vector3,
	source_mass: float,
	anchored: bool,
	magnitude: float,
	pull: bool
) -> Dictionary:
	var line := (source_pos - origin).normalized()
	if anchored or source_mass >= PLAYER_MASS:
		var scale := clampf(source_mass / PLAYER_MASS, MASS_RATIO_MIN, MASS_RATIO_MAX)
		var dir := line if pull else -line
		return {
			"player_impulse": dir * magnitude * scale,
			"source_impulse": Vector3.ZERO,
		}
	var scale := clampf(PLAYER_MASS / maxf(source_mass, 0.01), MASS_RATIO_MIN, MASS_RATIO_MAX)
	var dir := -line if pull else line
	return {
		"player_impulse": Vector3.ZERO,
		"source_impulse": dir * magnitude * scale,
	}
