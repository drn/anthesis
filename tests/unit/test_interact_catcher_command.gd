extends GutTest

## Covers [InteractCatcherCommand]: deposit path, collect path, inventory
## exchange exactness, null safety, and duck-type validation.


## Fake [StormCatcher] that controls gem counts and records calls, without
## requiring a real scene tree. Exposes the same interface as [StormCatcher]
## so duck-type checks in the command pass. Extends Node so it satisfies the
## statically-typed [param catcher: Node] parameter on [InteractCatcherCommand].
class CatcherStub:
	extends Node

	## Matches the pinned contract constant.
	const CAPACITY := 4

	var deposit_calls: Array = []
	var collect_calls: int = 0
	var _dun: int = 0
	var _charged: int = 0

	func set_gems(dun: int, charged: int) -> void:
		_dun = dun
		_charged = charged

	func dun_count() -> int:
		return _dun

	func charged_count() -> int:
		return _charged

	## Accept up to remaining capacity; return accepted count.
	func deposit(count: int) -> int:
		var room: int = CAPACITY - _dun - _charged
		var accepted: int = mini(count, room)
		_dun += accepted
		deposit_calls.append({"requested": count, "accepted": accepted})
		return accepted

	## Return and empty all gems.
	func collect() -> Dictionary:
		collect_calls += 1
		var result := {"dun": _dun, "charged": _charged}
		_dun = 0
		_charged = 0
		return result


## Minimal [Node] subclass lacking collect/deposit — used to verify the
## duck-type guard in [InteractCatcherCommand] rejects non-catcher nodes.
class NotACatcher:
	extends Node


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _make_ctx(inv_size := 24) -> WorldContext:
	var ctx := WorldContext.new()
	ctx.inventory = Inventory.new(inv_size)
	return ctx


# ---------------------------------------------------------------------------
# Collect path — catcher has gems
# ---------------------------------------------------------------------------


func test_collect_path_adds_dun_gems_to_inventory() -> void:
	var catcher := CatcherStub.new()
	catcher.set_gems(3, 0)
	var ctx := _make_ctx()

	InteractCatcherCommand.new(catcher).apply(ctx)

	assert_eq(ctx.inventory.count_of(&"dun_gem"), 3)
	assert_eq(catcher.collect_calls, 1)
	catcher.free()


func test_collect_path_adds_charged_gems_to_inventory() -> void:
	var catcher := CatcherStub.new()
	catcher.set_gems(0, 2)
	var ctx := _make_ctx()

	InteractCatcherCommand.new(catcher).apply(ctx)

	assert_eq(ctx.inventory.count_of(&"charged_gem"), 2)
	assert_eq(catcher.collect_calls, 1)
	catcher.free()


func test_collect_path_adds_mixed_gems_to_inventory() -> void:
	var catcher := CatcherStub.new()
	catcher.set_gems(2, 1)
	var ctx := _make_ctx()

	InteractCatcherCommand.new(catcher).apply(ctx)

	assert_eq(ctx.inventory.count_of(&"dun_gem"), 2)
	assert_eq(ctx.inventory.count_of(&"charged_gem"), 1)
	catcher.free()


func test_collect_path_empties_catcher() -> void:
	var catcher := CatcherStub.new()
	catcher.set_gems(4, 0)
	var ctx := _make_ctx()

	InteractCatcherCommand.new(catcher).apply(ctx)

	assert_eq(catcher.dun_count(), 0)
	assert_eq(catcher.charged_count(), 0)
	catcher.free()


func test_collect_path_does_not_deposit() -> void:
	## When collecting, no deposit must occur.
	var catcher := CatcherStub.new()
	catcher.set_gems(1, 1)
	var ctx := _make_ctx()
	ctx.inventory.add(&"dun_gem", 3)

	InteractCatcherCommand.new(catcher).apply(ctx)

	assert_eq(catcher.deposit_calls.size(), 0)
	catcher.free()


# ---------------------------------------------------------------------------
# Deposit path — catcher is empty
# ---------------------------------------------------------------------------


