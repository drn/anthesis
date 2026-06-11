extends GutTest

## Covers [InhaleCommand]: routing through [TempestLight], null-safety, and
## the [CommandBus] execution path.


## Lightweight fake for [TempestLight] that records inhale calls and controls
## the return value, without requiring the full Node scene tree.
class TempestStub:
	extends RefCounted

	var inhale_calls: Array = []
	var inhale_result := true

	func inhale(inventory: Object) -> bool:
		inhale_calls.append({"inventory": inventory})
		return inhale_result


# ---------------------------------------------------------------------------
# InhaleCommand — routing to TempestLight
# ---------------------------------------------------------------------------


func test_inhale_delegates_to_tempest_with_inventory() -> void:
	var stub := TempestStub.new()
	var ctx := WorldContext.new()
	ctx.tempest = stub
	var inv := Inventory.new(8)
	ctx.inventory = inv

	InhaleCommand.new().apply(ctx)

	assert_eq(stub.inhale_calls.size(), 1)
	assert_eq(stub.inhale_calls[0]["inventory"], inv)


func test_inhale_passes_null_inventory_when_not_wired() -> void:
	## tempest.inhale must receive null safely when no inventory is set.
	var stub := TempestStub.new()
	var ctx := WorldContext.new()
	ctx.tempest = stub
	# Leave ctx.inventory null.

	InhaleCommand.new().apply(ctx)

	assert_eq(stub.inhale_calls.size(), 1)
	assert_eq(stub.inhale_calls[0]["inventory"], null)


func test_inhale_noop_when_tempest_null() -> void:
	var ctx := WorldContext.new()  # no tempest wired
	ctx.inventory = Inventory.new(8)
	# Must not crash.
	InhaleCommand.new().apply(ctx)
	assert_true(true)


func test_inhale_noop_when_tempest_and_inventory_both_null() -> void:
	var ctx := WorldContext.new()
	# Neither tempest nor inventory wired — must not crash.
	InhaleCommand.new().apply(ctx)
	assert_true(true)


func test_inhale_routes_through_command_bus() -> void:
	var stub := TempestStub.new()
	var ctx := WorldContext.new()
	ctx.tempest = stub
	ctx.inventory = Inventory.new(4)
	var bus := CommandBus.new(ctx)

	bus.execute(InhaleCommand.new())

	assert_eq(stub.inhale_calls.size(), 1)


func test_inhale_returns_when_stub_returns_false() -> void:
	## Command must not crash even when inhale reports no charged gem available.
	var stub := TempestStub.new()
	stub.inhale_result = false
	var ctx := WorldContext.new()
	ctx.tempest = stub
	ctx.inventory = Inventory.new(4)

	InhaleCommand.new().apply(ctx)

	assert_eq(stub.inhale_calls.size(), 1)
