extends GutTest

# ---------------------------------------------------------------------------
# Verifies the presentation environment rig is wired correctly:
# WorldEnvironment present, glow + volumetric fog enabled, sky shader
# assigned, and a shadow-casting directional light exists.
# ---------------------------------------------------------------------------

const ENV_SCENE := "res://scenes/world/environment.tscn"


func _instantiate_rig() -> Node3D:
	var packed: PackedScene = load(ENV_SCENE)
	assert_not_null(packed, "environment.tscn must load")
	var rig: Node3D = packed.instantiate()
	add_child_autofree(rig)
	return rig


func _find_world_environment(rig: Node) -> WorldEnvironment:
	for child in rig.get_children():
		if child is WorldEnvironment:
			return child
	return null


func _find_directional_lights(rig: Node) -> Array:
	var out := []
	for child in rig.get_children():
		if child is DirectionalLight3D:
			out.append(child)
	return out


func test_world_environment_exists() -> void:
	var rig := _instantiate_rig()
	var we := _find_world_environment(rig)
	assert_not_null(we, "Rig must contain a WorldEnvironment node")
	assert_not_null(we.environment, "WorldEnvironment must have an Environment resource")


func test_glow_enabled() -> void:
	var rig := _instantiate_rig()
	var env := _find_world_environment(rig).environment
	assert_true(env.glow_enabled, "Glow must be enabled")


func test_volumetric_fog_enabled() -> void:
	var rig := _instantiate_rig()
	var env := _find_world_environment(rig).environment
	assert_true(env.volumetric_fog_enabled, "Volumetric fog must be enabled")


func test_sky_shader_assigned() -> void:
	var rig := _instantiate_rig()
	var env := _find_world_environment(rig).environment
	assert_eq(env.background_mode, Environment.BG_SKY, "Background must be Sky")
	assert_not_null(env.sky, "Environment must have a Sky")
	var mat := env.sky.sky_material
	assert_not_null(mat, "Sky must have a sky_material")
	assert_true(mat is ShaderMaterial, "Sky material must be a ShaderMaterial")
	assert_not_null((mat as ShaderMaterial).shader, "Sky ShaderMaterial must have a shader")


func test_directional_light_with_shadows() -> void:
	var rig := _instantiate_rig()
	var lights := _find_directional_lights(rig)
	assert_gt(lights.size(), 0, "Rig must contain at least one DirectionalLight3D")
	var has_shadow := false
	for light in lights:
		if light.shadow_enabled:
			has_shadow = true
	assert_true(has_shadow, "At least one directional light must cast shadows")
