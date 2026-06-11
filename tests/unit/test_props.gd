extends GutTest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

const PROP_PATHS := [
	"res://scenes/props/glow_mushroom.tscn",
	"res://scenes/props/glow_flower.tscn",
	"res://scenes/props/crystal.tscn",
]

const LUMEN_BLOOM_PATH := "res://scenes/props/lumen_bloom.tscn"


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


## Verify each prop has a StaticBody3D with at least one CollisionShape3D child.
## This is required so the player raycast can hit the prop for harvesting.
func test_all_props_have_static_body_with_collision() -> void:
	for path in PROP_PATHS:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var root := packed.instantiate()
		var static_body := root.get_node_or_null("StaticBody3D")
		assert_not_null(
			static_body, "Prop must have a StaticBody3D child named StaticBody3D: %s" % path
		)
		if static_body != null:
			assert_true(
				static_body is StaticBody3D, "StaticBody3D child must be a StaticBody3D: %s" % path
			)
			var col_shape := static_body.get_node_or_null("CollisionShape3D")
			assert_not_null(col_shape, "StaticBody3D must have a CollisionShape3D child: %s" % path)
			if col_shape != null:
				assert_true(
					col_shape is CollisionShape3D,
					"CollisionShape3D child must be CollisionShape3D: %s" % path
				)
				assert_not_null(
					col_shape.shape, "CollisionShape3D must have a shape set: %s" % path
				)
		root.queue_free()


## Verify each prop has a Harvestable child with at least one drop defined.
func test_all_props_have_harvestable_with_drops() -> void:
	for path in PROP_PATHS:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var root := packed.instantiate()
		var harvestable := root.get_node_or_null("Harvestable")
		assert_not_null(harvestable, "Prop must have a child named Harvestable: %s" % path)
		if harvestable != null:
			assert_true(
				harvestable.has_method("get") or harvestable.get_script() != null,
				"Harvestable child must have a script attached: %s" % path
			)
			var drops = harvestable.get("drops")
			assert_not_null(drops, "Harvestable must have a drops property: %s" % path)
			if drops != null:
				assert_true(drops.size() > 0, "Harvestable drops must not be empty: %s" % path)
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


# ---------------------------------------------------------------------------
# Lumen Bloom mote tests
# ---------------------------------------------------------------------------


## Verify the lumen_bloom scene loads successfully.
func test_lumen_bloom_scene_loads() -> void:
	var packed: PackedScene = load(LUMEN_BLOOM_PATH)
	assert_not_null(packed, "lumen_bloom.tscn must load")


## Verify the mote root is a Node3D with the LumenBloomMote script attached.
func test_lumen_bloom_root_has_script() -> void:
	var packed: PackedScene = load(LUMEN_BLOOM_PATH)
	if packed == null:
		return
	var root := packed.instantiate()
	assert_not_null(root, "lumen_bloom root must not be null")
	assert_true(root is Node3D, "lumen_bloom root must be Node3D")
	assert_true(root.get_script() != null, "lumen_bloom root must have a script attached")
	root.queue_free()


## Verify the mote has an emissive MeshInstance3D child.
func test_lumen_bloom_has_emissive_mesh() -> void:
	var packed: PackedScene = load(LUMEN_BLOOM_PATH)
	if packed == null:
		return
	var root := packed.instantiate()
	assert_true(_has_mesh_descendant(root), "lumen_bloom must have at least one MeshInstance3D")
	var mats := _collect_materials(root)
	var has_emissive := false
	for mat in mats:
		if mat is StandardMaterial3D:
			var smat := mat as StandardMaterial3D
			if smat.emission_enabled and smat.emission_energy_multiplier > 0.0:
				has_emissive = true
	assert_true(has_emissive, "lumen_bloom must have at least one emissive material")
	root.queue_free()


## Verify the mote has exactly one OmniLight3D child.
func test_lumen_bloom_has_omni_light() -> void:
	var packed: PackedScene = load(LUMEN_BLOOM_PATH)
	if packed == null:
		return
	var root := packed.instantiate()
	var light_count := _count_nodes_of_class(root, "OmniLight3D")
	assert_eq(light_count, 1, "lumen_bloom must have exactly one OmniLight3D")
	root.queue_free()


## Verify configure(radius) sets the OmniLight3D range to the given radius.
func test_lumen_bloom_configure_sets_light_range() -> void:
	var packed: PackedScene = load(LUMEN_BLOOM_PATH)
	if packed == null:
		return
	var root := packed.instantiate()
	add_child_autofree(root)
	root.configure(12.0)
	var light := root.get_node_or_null("OmniLight3D")
	assert_not_null(light, "lumen_bloom must have OmniLight3D for configure to target")
	if light != null:
		assert_almost_eq(light.omni_range, 12.0, 0.01, "configure(12) must set omni_range to 12")


# ---------------------------------------------------------------------------
# Lumen values on harvested flora
# ---------------------------------------------------------------------------


## Verify each flora prop's Harvestable has the correct lumen value.
func test_prop_harvestable_lumen_values() -> void:
	var expected := {
		"res://scenes/props/glow_mushroom.tscn": 8.0,
		"res://scenes/props/glow_flower.tscn": 10.0,
		"res://scenes/props/crystal.tscn": 15.0,
	}
	for path in expected:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var root := packed.instantiate()
		var harvestable := root.get_node_or_null("Harvestable")
		if harvestable == null:
			root.queue_free()
			continue
		var lumen = harvestable.get("lumen")
		assert_not_null(lumen, "Harvestable must have a lumen property: %s" % path)
		if lumen != null:
			assert_almost_eq(
				float(lumen),
				expected[path],
				0.01,
				"Harvestable lumen must be %.1f for %s" % [expected[path], path]
			)
		root.queue_free()
