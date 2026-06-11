## Fixed-timestep simulation heartbeat for tick-based gameplay.
##
## SimulationClock decouples gameplay simulation from the render frame rate.
## It accumulates real frame time in [method _process] and emits [signal ticked]
## once per fixed simulation step ([member ticks_per_second]), advancing
## [member tick_index] by exactly one each emission. A single render frame may
## fire several ticks (when the frame was long) or none (when it was short);
## the accumulator carries the remainder forward so the long-run tick rate stays
## true to [member ticks_per_second].
##
## Determinism: ticks always start at index 0 and increment by exactly 1 per
## emission, so a fixed sequence of [code]delta[/code] values always produces the
## same tick stream. To keep a single huge frame (or a debugger pause) from
## triggering a runaway "spiral of death", at most [constant MAX_TICKS_PER_FRAME]
## ticks fire in one [method _process] call; surplus accumulated time is dropped.
##
## Magic and other simulation systems read [method current_tick] to gate
## cooldowns and schedule effects. It deliberately runs in [method _process] (not
## [method _physics_process]) so the tick rate is independent of the physics
## step and can be paused without freezing physics.
class_name SimulationClock
extends Node

## Emitted once per fixed simulation step. [param tick_index] is monotonic,
## starts at 0, and increments by exactly 1 per emission.
signal ticked(tick_index: int)

## Hard cap on how many ticks may fire within a single [method _process] call.
## Prevents a long frame from cascading into an unbounded catch-up loop.
const MAX_TICKS_PER_FRAME := 10

## Simulation ticks per second. Drives the fixed timestep; the seconds-per-tick
## interval is its reciprocal.
@export var ticks_per_second := 10.0

## Index of the most recently emitted tick. Starts at -1 (no tick emitted yet);
## the first emission carries index 0. Read via [method current_tick].
var _tick_index := -1

## Carried-over real time not yet consumed by a tick, in seconds.
var _accumulator := 0.0

## Whether the clock is paused. While paused, [method _process] accumulates
## nothing and emits nothing.
var _paused := false


## The index of the most recently emitted tick, or -1 before the first tick.
##
## During a [signal ticked] handler this equals the index just emitted, so a
## handler reading [method current_tick] sees the tick it is being notified of.
func current_tick() -> int:
	return _tick_index


## Advance the accumulator by [param delta] seconds and emit any whole ticks.
##
## Fires at most [constant MAX_TICKS_PER_FRAME] ticks per call; if more time has
## accumulated than that cap allows, the surplus is discarded so the simulation
## cannot enter a catch-up spiral. Does nothing while paused or when
## [member ticks_per_second] is non-positive.
func _process(delta: float) -> void:
	if _paused or ticks_per_second <= 0.0:
		return
	var seconds_per_tick := 1.0 / ticks_per_second
	_accumulator += delta
	var fired := 0
	while _accumulator >= seconds_per_tick and fired < MAX_TICKS_PER_FRAME:
		_accumulator -= seconds_per_tick
		_tick_index += 1
		fired += 1
		ticked.emit(_tick_index)
	# Drop surplus time beyond the per-frame cap so a single huge frame cannot
	# queue an unbounded backlog of future ticks.
	if _accumulator >= seconds_per_tick:
		_accumulator = fmod(_accumulator, seconds_per_tick)


## Pause the clock. Accumulated time is preserved; no ticks fire until resumed.
func pause() -> void:
	_paused = true


## Resume a paused clock. The accumulator continues from where it was.
func resume() -> void:
	_paused = false


## Whether the clock is currently paused.
func is_paused() -> bool:
	return _paused
