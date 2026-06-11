extends GutTest

# ---------------------------------------------------------------------------
# Tests for the VoxelWorld terrain (contract #1).
# ---------------------------------------------------------------------------

const TERRAIN_SCENE := "res://scenes/world/terrain.tscn"


func _instance(seed_value: int = 20260610) -> VoxelWorld:
	var world: VoxelWorld = load(TERRAIN_SCENE).instantiate()
	# Set the seed before the node enters the tree so _ready() builds the
	# generator with this value.
	world.seed_value = seed_value
	add_child_autofree(world)
	return world


# ---------------------------------------------------------------------------
# Structure
# ---------------------------------------------------------------------------


## The scene root is a VoxelWorld exposing a VoxelLodTerrain.
func test_terrain_node_is_voxel_lod_terrain() -> void:
	var world := _instance()
	var terrain := world.terrain_node()
	assert_not_null(terrain, "terrain_node() must return a node")
	assert_true(terrain is VoxelLodTerrain, "terrain must be a VoxelLodTerrain")


## The mesher is Transvoxel for smooth SDF surfaces.
func test_mesher_is_transvoxel() -> void:
	var world := _instance()
	var terrain := world.terrain_node()
	assert_true(terrain.mesher is VoxelMesherTransvoxel, "mesher must be VoxelMesherTransvoxel")


## The generator is a noise generator writing the SDF channel.
func test_generator_is_noise_with_sdf_channel() -> void:
	var world := _instance()
	var terrain := world.terrain_node()
	assert_true(terrain.generator is VoxelGeneratorNoise, "generator must be VoxelGeneratorNoise")
	assert_eq(
		terrain.generator.channel, VoxelBuffer.CHANNEL_SDF, "generator must target the SDF channel"
	)


## Collisions are generated so the player can walk and raycasts hit.
func test_collisions_enabled() -> void:
	var world := _instance()
	var terrain := world.terrain_node()
	assert_true(terrain.generate_collisions, "generate_collisions must be true")


## Several LOD levels are configured.
func test_lod_count_configured() -> void:
	var world := _instance()
	var terrain := world.terrain_node()
	assert_eq(terrain.lod_count, VoxelWorld.LOD_COUNT, "lod_count must match contract")


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------


## Same seed_value => identically-seeded generator noise.
func test_same_seed_same_noise_seed() -> void:
	var a := _instance(12345)
	var b := _instance(12345)
	# terrain_node() builds the generator lazily using seed_value.
	var noise_a: FastNoiseLite = a.terrain_node().generator.noise
	var noise_b: FastNoiseLite = b.terrain_node().generator.noise
	assert_eq(noise_a.seed, noise_b.seed, "Same seed_value must yield same noise seed")


## Different seed_value => different generator noise seed.
func test_different_seed_different_noise_seed() -> void:
	var a := _instance(111)
	var b := _instance(222)
	var noise_a: FastNoiseLite = a.terrain_node().generator.noise
	var noise_b: FastNoiseLite = b.terrain_node().generator.noise
	assert_ne(noise_a.seed, noise_b.seed, "Different seed_value must yield different noise seed")


## The static noise-seed mapping is deterministic and seed-sensitive.
func test_noise_seed_mapping_deterministic() -> void:
	assert_eq(
		VoxelWorld.noise_seed_for(777),
		VoxelWorld.noise_seed_for(777),
		"noise_seed_for must be pure"
	)
	assert_ne(
		VoxelWorld.noise_seed_for(1),
		VoxelWorld.noise_seed_for(2),
		"noise_seed_for must differ for different seeds"
	)
