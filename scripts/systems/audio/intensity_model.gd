## Game-intensity signal driving adaptive music stem mixing.
##
## IntensityModel is a pure, deterministic accumulator of "heat". Gameplay
## events ([method on_event]) add heat immediately, raising the intensity
## [method level] toward 1.0. Each simulation tick ([method tick]) decays the
## level back toward 0 by a fixed amount, so intensity naturally cools when the
## action stops. The level is always clamped to [code][0.0, 1.0][/code].
##
## The model is the single source of truth for "how intense is the moment"; the
## MusicSystem reads [method level] to crossfade stems in and out. It is
## intentionally free of any node, signal, RNG, or wall-clock dependency: given
## the same sequence of [method on_event] and [method tick] calls it always
## produces the same level, which keeps the soundtrack reproducible and testable.
##
## Heat is added the instant an event arrives (and clamped), so the level can
## react within a single frame. Decay happens only in [method tick], pacing the
## cooldown to the simulation clock (10 Hz) rather than the render frame rate.
class_name IntensityModel
extends RefCounted

## Heat contributed by each known event kind, added immediately on [method
## on_event]. Larger values mean a stronger, more immediate spike in intensity.
## Event kinds not present here are ignored.
const HEAT := {
	&"combat_hit": 0.35,
	&"player_hurt": 0.45,
	&"enemy_near": 0.12,
	&"dig": 0.06,
	&"cast": 0.15,
	&"harvest": 0.04,
}

## Amount the level decays per [method tick]. At the simulation rate of 10 Hz
## this is roughly 0.12 intensity lost per second when no events arrive.
const DECAY_PER_TICK := 0.012

## Current intensity, in [code][0.0, 1.0][/code]. Starts at 0.0.
var _level := 0.0


## Construct a model at zero intensity. Takes no arguments and seeds no state.
func _init() -> void:
	_level = 0.0


## The current intensity, always within [code][0.0, 1.0][/code]. Starts at 0.0.
func level() -> float:
	return _level


## Apply the heat for event [param kind], immediately raising the level.
##
## Known kinds (see [constant HEAT]) add their heat and the level is clamped to
## at most 1.0. Unknown kinds are ignored and leave the level unchanged. No
## decay happens here — decay is applied only in [method tick].
func on_event(kind: StringName) -> void:
	if not HEAT.has(kind):
		return
	_level = clampf(_level + HEAT[kind], 0.0, 1.0)


## Advance one simulation tick, decaying the level toward 0.
##
## Subtracts [constant DECAY_PER_TICK] and floors the result at 0.0 so the level
## never goes negative. Adds no heat; only [method on_event] does that.
func tick() -> void:
	_level = clampf(_level - DECAY_PER_TICK, 0.0, 1.0)
