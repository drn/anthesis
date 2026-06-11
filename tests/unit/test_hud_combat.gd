extends GutTest
## Combat HUD unit tests: health bar, bind_health, hurt vignette, death overlay.
##
## Split from test_hud.gd to respect the 20-public-method lint ceiling.

const HUD_PATH := "res://scenes/ui/hud.tscn"


class FakeHealth:
	extends RefCounted
	signal changed(current: float, max_health: float)
	var _current: float
	var _max: float

	func _init(current: float, max_hp: float) -> void:
		_current = current
		_max = max_hp

	func current() -> float:
		return _current

	func max_health() -> float:
		return _max

	func set_current(value: float) -> void:
		_current = value
		changed.emit(_current, _max)


# ---------------------------------------------------------------------------
# Health bar structure
# ---------------------------------------------------------------------------


func test_hud_has_health_bar() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate()
	add_child_autofree(hud)
	var bar := hud.get_node_or_null("HealthBar")
	assert_not_null(bar, "HUD must have a HealthBar node")
	var label := hud.get_node_or_null("HealthBar/Margin/Body/Label")
	assert_not_null(label, "HealthBar must have a label")
	var fill := hud.get_node_or_null("HealthBar/Margin/Body/Track/Fill")
	assert_not_null(fill, "HealthBar must have a fill rect")


# ---------------------------------------------------------------------------
# bind_health
# ---------------------------------------------------------------------------


func test_bind_health_reflects_initial_state() -> void:
	var health := FakeHealth.new(30.0, 40.0)
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	hud.bind_health(health)
	var label := hud.get_node("HealthBar/Margin/Body/Label") as Label
	assert_eq(label.text, "HP 30 / 40", "Health label shows initial state on bind")


func test_bind_health_updates_on_changed() -> void:
	var health := FakeHealth.new(30.0, 40.0)
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	hud.bind_health(health)
	health.set_current(15.0)
	var label := hud.get_node("HealthBar/Margin/Body/Label") as Label
	assert_eq(label.text, "HP 15 / 40", "Health label updates on health.changed")


func test_bind_health_nil_safe() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	hud.bind_health(null)
	assert_true(true, "bind_health(null) must not crash")


# ---------------------------------------------------------------------------
# Hurt vignette
# ---------------------------------------------------------------------------


func test_hud_has_hurt_vignette() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate()
	add_child_autofree(hud)
	var vignette := hud.get_node_or_null("HurtVignette")
	assert_not_null(vignette, "HUD must have a HurtVignette node")
	assert_true(vignette is ColorRect, "HurtVignette must be a ColorRect")


func test_hurt_vignette_transparent_by_default() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate()
	add_child_autofree(hud)
	var vignette := hud.get_node("HurtVignette") as ColorRect
	assert_almost_eq(vignette.modulate.a, 0.0, 0.01, "HurtVignette must be transparent initially")


# ---------------------------------------------------------------------------
# Death overlay
# ---------------------------------------------------------------------------


func test_death_overlay_hidden_by_default() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate()
	add_child_autofree(hud)
	var overlay := hud.get_node_or_null("DeathOverlay")
	assert_not_null(overlay, "HUD must have a DeathOverlay node")
	assert_false(overlay.visible, "DeathOverlay must be hidden by default")


func test_show_death_makes_overlay_visible() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	hud.show_death(4.0)
	var overlay := hud.get_node("DeathOverlay")
	assert_true(overlay.visible, "show_death() must make DeathOverlay visible")
	var label := hud.get_node("DeathOverlay/Label") as Label
	assert_true(
		label.text.contains("THE DARK TAKES YOU"), "Death label must contain 'THE DARK TAKES YOU'"
	)


func test_hide_death_hides_overlay() -> void:
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	hud.show_death(4.0)
	hud.hide_death()
	var overlay := hud.get_node("DeathOverlay")
	assert_false(overlay.visible, "hide_death() must hide DeathOverlay")
