extends GutTest
## Resource-orb shader tests: HP/Lumen orb fills carry the liquid orb
## material and hud.gd drives its fill_ratio / fill_color / pulse parameters.
##
## Split from test_hud.gd / test_hud_combat.gd to respect the
## 20-public-method lint ceiling.

const HUD_PATH := "res://scenes/ui/hud.tscn"
const SHADER_PATH := "res://shaders/resource_orb.gdshader"


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


class FakeWell:
	extends RefCounted
	signal changed(current: float, capacity: float)
	var _current: float
	var _capacity: float

	func _init(current: float, capacity: float) -> void:
		_current = current
		_capacity = capacity

	func current() -> float:
		return _current

	func capacity() -> float:
		return _capacity

	func set_current(value: float) -> void:
		_current = value
		changed.emit(_current, _capacity)


func _hud() -> Hud:
	var hud := (load(HUD_PATH) as PackedScene).instantiate() as Hud
	add_child_autofree(hud)
	return hud


func _fill_material(hud: Hud, orb: String) -> ShaderMaterial:
	var fill := hud.get_node("%s/Fill" % orb) as ColorRect
	return fill.material as ShaderMaterial


# ---------------------------------------------------------------------------
# Material wiring
# ---------------------------------------------------------------------------


func test_resource_orb_shader_loads() -> void:
	var shader := load(SHADER_PATH) as Shader
	assert_not_null(shader, "resource_orb.gdshader must load")


func test_health_fill_has_orb_material() -> void:
	var mat := _fill_material(_hud(), "HealthOrb")
	assert_not_null(mat, "Health fill must carry a ShaderMaterial")
	assert_eq(mat.shader, load(SHADER_PATH), "Health fill must use the resource orb shader")


func test_lumen_fill_has_orb_material() -> void:
	var mat := _fill_material(_hud(), "LumenOrb")
	assert_not_null(mat, "Lumen fill must carry a ShaderMaterial")
	assert_eq(mat.shader, load(SHADER_PATH), "Lumen fill must use the resource orb shader")


func test_meter_materials_are_independent() -> void:
	var hud := _hud()
	assert_ne(
		_fill_material(hud, "HealthOrb"),
		_fill_material(hud, "LumenOrb"),
		"HP and Lumen meters must not share a material instance"
	)


# ---------------------------------------------------------------------------
# Health meter parameters
# ---------------------------------------------------------------------------


func test_health_fill_ratio_tracks_health() -> void:
	var health := FakeHealth.new(30.0, 40.0)
	var hud := _hud()
	hud.bind_health(health)
	var mat := _fill_material(hud, "HealthOrb")
	assert_almost_eq(
		float(mat.get_shader_parameter("fill_ratio")), 0.75, 0.001, "fill_ratio reflects 30/40"
	)
	health.set_current(10.0)
	assert_almost_eq(
		float(mat.get_shader_parameter("fill_ratio")), 0.25, 0.001, "fill_ratio follows changed"
	)


func test_health_fill_color_param_matches_rect() -> void:
	var hud := _hud()
	hud.bind_health(FakeHealth.new(40.0, 40.0))
	var fill := hud.get_node("HealthOrb/Fill") as ColorRect
	var mat := fill.material as ShaderMaterial
	assert_eq(
		mat.get_shader_parameter("fill_color"),
		fill.color,
		"Shader fill_color mirrors the fill rect color"
	)


func test_health_pulse_zero_when_healthy() -> void:
	var hud := _hud()
	hud.bind_health(FakeHealth.new(40.0, 40.0))
	var mat := _fill_material(hud, "HealthOrb")
	assert_almost_eq(
		float(mat.get_shader_parameter("pulse")), 0.0, 0.001, "No alarm pulse at full health"
	)


func test_health_pulse_rises_when_low() -> void:
	var health := FakeHealth.new(40.0, 40.0)
	var hud := _hud()
	hud.bind_health(health)
	var mat := _fill_material(hud, "HealthOrb")
	health.set_current(4.0)
	assert_gt(
		float(mat.get_shader_parameter("pulse")), 0.0, "Low health drives a nonzero alarm pulse"
	)


# ---------------------------------------------------------------------------
# Lumen meter parameters
# ---------------------------------------------------------------------------


func test_lumen_fill_ratio_tracks_well() -> void:
	var well := FakeWell.new(50.0, 100.0)
	var hud := _hud()
	hud.bind_magic(well, null, [])
	var mat := _fill_material(hud, "LumenOrb")
	assert_almost_eq(
		float(mat.get_shader_parameter("fill_ratio")), 0.5, 0.001, "fill_ratio reflects 50/100"
	)
	well.set_current(100.0)
	assert_almost_eq(
		float(mat.get_shader_parameter("fill_ratio")), 1.0, 0.001, "fill_ratio follows changed"
	)


func test_meter_updates_survive_missing_material() -> void:
	var health := FakeHealth.new(40.0, 40.0)
	var hud := _hud()
	var fill := hud.get_node("HealthOrb/Fill") as ColorRect
	fill.material = null
	hud.bind_health(health)
	health.set_current(10.0)
	var label := hud.get_node("HealthOrb/Label") as Label
	assert_eq(label.text, "HP 10 / 40", "Meter updates degrade gracefully without a material")
