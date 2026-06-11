## Pure axis-snapping math for the Tempestlight lashes.
##
## A Skylash redirects the player's personal gravity along a single world axis;
## the v1 lashes are deliberately axis-aligned (the player picks "that way" and
## falls toward the nearest cardinal direction). [method snap_axis] collapses an
## arbitrary aim vector down to the dominant signed unit axis: a forward look of
## roughly straight up becomes [constant Vector3.UP], a glance at the floor
## becomes [constant Vector3.DOWN], and so on for the four horizontal faces.
##
## Pure [RefCounted] with only static math — no node, no tree, fully
## unit-testable without a Godot binary.
class_name LashMath
extends RefCounted

## Below this magnitude an aim vector carries no usable direction.
const EPSILON := 0.0001


## Collapse [param dir] to the dominant signed world axis as a unit vector.
##
## Compares the absolute components of [param dir]; the largest wins, and the
## result keeps that component's sign (e.g. [code](0.2, 0.7, -0.1)[/code] →
## [constant Vector3.UP]). A zero or near-zero input has no usable direction and
## falls back to [constant Vector3.DOWN] (normal gravity).
static func snap_axis(dir: Vector3) -> Vector3:
	var ax := absf(dir.x)
	var ay := absf(dir.y)
	var az := absf(dir.z)
	if maxf(ax, maxf(ay, az)) < EPSILON:
		return Vector3.DOWN
	if ay >= ax and ay >= az:
		return Vector3.UP if dir.y > 0.0 else Vector3.DOWN
	if ax >= az:
		return Vector3.RIGHT if dir.x > 0.0 else Vector3.LEFT
	return Vector3.BACK if dir.z > 0.0 else Vector3.FORWARD
