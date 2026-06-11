extends GutTest

## Covers [ThrowCoinCommand]: consumes exactly one ferric coin from inventory,
## aborts silently with no coins, passes origin+velocity to coin_spawn, and
## is null-tolerant when inventory or coin_spawn are unwired.


## Records each spawn call so origin/velocity passthrough can be asserted.
class SpawnSpy:
	extends RefCounted

	var calls: Array = []

	func spawn(origin: Vector3, velocity: Vector3) -> void:
		calls.append({"origin": origin, "velocity": velocity})


func _context_with_coins(count: int) -> WorldContext:
	var ctx := WorldContext.new()
	ctx.inventory = Inventory.new(24, null)
	ctx.inventory.add(&"ferric_coin", count)
	return ctx


# ---------------------------------------------------------------------------
# ThrowCoinCommand
# ---------------------------------------------------------------------------


func test_consumes_exactly_one_coin_and_calls_spawn() -> void:
	var ctx := _context_with_coins(5)
	var spy := SpawnSpy.new()
	ctx.coin_spawn = spy.spawn
	ThrowCoinCommand.new(Vector3(1, 2, 3), Vector3(0, 0, 18)).apply(ctx)
	assert_eq(ctx.inventory.count_of(&"ferric_coin"), 4)
	assert_eq(spy.calls.size(), 1)


func test_spawn_receives_correct_origin_and_velocity() -> void:
	var ctx := _context_with_coins(3)
	var spy := SpawnSpy.new()
	ctx.coin_spawn = spy.spawn
	var origin := Vector3(5.0, 1.0, -3.0)
	var velocity := Vector3(0.0, 0.0, 18.0)
	ThrowCoinCommand.new(origin, velocity).apply(ctx)
	assert_eq(spy.calls[0]["origin"], origin)
	assert_eq(spy.calls[0]["velocity"], velocity)


func test_aborts_silently_when_no_coins_in_inventory() -> void:
	var ctx := _context_with_coins(0)
	var spy := SpawnSpy.new()
	ctx.coin_spawn = spy.spawn
	ThrowCoinCommand.new(Vector3.ZERO, Vector3.ZERO).apply(ctx)
	assert_eq(ctx.inventory.count_of(&"ferric_coin"), 0)
	assert_eq(spy.calls.size(), 0, "spawn must not be called with no coins")


func test_aborts_silently_when_inventory_null() -> void:
	var ctx := WorldContext.new()  # inventory not wired
	var spy := SpawnSpy.new()
	ctx.coin_spawn = spy.spawn
	# Must not crash.
	ThrowCoinCommand.new(Vector3.ZERO, Vector3.ZERO).apply(ctx)
	assert_eq(spy.calls.size(), 0)


func test_aborts_silently_when_coin_spawn_invalid() -> void:
	var ctx := _context_with_coins(5)
	# Leave ctx.coin_spawn as the default invalid Callable.
	# Must not crash and must not consume the coin.
	ThrowCoinCommand.new(Vector3.ZERO, Vector3.ZERO).apply(ctx)
	assert_eq(ctx.inventory.count_of(&"ferric_coin"), 5, "coin not consumed with invalid spawn")


func test_each_call_consumes_exactly_one_coin() -> void:
	var ctx := _context_with_coins(3)
	var spy := SpawnSpy.new()
	ctx.coin_spawn = spy.spawn
	ThrowCoinCommand.new(Vector3.ZERO, Vector3(0, 0, 18)).apply(ctx)
	ThrowCoinCommand.new(Vector3.ZERO, Vector3(0, 0, 18)).apply(ctx)
	assert_eq(ctx.inventory.count_of(&"ferric_coin"), 1)
	assert_eq(spy.calls.size(), 2)


func test_routes_through_command_bus() -> void:
	var ctx := _context_with_coins(2)
	var spy := SpawnSpy.new()
	ctx.coin_spawn = spy.spawn
	var bus := CommandBus.new(ctx)
	bus.execute(ThrowCoinCommand.new(Vector3(0, 1, 0), Vector3(0, 0, 18)))
	assert_eq(ctx.inventory.count_of(&"ferric_coin"), 1)
	assert_eq(spy.calls.size(), 1)
