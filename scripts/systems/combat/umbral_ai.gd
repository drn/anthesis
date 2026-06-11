## Pure-logic state machine driving an Umbral's behaviour each simulation tick.
##
## UmbralAI is the deterministic brain shared by every shadow-wisp enemy. It
## holds no scene-tree references and performs no movement itself: each tick it
## is handed the current self/target positions and the tick index, and returns a
## plain [Dictionary] describing the desired state, movement direction, and
## whether an attack lands. The owning [Umbral] node turns that decision into
## physics. Keeping the logic pure makes the whole behaviour unit-testable and
## replayable.
##
## The five states form a simple distance-driven machine:
## [br]- [code]&"dead"[/code]: terminal; set by [method mark_dead], never leaves.
## [br]- [code]&"wander"[/code]: target is beyond [member CreatureDef.aggro_range].
##   The wisp drifts between random "legs" — every [constant WANDER_LEG_TICKS]
##   ticks it picks a fresh offset within [member CreatureDef.wander_radius] of
##   its home (the position it first saw), idling once it arrives.
## [br]- [code]&"idle"[/code]: a wander leg whose goal has been reached; no motion
##   until the next leg is chosen.
## [br]- [code]&"chase"[/code]: target within aggro range but beyond attack range;
##   move straight toward it on the XZ plane.
## [br]- [code]&"attack"[/code]: target within [member CreatureDef.attack_range].
##   [code]attack[/code] is true only on ticks where the attack cooldown has
##   elapsed since the last landed strike; that tick is then recorded.
##
## All randomness flows through the injected [RandomNumberGenerator], so two AIs
## fed the same seed and the same tick/position inputs make identical decisions.
class_name UmbralAI
extends RefCounted

## Ticks between picking successive wander legs while out of aggro range.
const WANDER_LEG_TICKS := 30
## Distance (m) at which a wander leg counts as "arrived", flipping to idle.
const WANDER_ARRIVE_DISTANCE := 0.6

var _def: CreatureDef
var _rng: RandomNumberGenerator

## Current state tag; one of idle/wander/chase/attack/dead.
var _state: StringName = &"idle"
## Whether [method mark_dead] has been called. Once true the AI is terminal.
var _dead := false

## The position the wisp first observed, used as the centre of its wander.
## NAN-flagged via [member _home_set] until the first tick establishes it.
var _home := Vector3.ZERO
var _home_set := false

## Current wander destination on the XZ plane (y ignored).
var _wander_goal := Vector3.ZERO
## Tick index at which the current wander leg was chosen; -1 before any leg.
var _wander_leg_tick := -1

## Tick index of the most recent landed attack; far-negative so the first
## in-range tick can always strike.
var _last_attack_tick := -1000000


## Construct an AI for [param def], drawing wander randomness from [param rng].
func _init(def: CreatureDef, rng: RandomNumberGenerator) -> void:
	_def = def
	_rng = rng


## The current state tag (idle/wander/chase/attack/dead).
func state() -> StringName:
	return _state


## Mark this AI permanently dead. All subsequent ticks return the dead decision.
func mark_dead() -> void:
	_dead = true
	_state = &"dead"


## Advance the AI one simulation tick and return its decision.
##
## [param self_pos] / [param target_pos] are world positions; [param tick_index]
## is the monotonic simulation tick. Returns a Dictionary with:
## [br]- [code]state[/code] ([StringName]): the resolved state this tick;
## [br]- [code]move_dir[/code] ([Vector3]): desired motion, normalized on XZ
##   (zero when idle/attacking/dead);
## [br]- [code]attack[/code] ([bool]): true only on the tick a strike lands.
func tick(self_pos: Vector3, target_pos: Vector3, tick_index: int) -> Dictionary:
	if _dead:
		return {"state": &"dead", "move_dir": Vector3.ZERO, "attack": false}

	if not _home_set:
		_home = self_pos
		_home_set = true

	var to_target := target_pos - self_pos
	var dist := Vector2(to_target.x, to_target.z).length()

	if dist <= _def.attack_range:
		return _attack_decision(tick_index)
	if dist <= _def.aggro_range:
		return _chase_decision(to_target)
	return _wander_decision(self_pos, tick_index)


func _attack_decision(tick_index: int) -> Dictionary:
	_state = &"attack"
	var ready: bool = tick_index - _last_attack_tick >= _def.attack_cooldown_ticks
	if ready:
		_last_attack_tick = tick_index
	return {"state": &"attack", "move_dir": Vector3.ZERO, "attack": ready}


func _chase_decision(to_target: Vector3) -> Dictionary:
	_state = &"chase"
	return {"state": &"chase", "move_dir": _flatten(to_target), "attack": false}


func _wander_decision(self_pos: Vector3, tick_index: int) -> Dictionary:
	# Pick a fresh leg on the first wander tick and every WANDER_LEG_TICKS after.
	if _wander_leg_tick < 0 or tick_index - _wander_leg_tick >= WANDER_LEG_TICKS:
		_choose_wander_leg(tick_index)

	var to_goal := _wander_goal - self_pos
	var planar := Vector2(to_goal.x, to_goal.z).length()
	if planar <= WANDER_ARRIVE_DISTANCE:
		# Arrived at this leg's goal: idle until the next leg is chosen.
		_state = &"idle"
		return {"state": &"idle", "move_dir": Vector3.ZERO, "attack": false}

	_state = &"wander"
	return {"state": &"wander", "move_dir": _flatten(to_goal), "attack": false}


## Choose a new wander goal within wander_radius of home and record its tick.
func _choose_wander_leg(tick_index: int) -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var radius := _rng.randf_range(0.0, _def.wander_radius)
	_wander_goal = _home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_wander_leg_tick = tick_index


## Flatten [param v] onto the XZ plane and normalize; zero stays zero.
func _flatten(v: Vector3) -> Vector3:
	var planar := Vector3(v.x, 0.0, v.z)
	if planar.length() < 0.0001:
		return Vector3.ZERO
	return planar.normalized()
