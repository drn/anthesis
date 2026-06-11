## Sustained metal-burns — the channels a Ferromancer holds open over time.
##
## Where a cast is one-shot, a channel is a toggle: open it and it drains its metal
## reserve every tick until you close it or the reserve runs dry. Vigor (pewter) and
## Keensight (tin) are channels — burning steadily for an ongoing boon. Flaring
## (burning hot) multiplies every open channel's drain by [constant FLARE_DRAIN_MULT]
## for a stronger effect at a steeper cost.
##
## A channel that depletes mid-burn is force-stopped: its [code]on_stop[/code] fires
## with reason &"depleted" (vs &"manual" for a deliberate toggle-off), so callers can
## punish over-burning — the "pewter drag" crash. Channels auto-swallow flakes from
## the bound inventory on toggle and on tick, sharing the reserve's flake economy.
##
## A scene-tree [Node] so its per-tick wiring is owned by the tree and cannot be
## garbage-collected out from under the [SimulationClock].
class_name ChannelSystem
extends Node

## Emitted whenever a channel opens or closes (manually or by depletion).
signal channel_changed(channel_id: StringName, active: bool)

## Drain multiplier applied to every open channel while flaring.
const FLARE_DRAIN_MULT := 3.0

var _reserves: MetalReserves
var _inventory: Object
## Maps channel id -> its def Dictionary (see [method install]).
var _defs: Dictionary = {}
## Maps channel id -> bool active state.
var _active: Dictionary = {}
var _flaring := false


## Bind the [param reserves] every channel drains and the [param inventory] flakes
## are swallowed from. May be called before or after [method install].
func setup(reserves: MetalReserves, inventory: Object) -> void:
	_reserves = reserves
	_inventory = inventory


## Register a channel. [param def] keys:
## [code]resource_kind[/code] (StringName metal), [code]drain_per_tick[/code] (float),
## [code]on_start[/code] (Callable()), [code]on_stop[/code] (Callable(reason: StringName)).
func install(channel_id: StringName, def: Dictionary) -> void:
	_defs[channel_id] = def
	_active[channel_id] = false


## Flip [param channel_id] on or off; return whether the toggle took effect.
##
## Turning ON requires the reserve to ensure its first tick of drain (auto-swallowing
## flakes); if it cannot, the channel stays off and this returns false. Otherwise the
## def's [code]on_start[/code] runs, [signal channel_changed] fires true, returns true.
## Turning OFF runs [code]on_stop[/code] with &"manual", fires false, returns true.
## An uninstalled id is a safe no-op returning false.
func toggle(channel_id: StringName) -> bool:
	if not _defs.has(channel_id):
		return false
	var def: Dictionary = _defs[channel_id]
	if _active[channel_id]:
		_active[channel_id] = false
		_call_on_stop(def, &"manual")
		channel_changed.emit(channel_id, false)
		return true
	var kind: StringName = def.get("resource_kind", &"")
	var drain: float = def.get("drain_per_tick", 0.0)
	if _reserves != null and not _reserves.ensure(kind, drain, _inventory):
		return false
	_active[channel_id] = true
	_call_on_start(def)
	channel_changed.emit(channel_id, true)
	return true


## Whether [param channel_id] is currently open.
func is_active(channel_id: StringName) -> bool:
	return _active.get(channel_id, false)


## Set the global flare state — while [param active], open channels drain
## [constant FLARE_DRAIN_MULT]x.
func set_flare(active: bool) -> void:
	_flaring = active


## Whether channels are currently flaring (burning hot).
func is_flaring() -> bool:
	return _flaring


## The open channel ids, sorted for stable iteration.
func active_channels() -> Array:
	var out: Array = []
	for id: StringName in _active.keys():
		if _active[id]:
			out.append(id)
	out.sort()
	return out


## Per-tick drain for every open channel (wire to [signal SimulationClock.ticked]).
##
## Each open channel drains [code]drain_per_tick[/code], times [constant
## FLARE_DRAIN_MULT] while flaring. If the well cannot cover the drain, the reserve
## tries to auto-swallow a flake and spend again; still failing, the channel is
## force-stopped with its [code]on_stop[/code] called with reason &"depleted".
func on_tick(_tick: int) -> void:
	for channel_id: StringName in active_channels():
		var def: Dictionary = _defs[channel_id]
		var kind: StringName = def.get("resource_kind", &"")
		var drain: float = def.get("drain_per_tick", 0.0)
		if _flaring:
			drain *= FLARE_DRAIN_MULT
		var w: LumenWell = _reserves.well(kind) if _reserves != null else null
		if w != null and w.spend(drain):
			continue
		if (
			_reserves != null
			and _reserves.ensure(kind, drain, _inventory)
			and w != null
			and w.spend(drain)
		):
			continue
		_active[channel_id] = false
		_call_on_stop(def, &"depleted")
		channel_changed.emit(channel_id, false)


func _call_on_start(def: Dictionary) -> void:
	var cb: Callable = def.get("on_start", Callable())
	if cb.is_valid():
		cb.call()


func _call_on_stop(def: Dictionary, reason: StringName) -> void:
	var cb: Callable = def.get("on_stop", Callable())
	if cb.is_valid():
		cb.call(reason)
