extends GutTest

## Covers [DamageCommand]: routing to the combat service, the null-combat
## no-op, knockback passthrough, and execution through the [CommandBus].


## Records each apply_damage call so routing and passthrough can be asserted
## without a real scene tree. Subclasses [CombatService] so it satisfies the
## statically-typed [member WorldContext.combat] field while intercepting calls.
class CombatStub:
	extends CombatService

	var calls: Array = []

	func apply_damage(target_id: int, amount: float, knockback := Vector3.ZERO) -> float:
		calls.append({"id": target_id, "amount": amount, "knockback": knockback})
		return amount


func test_routes_to_combat_service() -> void:
	var stub := CombatStub.new()
	var ctx := WorldContext.new()
	ctx.combat = stub
	DamageCommand.new(101, 12.0).apply(ctx)
	assert_eq(stub.calls.size(), 1)
	assert_eq(stub.calls[0]["id"], 101)
	assert_eq(stub.calls[0]["amount"], 12.0)


func test_passes_knockback_through() -> void:
	var stub := CombatStub.new()
	var ctx := WorldContext.new()
	ctx.combat = stub
	DamageCommand.new(101, 12.0, Vector3(0, 2, 6)).apply(ctx)
	assert_eq(stub.calls[0]["knockback"], Vector3(0, 2, 6))


func test_default_knockback_is_zero() -> void:
	var stub := CombatStub.new()
	var ctx := WorldContext.new()
	ctx.combat = stub
	DamageCommand.new(101, 12.0).apply(ctx)
	assert_eq(stub.calls[0]["knockback"], Vector3.ZERO)


func test_noop_when_combat_null() -> void:
	var ctx := WorldContext.new()  # no combat wired
	# Must not crash.
	DamageCommand.new(101, 12.0, Vector3.UP).apply(ctx)
	assert_true(true)


func test_routes_through_command_bus() -> void:
	var stub := CombatStub.new()
	var ctx := WorldContext.new()
	ctx.combat = stub
	var bus := CommandBus.new(ctx)
	bus.execute(DamageCommand.new(202, 4.0, Vector3.DOWN))
	assert_eq(stub.calls.size(), 1)
	assert_eq(stub.calls[0]["id"], 202)
