extends GutTest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const PROP_PATHS := [
	"res://scenes/props/glow_mushroom.tscn",
	"res://scenes/props/glow_flower.tscn",
	"res://scenes/props/crystal.tscn",
]


func _count_nodes_of_class(node: Node, class_str: String) -> int:
	var count := 0
	if node.get_class() == class_str or node.is_class(class_str):
		count += 1
	for child in node.get_children():
		count += _count_nodes_of_class(child, class_str)
	return count


func _has_mesh_descendant(node: Node) -> bool:
	if node.is_class("MeshInstance3D") or node.is_class("CSGShape3D"):
		return true
	for child in node.get_children():
		if _has_mesh_descendant(child):
			return true
	return false


func _collect_materials(node: Node) -> Array:
	var mats := []
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for s in range(mi.get_surface_override_material_count()):
			var mat := mi.get_surface_override_material(s)
			if mat != null:
				mats.append(mat)
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s)
				if mat != null:
					mats.append(mat)
	for child in node.get_children():
		mats.append_array(_collect_materials(child))
	return mats


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


func test_all_props_load() -> void:
	for path in PROP_PATHS:
		var packed: PackedScene = load(path)
		assert_not_null(packed, "Scene must load: %s" % path)


func test_all_props_root_not_null() -> void:
	for path in PROP_PATHS:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var root := packed.instantiate()
		assert_not_null(root, "Root must not be null for %s" % path)
		root.queue_free()


func test_all_props_have_mesh_descendant() -> void:
	for path in PROP_PATHS:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var root := packed.instantiate()
		assert_true(
			_has_mesh_descendant(root),
			"Prop must have at least one MeshInstance3D or CSGShape3D: %s" % path
		)
		root.queue_free()


func test_all_props_have_exactly_one_omni_light() -> void:
	for path in PROP_PATHS:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var root := packed.instantiate()
		var light_count := _count_nodes_of_class(root, "OmniLight3D")
		assert_eq(
			light_count,
			1,
			"Prop must have exactly one OmniLight3D, found %d in %s" % [light_count, path]
		)
		root.queue_free()


## Verify every material that declares itself emissive actually has
## emission_enabled = true and a positive emission_energy_multiplier.
func test_all_emissive_materials_have_emission_enabled() -> void:
	var found_at_least_one_emissive := false
	for path in PROP_PATHS:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var root := packed.instantiate()
		var mats := _collect_materials(root)
		for mat in mats:
			if mat is StandardMaterial3D:
				var smat := mat as StandardMaterial3D
				if smat.emission_enabled:
					found_at_least_one_emissive = true
					assert_true(
						smat.emission_energy_multiplier > 0.0,
						"emission_enabled mat must have energy > 0 in %s" % path
					)
		root.queue_free()
	assert_true(
		found_at_least_one_emissive, "At least one emissive material must exist across all props"
	)
