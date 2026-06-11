# Terrain System

Anthesis uses Zylann's `godot_voxel` module to produce a smooth, fully diggable
SDF landscape. `VoxelWorld` owns the terrain node and its configuration;
`TerrainEditService` is the only code that mutates voxel data; all edits are
driven through the command layer.

---

## Key Files

| File | Role |
|------|------|
| `scripts/systems/terrain/voxel_world.gd` | Wires and owns the `VoxelLodTerrain` |
| `scripts/systems/terrain/edit_service.gd` | Single mutation surface (`dig_sphere` / `place_sphere`) |
| `resources/terrain/terrain_material.tres` | Triplanar material loaded at runtime |
| `scenes/world/terrain.tscn` | Scene that places a `VoxelWorld` node |
| `tests/unit/test_voxel_world.gd` | Structure + determinism tests |
| `tests/unit/test_terrain_edit_service.gd` | Edit-routing tests against a duck-typed fake tool |

---

## How It Works

### VoxelWorld

`VoxelWorld` (`class_name VoxelWorld`, `extends Node3D`) lazily constructs or
adopts a `VoxelLodTerrain` child called `"VoxelLodTerrain"` in `_ensure_terrain`,
which runs from both `_ready` and the first call to `terrain_node()`. This makes
the class work whether it is instantiated from `terrain.tscn` or spawned bare in
a test.

`_configure_terrain` sets four things on the terrain node every time it is built:

| Property | Value |
|----------|-------|
| `mesher` | `VoxelMesherTransvoxel` — smooth Transvoxel surface |
| `generator` | `VoxelGeneratorNoise` writing `CHANNEL_SDF` |
| `material` | `res://resources/terrain/terrain_material.tres` (triplanar) |
| `lod_count` | `LOD_COUNT = 4` |
| `view_distance` | `VIEW_DISTANCE = 384` world units |
| `generate_collisions` | `true` — player can walk and raycasts hit |

**Noise parameters** (all constants on `VoxelWorld`):

| Constant | Value | Meaning |
|----------|-------|---------|
| `TERRAIN_HEIGHT_START` | `-32.0` | Sea-level offset |
| `TERRAIN_HEIGHT_RANGE` | `96.0` | Vertical span mapped over |
| `NOISE_OCTAVES` | `5` | fbm octave count |
| `NOISE_FREQUENCY` | `0.0055` | Low = wide hills (tens of metres across) |
| `fractal_lacunarity` | `2.0` | Fixed in `_build_noise` |
| `fractal_gain` | `0.5` | Fixed in `_build_noise` |

The noise type is `TYPE_SIMPLEX_SMOOTH` with `FRACTAL_FBM`.

**Determinism.** The integer noise seed is derived through `WorldSeed` stream
`"terrain"`:

```gdscript
static func noise_seed_for(world_seed_value: int) -> int:
    var ws := WorldSeed.new(world_seed_value)
    return ws.derive("terrain").randi()
```

Two `VoxelWorld` instances sharing the same `seed_value` export will produce
byte-for-byte identical terrain.

**`height_at(xz: Vector2) -> float`** casts a ray straight down from Y=1024 over
2048 units and returns `hit.position.y` of the first solid voxel. Returns `NAN`
when the chunk has not streamed in yet (e.g. far-out flora placement). Callers
**must** check for `NAN` before using the result — `is_nan(y)` is the correct
guard. Do not use `== NAN`.

### TerrainEditService

`TerrainEditService` (`class_name TerrainEditService`, `extends RefCounted`) is
the only place that calls `VoxelTool.do_sphere`. It is dependency-injected: the
constructor takes a `Callable` that returns a `VoxelTool`-like object, so tests
substitute a duck-typed fake with no voxel engine required.

```gdscript
# Production wiring (in World):
var svc := TerrainEditService.new(func(): return voxel_world.voxel_tool())

# Test wiring:
var fake := FakeVoxelTool.new()
var svc := TerrainEditService.new(func() -> Object: return fake)
```

`dig_sphere(center, radius)` sets `tool.mode = VoxelTool.MODE_REMOVE` then calls
`tool.do_sphere(center, radius)`.

`place_sphere(center, radius)` sets `tool.mode = VoxelTool.MODE_ADD` then calls
`tool.do_sphere(center, radius)`.

If the provider Callable is invalid or returns null, `push_error` is called and
the method returns early (no crash).

### Triplanar Material

The terrain uses a single `.tres` material at `resources/terrain/terrain_material.tres`.
When the resource does not exist (e.g. a bare test environment), `_load_material`
returns `null` and Godot uses the default white material — safe, intentional.

---

## FastNoiseLite Not ZN_ — the Gotcha

`VoxelGeneratorNoise.noise` is typed to Godot's built-in `FastNoiseLite`, **not**
the `ZN_FastNoiseLite` type exported by the voxel module. Assigning a `ZN_` variant
here will be silently rejected or error. Always construct a plain `FastNoiseLite.new()`.

---

## Apple Silicon Scalar Fallback

The SIMD noise path inside `godot_voxel` is x86-only. On Apple Silicon (ARM64)
the engine falls back to a scalar implementation automatically. Performance is
adequate at solo-player chunk distances (view distance 384) but will degrade at
larger multiplayer radii. This is a known v0 trade-off — no code change required.

---

## How to Extend

**Change noise shape** — modify the constants (`NOISE_FREQUENCY`, `NOISE_OCTAVES`,
`TERRAIN_HEIGHT_RANGE`) on `VoxelWorld`. Changing `TERRAIN_HEIGHT_START` shifts
the sea level. Because the seed derivation is stable, any noise tweak requires
regenerating worlds (seeds are not forwards-compatible across noise changes).

**Add a new biome layer** — the current `VoxelGeneratorNoise` is single-layer.
Replace `_build_generator` with a `VoxelGeneratorGraph` or a custom generator
that combines multiple noise layers; the rest of the pipeline is unchanged.

**Surface query from a new system** — call `voxel_world.height_at(xz)` and handle
`NAN`. Never store the result beyond the current frame — chunks can stream out.

**Stub terrain in a new test** — subclass `TerrainEditService`, override
`dig_sphere`/`place_sphere` to record calls, and inject the stub into a
`WorldContext`. See `tests/unit/test_commands.gd` (`RecordingEditService`) for the
pattern.

---

## Testing Notes

`tests/unit/test_voxel_world.gd` loads `terrain.tscn`, checks mesher type,
generator channel, collision flag, LOD count, and seed determinism. Instantiates
the scene in-tree with `add_child_autofree`.

`tests/unit/test_terrain_edit_service.gd` uses a duck-typed `FakeVoxelTool` (inner
class with a `mode` field and a `calls` array) — copy this pattern for any new
system that needs to unit-test terrain edits without the voxel engine.

---

## Gotchas

- `height_at` returns `NAN` when the chunk is not loaded — always guard with `is_nan`.
- `VoxelGeneratorNoise.noise` takes built-in `FastNoiseLite`, **not** `ZN_FastNoiseLite`.
- Collisions are generated asynchronously by `godot_voxel`; immediately after a dig,
  the physics shape may lag one update behind the mesh. Do not rely on same-frame
  collision accuracy for freshly edited voxels.
- Never call `TerrainEditService` directly from presentation code — route through a
  command (`DigCommand` / `PlaceCommand`) via `CommandBus`.
