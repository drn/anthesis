## Pure musical-grid model for the in-world sequencer (Phase 6 contract #1).
##
## StepTimeline turns a playback position in seconds into a step index on a
## looping bar, and reports which step boundaries a span of time crossed. It is
## the timing brain shared by every [SequencerCore]: the core reads the live
## adaptive-music transport (the synced stem players' playback position) and
## asks the timeline which steps fired since the previous frame, so player
## compositions ride the same 110 BPM grid as the soundtrack.
##
## The defaults model one bar of 4/4 as 16 sixteenth-notes: at 110 BPM each beat
## is 60/110 s and each step is a quarter of that (60/110/4). [param subdivision]
## is "steps per beat", so 16 steps over 4 beats is 4 steps/beat = sixteenths.
##
## This class has NO engine dependencies (no nodes, no audio, no RNG): everything
## is derived arithmetically from (bpm, steps, subdivision), which makes the loop
## timing exhaustively unit-testable in isolation.
class_name StepTimeline
extends RefCounted

## Beats per minute the grid is locked to. 110 matches the soundtrack tempo.
var bpm: float
## Number of steps in one loop (the bar). 16 by default.
var steps: int
## Steps per beat. 4 means each step is a sixteenth note in 4/4.
var subdivision: float


## Build a timeline. Defaults model a 16-step (sixteenth-note) bar at 110 BPM.
## Inputs are floored/guarded so degenerate values never divide by zero or
## produce a non-positive loop: [param bpm] and [param subdivision] clamp to a
## tiny positive epsilon and [param steps] clamps to at least 1.
func _init(bpm := 110.0, steps := 16, subdivision := 4) -> void:
	self.bpm = maxf(bpm, 0.0001)
	self.steps = maxi(steps, 1)
	self.subdivision = maxf(float(subdivision), 0.0001)


## Seconds occupied by a single step: 60 / bpm / subdivision.
func step_duration() -> float:
	return 60.0 / bpm / subdivision


## Seconds for one full loop of all [member steps] steps.
func loop_duration() -> float:
	return steps * step_duration()


## The step index (0..steps-1) active at [param playback_s].
##
## The position is wrapped into [0, loop_duration) so any absolute transport
## time maps onto the bar, then floored to a step and clamped defensively so
## floating-point edge cases at the loop boundary never escape the valid range.
func step_at(playback_s: float) -> int:
	var loop := loop_duration()
	if loop <= 0.0:
		return 0
	var wrapped := fposmod(playback_s, loop)
	var index := int(floor(wrapped / step_duration()))
	return clampi(index, 0, steps - 1)


## Ordered list of step indices whose boundaries were crossed in the half-open
## interval (prev_s, now_s].
##
## "Crossing a boundary" means entering a step: the index returned is the step
## that becomes active. The list is in playback order and handles three cases:
## staying in the same step (empty), a forward jump spanning several steps
## (every intermediate step, in order), and a loop wrap where now_s < prev_s
## (the tail of the bar followed by the head). Equal inputs return empty.
func steps_crossed(prev_s: float, now_s: float) -> Array[int]:
	var crossed: Array[int] = []
	var loop := loop_duration()
	if loop <= 0.0:
		return crossed
	var dur := step_duration()
	# How far we advanced along the (possibly wrapping) timeline, in seconds.
	var delta := now_s - prev_s
	if delta == 0.0:
		return crossed
	if delta < 0.0:
		# A wrap (now < prev) covers the remaining distance to loop end plus now.
		delta += loop
	# Count whole step-boundaries strictly after prev up to and including now.
	# The first boundary after prev sits at floor(prev/dur)+1 steps.
	var prev_wrapped := fposmod(prev_s, loop)
	var first_index := int(floor(prev_wrapped / dur)) + 1
	# Number of boundaries within the advanced span. A span of exactly N step
	# durations crosses N boundaries.
	var boundary_count := int(floor((prev_wrapped + delta) / dur)) - int(floor(prev_wrapped / dur))
	for i in range(boundary_count):
		var step_index := (first_index + i) % steps
		crossed.append(step_index)
	return crossed
