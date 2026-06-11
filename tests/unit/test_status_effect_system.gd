extends GutTest

## Exercises [StatusEffectSystem]: apply/expire callables fire exactly once each,
## refresh semantics (no re-apply), indefinite effects, countdown expiry, clear,
## and clear_all.

const VIGOR := &"vigor"
const TARGET := 42


## Records how many times the apply / expire callables fire.
class CallableSpy:
	extends RefCounted

	var applies: int = 0
	var expires: int = 0

	func on_apply() -> void:
		applies += 1

	func on_expire() -> void:
		expires += 1


func _system() -> StatusEffectSystem:
	var s := StatusEffectSystem.new()
	add_child_autofree(s)
	return s


func test_apply_fires_on_apply_once_and_signals() -> void:
	var s := _system()
	var spy := CallableSpy.new()
	watch_signals(s)

	s.apply(TARGET, VIGOR, 5, spy.on_apply, spy.on_expire)

	assert_true(s.has(TARGET, VIGOR))
	assert_eq(spy.applies, 1)
	assert_eq(spy.expires, 0)
	assert_signal_emitted_with_parameters(s, "effect_applied", [TARGET, VIGOR])


func test_countdown_expires_and_fires_on_expire_once() -> void:
	var s := _system()
	var spy := CallableSpy.new()
	s.apply(TARGET, VIGOR, 2, spy.on_apply, spy.on_expire)
	watch_signals(s)

	s.on_tick(1)  # remaining 1
	assert_true(s.has(TARGET, VIGOR))
	s.on_tick(2)  # remaining 0 -> expire

	assert_false(s.has(TARGET, VIGOR))
	assert_eq(spy.expires, 1)
	assert_signal_emitted_with_parameters(s, "effect_expired", [TARGET, VIGOR])


func test_reapply_refreshes_without_recalling_on_apply() -> void:
	var s := _system()
	var spy := CallableSpy.new()
	s.apply(TARGET, VIGOR, 3, spy.on_apply, spy.on_expire)
	s.on_tick(1)  # remaining 2
	s.apply(TARGET, VIGOR, 3, spy.on_apply, spy.on_expire)  # refresh to 3

	assert_eq(spy.applies, 1, "on_apply not re-called on refresh")
	s.on_tick(2)
	s.on_tick(3)
	assert_true(s.has(TARGET, VIGOR), "still alive: refreshed to 3")
	s.on_tick(4)
	assert_false(s.has(TARGET, VIGOR))


func test_indefinite_effect_never_expires_on_tick() -> void:
	var s := _system()
	var spy := CallableSpy.new()
	s.apply(TARGET, VIGOR, 0, spy.on_apply, spy.on_expire)  # indefinite

	for t in range(1, 50):
		s.on_tick(t)
	assert_true(s.has(TARGET, VIGOR))
	assert_eq(spy.expires, 0)


func test_clear_fires_on_expire() -> void:
	var s := _system()
	var spy := CallableSpy.new()
	s.apply(TARGET, VIGOR, 0, spy.on_apply, spy.on_expire)
	watch_signals(s)

	s.clear(TARGET, VIGOR)

	assert_false(s.has(TARGET, VIGOR))
	assert_eq(spy.expires, 1)
	assert_signal_emitted_with_parameters(s, "effect_expired", [TARGET, VIGOR])


func test_clear_missing_is_noop() -> void:
	var s := _system()
	var spy := CallableSpy.new()
	s.clear(TARGET, VIGOR)  # nothing applied
	assert_eq(spy.expires, 0)


func test_clear_all_expires_every_effect() -> void:
	var s := _system()
	var a := CallableSpy.new()
	var b := CallableSpy.new()
	s.apply(TARGET, VIGOR, 0, a.on_apply, a.on_expire)
	s.apply(TARGET, &"keensight", 0, b.on_apply, b.on_expire)

	s.clear_all(TARGET)

	assert_false(s.has(TARGET, VIGOR))
	assert_false(s.has(TARGET, &"keensight"))
	assert_eq(a.expires, 1)
	assert_eq(b.expires, 1)
