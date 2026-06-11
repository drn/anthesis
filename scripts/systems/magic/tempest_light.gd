## The held-light pool of a Tempest — Anthesis's Stormlight-style investiture.
##
## Where Lumen is gathered and spent in instant bursts and metals are burned in
## sustained channels, Tempestlight is *held*: the player inhales a charged gem
## (storm-charged in a [StormCatcher]), filling a pool that then leaks away
## second by second. While any light is held the player glows, moves faster, and
## the well slowly knits wounds shut. When the last of it drains the glow dies
## and the boons lapse — the Sanderson-style limitation is that the power is a
## visible, dwindling clock, never a reserve you can sit on.
##
## The pool itself is a [LumenWell] (capacity [constant CAPACITY], starting
## empty). [method on_tick] runs the per-tick economy: leak, periodic healing
## regen, and the edge-triggered [code]&"tempest"[/code] status that drives the
## speed boon and glow. A scene-tree [Node] so its per-tick wiring is owned by
## the tree and survives GC.
class_name TempestLight
extends Node

## Emitted when the held light crosses the empty boundary in either direction:
## [code]true[/code] when the well goes from empty to holding, [code]false[/code]
## when it drains back to empty.
signal holding_changed(active: bool)

## Effect id for the held-light status (speed boon + glow gate).
const TEMPEST_STATUS := &"tempest"

## Maximum Tempestlight the pool can hold.
const CAPACITY := 100.0
## Charge gained from inhaling a single charged gem.
const INHALE_CHARGE := 40.0
## Tempestlight lost to leak every tick (1.0/s at 10 ticks/s; one gem ≈ 40 s).
const LEAK_PER_TICK := 0.1
## How often (in ticks) the healing regen pulse fires.
const REGEN_INTERVAL_TICKS := 10
## Tempestlight spent per healing regen pulse.
const REGEN_COST := 2.0
## Hit points restored per healing regen pulse.
const REGEN_AMOUNT := 1.0
## Speed multiplier applied while holding light.
const SPEED_BONUS := 1.2
## OmniLight energy at full pool (scaled by fill ratio each tick).
const GLOW_MAX_ENERGY := 3.0

var _well: LumenWell = LumenWell.new(CAPACITY)
var _status: StatusEffectSystem
var _health: Health
var _target_id: Callable
var _glow: Light3D
var _speed_modifier: Callable
## Tracks the holding edge so the status applies / clears exactly once per cross.
var _holding := false


## Wire the pool to its collaborators.
##
## [param status] tracks the [code]&"tempest"[/code] effect; [param health] is
## the pool whose wounds the regen knits; [param target_id] resolves the player's
## instance id at call time (so the status keys correctly even if the player is
## built lazily); [param glow] is the player's [OmniLight3D] (may be null in
## headless tests); [param speed_modifier] is the integrator closure that
## sets / clears the [code]&"tempest"[/code] entry in World's speed-modifier
## table — it is called [code](true)[/code] on apply and [code](false)[/code] on
## expire.
func setup(
	status: StatusEffectSystem,
	health: Health,
	target_id: Callable,
	glow: Light3D,
	speed_modifier: Callable
) -> void:
	_status = status
	_health = health
	_target_id = target_id
	_glow = glow
	_speed_modifier = speed_modifier
	_update_glow()


## The backing [LumenWell] (capacity [constant CAPACITY], starts empty).
func well() -> LumenWell:
	return _well


## Inhale one charged gem from [param inventory], returning whether it happened.
##
## Requires at least one [code]&"charged_gem"[/code]: removes it, adds
## [constant INHALE_CHARGE] to the pool, and returns one spent [code]&"dun_gem"[/code]
## to the pouch. A null [param inventory] or an empty stock returns
## [code]false[/code] and changes nothing. The holding edge (and glow / status)
## is reconciled immediately.
func inhale(inventory: Object) -> bool:
	if inventory == null:
		return false
	if inventory.count_of(&"charged_gem") <= 0:
		return false
	inventory.remove(&"charged_gem", 1)
	_well.add(INHALE_CHARGE)
	inventory.add(&"dun_gem", 1)
	_reconcile()
	return true


## Per-tick economy (wire to [signal SimulationClock.ticked]).
##
## In order: leak [constant LEAK_PER_TICK] (capped at what remains); every
## [constant REGEN_INTERVAL_TICKS] ticks, if the player is hurt and the pool can
## afford [constant REGEN_COST], spend it to heal [constant REGEN_AMOUNT]; then
## reconcile the holding edge (status apply / clear, [signal holding_changed])
## and refresh the glow to [constant GLOW_MAX_ENERGY] × fill ratio.
func on_tick(tick: int) -> void:
	var leak := minf(LEAK_PER_TICK, _well.current())
	if leak > 0.0:
		_well.spend(leak)
	if tick % REGEN_INTERVAL_TICKS == 0:
		_regen()
	_reconcile()


## Spend a regen pulse to knit one wound, if affordable and the player is hurt.
func _regen() -> void:
	if _health == null:
		return
	if _health.current() >= _health.max_health():
		return
	if not _well.can_afford(REGEN_COST):
		return
	if _well.spend(REGEN_COST):
		_health.heal(REGEN_AMOUNT)


## Reconcile the holding edge and refresh the glow.
##
## When the pool crosses from empty to holding, applies the indefinite
## [code]&"tempest"[/code] status (its on_apply / on_expire drive the speed
## modifier) and emits [signal holding_changed] [code](true)[/code]. When it
## drains to empty, clears the status (firing on_expire) and emits
## [code](false)[/code].
func _reconcile() -> void:
	var holding := _well.current() > 0.0
	if holding and not _holding:
		_holding = true
		_apply_status()
		holding_changed.emit(true)
	elif not holding and _holding:
		_holding = false
		_clear_status()
		holding_changed.emit(false)
	_update_glow()


func _apply_status() -> void:
	if _status == null or not _target_id.is_valid():
		return
	var tid: int = _target_id.call()
	_status.apply(
		tid,
		TEMPEST_STATUS,
		0,
		func() -> void: _set_speed_mod(true),
		func() -> void: _set_speed_mod(false)
	)


func _clear_status() -> void:
	if _status == null or not _target_id.is_valid():
		return
	var tid: int = _target_id.call()
	_status.clear(tid, TEMPEST_STATUS)


func _set_speed_mod(active: bool) -> void:
	if _speed_modifier.is_valid():
		_speed_modifier.call(active)


func _update_glow() -> void:
	if _glow == null:
		return
	var ratio := _well.current() / CAPACITY if CAPACITY > 0.0 else 0.0
	_glow.light_energy = GLOW_MAX_ENERGY * ratio
