## Pure spatial→step mapping for the in-world sequencer (Phase 6 contract #2).
##
## The signature trick of the sequencer is that a Note Block's ANGLE around its
## [SequencerCore] picks which of the 16 loop steps it plays: the spatial
## arrangement of crystals IS the rhythm. SectorMath is the pure geometry that
## turns a block's offset from the core into that step index.
##
## North (toward -Z) is step 0; angle increases clockwise (toward +X = east),
## so the steps sweep clockwise around the core. Each sector spans 2*PI/steps
## radians; offsets are bucketed by rounding the wrapped angle to the nearest
## sector centre so the mapping is stable right at sector boundaries.
##
## No engine deps beyond [Vector3] math — fully unit-testable.
class_name SectorMath
extends RefCounted


## Step index (0..steps-1) for a Note Block sitting at [param offset] from its
## core (offset = block.global_position - core.global_position).
##
## Only the XZ plane matters (Y is ignored). The angle is measured as
## atan2(x, -z): with x=0, z<0 (due north) this is 0; rotating toward +X (east)
## increases it, giving a clockwise sweep. The angle is normalised into
## [0, 2*PI) with [method @GlobalScope.wrapf], divided into [param steps]
## sectors, and rounded to the nearest sector so a block exactly on a boundary
## resolves deterministically rather than flickering between two steps.
static func step_for_offset(offset: Vector3, steps := 16) -> int:
	var count := maxi(steps, 1)
	# atan2(x, -z): north (-Z) -> 0, east (+X) -> +PI/2, clockwise ascending.
	var angle := atan2(offset.x, -offset.z)
	# Normalise to [0, TAU) so negative angles (west/north-west) wrap forward.
	angle = wrapf(angle, 0.0, TAU)
	var sector := TAU / count
	# Round (not floor) so boundaries snap to the nearest sector centre; wrap the
	# top sector (which can round up to `count`) back to 0.
	var index := int(round(angle / sector)) % count
	return index
