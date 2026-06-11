extends GutTest

## Covers [CombatService]: register/unregister, damage routing and the
## actually-dealt return value, knockback added to a real [CharacterBody3D]
## velocity, safe no-ops on unknown ids, and the [signal damage_applied] signal.

var _bodies: Array[CharacterBody3D] = []


func after_each() -> void:
	for body in _bodies:
		if is_instance_valid(body):
			body.free()
	_bodies.clear()


## Build a free-tracked CharacterBody3D so knockback can be observed on velocity.
func _body() -> CharacterBody3D:
	var b := CharacterBody3D.new()
	_bodies.append(b)
	return b


func test_register_exposes_health_and_node() -> void:
	var svc := CombatService.new()
	var h := Health.new(30.0)
	var node := _body()
	svc.register(1, h, node)
	assert_eq(svc.health_of(1), h)
	assert_eq(svc.node_of(1), node)


func test_register_without_node_leaves_node_null() -> void:
	var svc := CombatService.new()
	svc.register(2, Health.new(10.0))
	assert_null(svc.node_of(2))
	assert_not_null(svc.health_of(2))


func test_unregister_removes_entry() -> void:
	var svc := CombatService.new()
	svc.register(3, Health.new(10.0), _body())
	svc.unregister(3)
	assert_null(svc.health_of(3))
	assert_null(svc.node_of(3))


func test_unregister_unknown_id_is_safe() -> void:
	var svc := CombatService.new()
	svc.unregister(999)
	assert_true(true)


func test_lookups_on_unknown_id_return_null() -> void:
	var svc := CombatService.new()
	assert_null(svc.health_of(42))
	assert_null(svc.node_of(42))


func test_apply_damage_routes_to_health_and_returns_dealt() -> void:
	var svc := CombatService.new()
	var h := Health.new(30.0)
	svc.register(4, h)
	var dealt := svc.apply_damage(4, 9.0)
	assert_eq(dealt, 9.0)
	assert_eq(h.current(), 21.0)


func test_apply_damage_returns_clamped_dealt_on_overkill() -> void:
	var svc := CombatService.new()
	var h := Health.new(5.0)
	svc.register(5, h)
	# Only the 5 hp that existed are reported as dealt.
	assert_eq(svc.apply_damage(5, 100.0), 5.0)
	assert_true(h.is_dead())


func test_apply_damage_unknown_id_is_safe_noop() -> void:
	var svc := CombatService.new()
	assert_eq(svc.apply_damage(777, 50.0), 0.0)


func test_knockback_added_to_character_body_velocity() -> void:
	var svc := CombatService.new()
	var node := _body()
	node.velocity = Vector3(1, 0, 0)
	svc.register(6, Health.new(30.0), node)
	svc.apply_damage(6, 5.0, Vector3(0, 2, 3))
	assert_eq(node.velocity, Vector3(1, 2, 3))


func test_no_knockback_when_node_not_character_body() -> void:
	var svc := CombatService.new()
	var h := Health.new(30.0)
	# No node registered; knockback path must not crash.
	svc.register(7, h)
	assert_eq(svc.apply_damage(7, 5.0, Vector3(0, 9, 0)), 5.0)
	assert_eq(h.current(), 25.0)


func test_damage_applied_signal_carries_id_and_dealt() -> void:
	var svc := CombatService.new()
	svc.register(8, Health.new(30.0))
	watch_signals(svc)
	svc.apply_damage(8, 7.0)
	assert_signal_emitted_with_parameters(svc, "damage_applied", [8, 7.0])


func test_damage_applied_not_emitted_when_nothing_dealt() -> void:
	var svc := CombatService.new()
	var h := Health.new(10.0)
	h.take_damage(10.0)  # already dead => future hits deal nothing
	svc.register(9, h)
	watch_signals(svc)
	assert_eq(svc.apply_damage(9, 5.0), 0.0)
	assert_signal_not_emitted(svc, "damage_applied")
