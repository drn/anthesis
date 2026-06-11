extends GutTest

## Covers [DamageCommand]: routing to the combat service, the null-combat
## no-op, knockback passthrough, vigor-resistance reduction, and execution
## through the [CommandBus].


## Records each apply_damage call so routing and passthrough can be asserted
## without a real scene tree. Subclasses [CombatService] so it satisfies the
## statically-typed [member WorldContext.combat] field while intercepting calls.
class CombatStub:
	extends CombatService

	var calls: Array = []

	func apply_damage(target_id: int, amount: float, knockback := Vector3.ZERO) -> float:
		calls.append({"id": target_id, "amount": amount, "knockback": knockback})
		return amount


## Minimal fake for StatusEffectSystem that reports a fixed set of active
## effects without requiring a real scene tree.
class StatusStub:
	extends RefCounted

	## Set of (target_id, effect_id) pairs that are considered active.
	var active: Array = []

	func has(target_id: int, effect_id: StringName) -> bool:
		for entry in active:
			if entry[0] == target_id and entry[1] == effect_id:
				return true
		return false


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


# ---------------------------------------------------------------------------
# DamageCommand — vigor resistance (pewter burn)
# ---------------------------------------------------------------------------


func test_vigor_reduces_incoming_damage_by_mult() -> void:
	var stub := CombatStub.new()
	var status := StatusStub.new()
	status.active.append([101, &"vigor"])
	var ctx := WorldContext.new()
	ctx.combat = stub
	ctx.status = status
	DamageCommand.new(101, 10.0).apply(ctx)
	assert_eq(stub.calls.size(), 1)
	assert_almost_eq(stub.calls[0]["amount"], 7.0, 0.001)


func test_vigor_does_not_affect_knockback() -> void:
	var stub := CombatStub.new()
	var status := StatusStub.new()
	status.active.append([101, &"vigor"])
	var ctx := WorldContext.new()
	ctx.combat = stub
	ctx.status = status
	DamageCommand.new(101, 10.0, Vector3(1, 2, 3)).apply(ctx)
	assert_eq(stub.calls[0]["knockback"], Vector3(1, 2, 3))


func test_no_vigor_effect_applies_full_damage() -> void:
	var stub := CombatStub.new()
	var status := StatusStub.new()
	var ctx := WorldContext.new()
	ctx.combat = stub
	ctx.status = status
	DamageCommand.new(202, 10.0).apply(ctx)
	assert_almost_eq(stub.calls[0]["amount"], 10.0, 0.001)


func test_vigor_mult_constant_value() -> void:
	assert_almost_eq(DamageCommand.VIGOR_DAMAGE_MULT, 0.7, 0.0001)


func test_vigor_only_applies_to_matching_target() -> void:
	## Target 202 has vigor; target 303 does not — each gets the correct amount.
	var stub := CombatStub.new()
	var status := StatusStub.new()
	status.active.append([202, &"vigor"])
	var ctx := WorldContext.new()
	ctx.combat = stub
	ctx.status = status
	DamageCommand.new(303, 10.0).apply(ctx)
	DamageCommand.new(202, 10.0).apply(ctx)
	assert_almost_eq(stub.calls[0]["amount"], 10.0, 0.001)
	assert_almost_eq(stub.calls[1]["amount"], 7.0, 0.001)


func test_noop_when_status_null_with_damage() -> void:
	## No status wired — damage passes through unmodified.
	var stub := CombatStub.new()
	var ctx := WorldContext.new()
	ctx.combat = stub
	DamageCommand.new(101, 10.0).apply(ctx)
	assert_almost_eq(stub.calls[0]["amount"], 10.0, 0.001)