func test_deposit_path_moves_dun_gems_from_inventory() -> void:
	var catcher := CatcherStub.new()
	var ctx := _make_ctx()
	ctx.inventory.add(&"dun_gem", 3)

	InteractCatcherCommand.new(catcher).apply(ctx)

	assert_eq(catcher.dun_count(), 3)
	assert_eq(ctx.inventory.count_of(&"dun_gem"), 0)
	catcher.free()


func test_deposit_path_respects_catcher_capacity() -> void:
	## Player has 6 dun gems but CAPACITY is 4 — only 4 should be deposited.
	var catcher := CatcherStub.new()
	var ctx := _make_ctx()
	ctx.inventory.add(&"dun_gem", 6)

	InteractCatcherCommand.new(catcher).apply(ctx)

	assert_eq(catcher.dun_count(), StormCatcher.CAPACITY)
	assert_eq(ctx.inventory.count_of(&"dun_gem"), 6 - StormCatcher.CAPACITY)
	catcher.free()


func test_deposit_path_does_not_deposit_more_than_player_has() -> void:
	## Player has only 2 gems; should deposit exactly 2.
	var catcher := CatcherStub.new()
	var ctx := _make_ctx()
	ctx.inventory.add(&"dun_gem", 2)

	InteractCatcherCommand.new(catcher).apply(ctx)

	assert_eq(catcher.dun_count(), 2)
	assert_eq(ctx.inventory.count_of(&"dun_gem"), 0)
	catcher.free()


func test_deposit_removes_exactly_accepted_count() -> void:
	## inventory delta must equal exactly what deposit() reported as accepted.
	var catcher := CatcherStub.new()
	var ctx := _make_ctx()
	# Give player exactly 1 dun gem — deposit accepts 1, inventory drops to 0.
	ctx.inventory.add(&"dun_gem", 1)

	InteractCatcherCommand.new(catcher).apply(ctx)

	assert_eq(catcher.deposit_calls.size(), 1)
	var accepted: int = catcher.deposit_calls[0]["accepted"]
	assert_eq(accepted, 1)
	assert_eq(ctx.inventory.count_of(&"dun_gem"), 0)
	catcher.free()


func test_deposit_path_noop_when_inventory_has_no_dun_gems() -> void:
	var catcher := CatcherStub.new()
	var ctx := _make_ctx()
	# No dun gems in inventory.

	InteractCatcherCommand.new(catcher).apply(ctx)

	assert_eq(catcher.dun_count(), 0)
	assert_eq(catcher.deposit_calls.size(), 0)
	catcher.free()


func test_deposit_path_does_not_collect() -> void:
	## Empty catcher: collect must not be called.
	var catcher := CatcherStub.new()
	var ctx := _make_ctx()
	ctx.inventory.add(&"dun_gem", 2)

	InteractCatcherCommand.new(catcher).apply(ctx)

	assert_eq(catcher.collect_calls, 0)
	catcher.free()


# ---------------------------------------------------------------------------
# Null safety
# ---------------------------------------------------------------------------


func test_noop_when_catcher_null() -> void:
	var ctx := _make_ctx()
	# Must not crash.
	InteractCatcherCommand.new(null).apply(ctx)
	assert_true(true)


func test_noop_when_inventory_null() -> void:
	var catcher := CatcherStub.new()
	var ctx := WorldContext.new()
	# ctx.inventory is null.
	# Must not crash.
	InteractCatcherCommand.new(catcher).apply(ctx)
	assert_true(true)
	catcher.free()


func test_noop_when_catcher_lacks_interface() -> void:
	## A node that doesn't have collect/deposit is silently ignored.
	var not_catcher := NotACatcher.new()
	var ctx := _make_ctx()
	ctx.inventory.add(&"dun_gem", 2)

	InteractCatcherCommand.new(not_catcher).apply(ctx)

	assert_eq(ctx.inventory.count_of(&"dun_gem"), 2)
	not_catcher.free()


# ---------------------------------------------------------------------------
# CommandBus routing
# ---------------------------------------------------------------------------


func test_routes_through_command_bus() -> void:
	var catcher := CatcherStub.new()
	var ctx := _make_ctx()
	ctx.inventory.add(&"dun_gem", 2)
	var bus := CommandBus.new(ctx)

	bus.execute(InteractCatcherCommand.new(catcher))

	assert_eq(catcher.dun_count(), 2)
	catcher.free()
