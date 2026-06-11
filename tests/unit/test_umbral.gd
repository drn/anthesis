extends GutTest

## Structural tests for the Umbral scene. Loads umbral.tscn headless, runs
## [method Umbral.setup] with a CreatureDef, and verifies the procedural body is
## built (core mesh + omni light + collision), the Health pool is created from
## the def, the node joins the "umbrals" group, and the combat signals exist.
## No physics is simulated — these are wiring/structure checks only.

var _umbral_scene: PackedScene = preload("res://scenes/creatures/umbral.tscn")
var _umbral: Umbral


func _def() -> CreatureDef:
	var d := CreatureDef.new()
	d.id = &"test_umbral"
	d.display_name = "Test Umbral"
	d.max_health = 20.0
	d.move_speed = 3.0
	d.attack_damage = 5.0
	d.attack_range = 1.6
	d.aggro_range = 12.0
	d.attack_cooldown_ticks = 12
	d.core_color = Color(0.7, 0.3, 1.0)
	d.body_scale = 0.8
	return d


func before_each() -> void:
	_umbral = _umbral_scene.instantiate() as Umbral
	add_child_autofree(_umbral)


func test_root_is_character_body_3d() -> void:
	assert_true(_umbral is CharacterBody3D, "Umbral root must be a CharacterBody3D")


func test_in_umbrals_group_after_ready() -> void:
	assert_true(_umbral.is_in_group("umbrals"), "Umbral must join the 'umbrals' group")


func test_has_perished_signal() -> void:
	assert_true(_umbral.has_signal("perished"), "Umbral must declare signal perished")


func test_has_attack_landed_signal() -> void:
	assert_true(_umbral.has_signal("attack_landed"), "Umbral must declare signal attack_landed")


func test_setup_builds_health_from_def() -> void:
	var def := _def()
	_umbral.setup(def, null, RandomNumberGenerator.new(), null)
	var hp := _umbral.health()
	assert_not_null(hp, "setup must build a Health pool")
	assert_almost_eq(hp.max_health(), def.max_health, 0.001, "Health max must match def")
	assert_almost_eq(hp.current(), def.max_health, 0.001, "Health starts full")


func test_setup_builds_glowing_core_mesh() -> void:
	_umbral.setup(_def(), null, RandomNumberGenerator.new(), null)
	var core := _umbral.get_node_or_null("Core")
	assert_not_null(core, "Umbral must build a Core mesh")
	assert_true(core is MeshInstance3D, "Core must be a MeshInstance3D")
	var mat := (core as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
	assert_not_null(mat, "Core must carry a material")
	assert_true(mat.emission_enabled, "Core material must be emissive")


func test_setup_builds_omni_light() -> void:
	_umbral.setup(_def(), null, RandomNumberGenerator.new(), null)
	var light := _umbral.get_node_or_null("CoreLight")
	assert_not_null(light, "Umbral must build a core OmniLight3D")
	assert_true(light is OmniLight3D, "CoreLight must be an OmniLight3D")


func test_setup_builds_collision_shape() -> void:
	_umbral.setup(_def(), null, RandomNumberGenerator.new(), null)
	var col := _umbral.get_node_or_null("CollisionShape3D")
	assert_not_null(col, "Umbral must build a CollisionShape3D")
	assert_true(col is CollisionShape3D, "must be a CollisionShape3D")
	assert_not_null((col as CollisionShape3D).shape, "collision must have a shape")


func test_setup_builds_dark_translucent_body() -> void:
	_umbral.setup(_def(), null, RandomNumberGenerator.new(), null)
	var body := _umbral.get_node_or_null("Body")
	assert_not_null(body, "Umbral must build a Body mesh")
	var mat := (body as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
	assert_not_null(mat)
	assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "body must be alpha-translucent")


func test_core_light_tinted_to_def_color() -> void:
	var def := _def()
	_umbral.setup(def, null, RandomNumberGenerator.new(), null)
	var light := _umbral.get_node("CoreLight") as OmniLight3D
	assert_almost_eq(light.light_color.r, def.core_color.r, 0.01, "light tinted to core_color")
	assert_almost_eq(light.light_color.b, def.core_color.b, 0.01)


func test_definition_returns_def() -> void:
	var def := _def()
	_umbral.setup(def, null, RandomNumberGenerator.new(), null)
	assert_eq(_umbral.definition().id, def.id, "definition() returns the configured def")
