## Owns the diggable voxel terrain for an Anthesis world.
##
## VoxelWorld wires up a [VoxelLodTerrain] driven by a smooth SDF noise
## generator and a Transvoxel mesher, producing rolling alien hills that the
## player can walk on and carve into. All randomness flows from the project
## [WorldSeed] so a given [member seed_value] always yields the same world.
##
## The terrain child is configured in [method _ready] if it is not already
## present in the scene, so this script is robust whether the node tree is
## built from [code]terrain.tscn[/code] or instantiated bare in a test.
##
## Mutations never happen here — callers obtain a [VoxelTool] via
## [method voxel_tool] (typically wrapped by a [code]TerrainEditService[/code])
## and the command layer drives all edits.
class_name VoxelWorld
extends Node3D

## Base sea level (in world units) about which the terrain undulates.
const TERRAIN_HEIGHT_START := -32.0

## Vertical span (in world units) the SDF noise is mapped across. Combined
## with the noise amplitude this gives roughly 20-40m of relief.
const TERRAIN_HEIGHT_RANGE := 96.0

## Number of fbm octaves for the surface noise.
const NOISE_OCTAVES := 5

## Noise frequency. Lower = wider features; this gives hills tens of
## meters across.
const NOISE_FREQUENCY := 0.0055

## Streaming view distance for the terrain, in world units.
const VIEW_DISTANCE := 384

## Number of LOD levels for the terrain mesh.
const LOD_COUNT := 4

## The deterministic world seed. Two VoxelWorld instances sharing this value
## generate byte-for-byte identical terrain.
@export var seed_value: int = 20260610

var _terrain: VoxelLodTerrain


func _ready() -> void:
	_ensure_terrain()


## Return the [VoxelLodTerrain] driving this world's mesh and collision.
##
## Guaranteed non-null after the node has entered the tree; safe to call
## from setup code that runs before [method _ready] because it lazily
## constructs the terrain on first access.
func terrain_node() -> VoxelLodTerrain:
	_ensure_terrain()
	return _terrain


## Return a [VoxelTool] bound to this world's terrain for read/edit access.
func voxel_tool() -> VoxelTool:
	return terrain_node().get_voxel_tool()


## Sample the terrain surface height at the given XZ world coordinate.
##
## Casts a ray straight down from high above and returns the Y of the first
## solid voxel hit. Returns [constant @GDScript.NAN] when nothing is hit
## (e.g. the chunk has not streamed in yet). Intended for flora placement.
func height_at(xz: Vector2) -> float:
	var tool := voxel_tool()
	var origin := Vector3(xz.x, 1024.0, xz.y)
	var hit := tool.raycast(origin, Vector3.DOWN, 2048.0)
	if hit == null:
		return NAN
	return float(hit.position.y)


## Compute the integer noise seed used by the terrain generator.
##
## Derived deterministically from [member seed_value] through the project
## [WorldSeed] "terrain" stream, so the mapping from world seed to noise is
## stable and uncorrelated with other systems' streams.
static func noise_seed_for(world_seed_value: int) -> int:
	var ws := WorldSeed.new(world_seed_value)
	return ws.derive("terrain").randi()


func _ensure_terrain() -> void:
	if _terrain != null and is_instance_valid(_terrain):
		return
	var existing := get_node_or_null(^"VoxelLodTerrain")
	if existing is VoxelLodTerrain:
		_terrain = existing
	else:
		_terrain = VoxelLodTerrain.new()
		_terrain.name = "VoxelLodTerrain"
		add_child(_terrain)
		if is_inside_tree():
			_terrain.owner = self
	_configure_terrain(_terrain)


func _configure_terrain(terrain: VoxelLodTerrain) -> void:
	terrain.mesher = _build_mesher()
	terrain.generator = _build_generator()
	terrain.material = _load_material()
	terrain.lod_count = LOD_COUNT
	terrain.view_distance = VIEW_DISTANCE
	terrain.generate_collisions = true


func _build_mesher() -> VoxelMesherTransvoxel:
	return VoxelMesherTransvoxel.new()


func _build_generator() -> VoxelGeneratorNoise:
	var gen := VoxelGeneratorNoise.new()
	gen.channel = VoxelBuffer.CHANNEL_SDF
	gen.height_start = TERRAIN_HEIGHT_START
	gen.height_range = TERRAIN_HEIGHT_RANGE
	gen.noise = _build_noise()
	return gen


func _build_noise() -> FastNoiseLite:
	# VoxelGeneratorNoise.noise is typed to Godot's built-in FastNoiseLite, so
	# the ZN_ variant cannot be assigned here. Built-in FastNoiseLite exposes
	# the smooth simplex + FBM controls we want and uses `frequency` directly.
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed_for(seed_value)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = NOISE_OCTAVES
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	noise.frequency = NOISE_FREQUENCY
	return noise


func _load_material() -> Material:
	var mat := load("res://resources/terrain/terrain_material.tres")
	if mat is Material:
		return mat
	return null
