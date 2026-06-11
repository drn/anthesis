## Consumes one ferric coin from inventory and launches it into the world.
##
## ThrowCoinCommand is the authoritative entry point for the coin-toss mechanic.
## It carries an origin position and a velocity vector, removes one
## [code]&"ferric_coin"[/code] from the player inventory, and then calls the
## [member WorldContext.coin_spawn] Callable to spawn the physical coin at the
## given position with the given velocity. If the inventory has no coins the
## command aborts silently without calling coin_spawn, so the effect is
## all-or-nothing. When inventory or coin_spawn are not wired the command is
## also a silent no-op, mirroring the null-tolerance of the other commands.
class_name ThrowCoinCommand
extends WorldCommand

var _origin: Vector3
var _velocity: Vector3


## Capture the [param origin] and [param velocity] for the thrown coin.
func _init(origin: Vector3, velocity: Vector3) -> void:
	_origin = origin
	_velocity = velocity


## Consume one ferric coin and call [member WorldContext.coin_spawn].
##
## Aborts silently when inventory is unwired, contains no coins, or coin_spawn
## is an invalid Callable.
func apply(ctx: WorldContext) -> void:
	if ctx.inventory == null:
		return
	if not ctx.coin_spawn.is_valid():
		return
	var removed := ctx.inventory.remove(&"ferric_coin", 1)
	if removed == 0:
		return
	ctx.coin_spawn.call(_origin, _velocity)
