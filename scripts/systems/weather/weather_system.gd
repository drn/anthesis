## Resonance Storm scheduler — the deterministic weather clock.
##
## The sky over Anthesis breathes in a fixed rhythm: long stretches of [code]calm[/code],
## then a [code]warning[/code] (the sky bruises violet, the music drops to a pulse), then
## the [code]storm[/code] itself — a Resonance Storm that pulses every [constant
## PULSE_INTERVAL] ticks, charging dun gems racked under open sky and battering anything
## exposed. When the storm passes, calm returns and the clock rolls a fresh gap.
##
## The schedule is fully deterministic: the gap before each storm is drawn ONLY from the
## injected [RandomNumberGenerator] (a [WorldSeed] stream), so two systems built from the
## same seed march through an identical sequence of transitions forever. No wall-clock, no
## bare [code]randf()[/code] / [code]randi()[/code].
##
## A scene-tree [Node] so the per-tick wiring it lives on cannot be garbage-collected out
## from under the [SimulationClock].
class_name WeatherSystem
extends Node

## Emitted on every state transition (NOT at setup). Payload is the new state:
## &"calm", &"warning", or &"storm".
signal weather_changed(state: StringName)

## Emitted once per storm pulse while in &"storm" — every [constant PULSE_INTERVAL] ticks.
## [param pulse_index] increments from 0 at the first pulse of each storm.
signal storm_pulse(pulse_index: int)

## Ticks the warning phase lasts (45 s at 10 ticks/s).
const WARNING_TICKS := 450
## Ticks the storm phase lasts (90 s at 10 ticks/s).
const STORM_TICKS := 900
## Minimum / maximum calm gap before the next storm (6–10 min at 10 ticks/s).
const STORM_MIN_GAP_TICKS := 3600
const STORM_MAX_GAP_TICKS := 6000
## Ticks between storm pulses (2 s at 10 ticks/s).
const PULSE_INTERVAL := 20

var _rng: RandomNumberGenerator
var _state: StringName = &"calm"
## Ticks remaining in the current phase before it transitions.
var _remaining: int = 0
## Ticks elapsed in the current storm, used to schedule pulses.
var _storm_elapsed: int = 0
## Pulses already emitted in the current storm (also the next pulse_index).
var _pulse_count: int = 0
## Set true by [method force_storm] so the next calm→warning uses a 10-tick warning.
var _forced_warning: bool = false


## Bind the deterministic [param rng] stream and roll the first calm gap.
## World passes [code]WorldSeed.derive("weather")[/code]. Does not emit
## [signal weather_changed].
func setup(rng: RandomNumberGenerator) -> void:
	_rng = rng
	_state = &"calm"
	_remaining = _roll_gap()
	_storm_elapsed = 0
	_pulse_count = 0


## The current weather state — starts &"calm".
func state() -> StringName:
	return _state


## Ticks of calm left before the next warning begins. Informational; returns 0
## once a storm is already warning or raging.
func ticks_until_storm() -> int:
	if _state == &"calm":
		return _remaining
	return 0


## Debug / harness hook: force the next [method on_tick] to enter &"warning"
## with a short 10-tick warning, so a storm can be summoned on demand.
func force_storm() -> void:
	_state = &"calm"
	_remaining = 1
	_forced_warning = true


## Advance the weather clock one simulation tick. Wire to
## [signal SimulationClock.ticked]. Drives all transitions and storm pulses.
func on_tick(_tick: int) -> void:
	match _state:
		&"calm":
			_tick_calm()
		&"warning":
			_tick_warning()
		&"storm":
			_tick_storm()


func _tick_calm() -> void:
	_remaining -= 1
	if _remaining > 0:
		return
	_enter_warning()


func _tick_warning() -> void:
	_remaining -= 1
	if _remaining > 0:
		return
	_enter_storm()


func _tick_storm() -> void:
	_storm_elapsed += 1
	# Pulse every PULSE_INTERVAL ticks: pulses at ticks 20, 40, ... 900 → 45 pulses.
	if _storm_elapsed % PULSE_INTERVAL == 0:
		storm_pulse.emit(_pulse_count)
		_pulse_count += 1
	_remaining -= 1
	if _remaining > 0:
		return
	_enter_calm()


func _enter_warning() -> void:
	_state = &"warning"
	_remaining = 10 if _forced_warning else WARNING_TICKS
	_forced_warning = false
	weather_changed.emit(_state)


func _enter_storm() -> void:
	_state = &"storm"
	_remaining = STORM_TICKS
	_storm_elapsed = 0
	_pulse_count = 0
	weather_changed.emit(_state)


func _enter_calm() -> void:
	_state = &"calm"
	_remaining = _roll_gap()
	weather_changed.emit(_state)


## Draw the next calm gap from the injected stream only. Falls back to the
## minimum gap if no rng was supplied (defensive; setup always supplies one).
func _roll_gap() -> int:
	if _rng == null:
		return STORM_MIN_GAP_TICKS
	return _rng.randi_range(STORM_MIN_GAP_TICKS, STORM_MAX_GAP_TICKS)
