# Flora

Bioluminescent flora is the world's life, light, and economy: props are scattered
deterministically at boot, harvested for items **and** lumen, and their glow defines
the safe zones where Umbrals cannot spawn.

## Key files

| File | Role |
|------|------|
| `scripts/systems/flora/flora_scatter.gd` | Deterministic placement (`FloraScatter`) |
| `scripts/systems/flora/harvestable.gd` | Per-prop drops + lumen component (`Harvestable`) |
| `scripts/systems/flora/lumen_bloom_mote.gd` | Player-cast light mote (`LumenBloomMote`) |
| `scenes/props/glow_mushroom.tscn` | Prop: cyan cap, drops `glow_spore` x2, lumen 8 |
| `scenes/props/glow_flower.tscn` | Prop: magenta petals, drops `lumen_petal` x2, lumen 10 |
| `scenes/props/crystal.tscn` | Prop: violet cluster, drops `crystal_shard` x3, lumen 15 |
| `scenes/props/lumen_bloom.tscn` | The cast mote scene |

## How it works

- `FloraScatter.compute_placements(rng, count, area_extent)` is a **pure static
  function** returning `Array[Transform3D]` — positions in an XZ square, random yaw,
  scale jitter 0.7–1.4. Runtime `scatter(world_seed, height_fn)` instantiates props
  at those placements with Y from `height_fn` (a `Callable` into
  `VoxelWorld.height_at`); placements whose height is `NAN` (chunk not streamed) are
  skipped. World scatters once terrain reports a surface (see `World._process`).
- Each prop root carries a `Harvestable` child (`drops: Array[ItemAmount]`,
  `lumen: float`, `prompt`) and a `StaticBody3D` so the player's raycast can hit it.
  Pressing E routes a `HarvestCommand` through the bus: drops are awarded via
  `LootService`, lumen via `ctx.lumen_gain`, then the prop is freed (validated to be
  a `FloraScatter` descendant first).
- **Glow points**: flora prop positions + active bloom motes are collected by
  `World._collect_glow_points()` each spawn-planning round; `SpawnSystem` rejects
  Umbral candidates within 9 m — light is literally safety.

## LumenBloomMote

Spawned by the `lumen_bloom` ability (see [MAGIC.md](MAGIC.md)): a small emissive
orb + `OmniLight3D`. `configure(radius)` sets the light range from the ability's
`magnitude` (6.0). It pulses gently, self-frees after `lifetime_s` (25 s), and while
alive it counts as a glow point — casting light is a tactical anti-Umbral act.

## Testing

`tests/unit/test_flora_scatter.gd` (placement determinism: same WorldSeed stream →
identical transforms), `tests/unit/test_props.gd` (prop structure: meshes, omni
light, Harvestable with non-empty drops, mote configure).

## Gotchas

- Placement is deterministic, but **node names are not** — never address flora props
  by name. The multiplayer codec targets them by child index (see
  [MULTIPLAYER.md](MULTIPLAYER.md)).
- Adding a prop: build the scene with an emissive mesh + `OmniLight3D` +
  `StaticBody3D` collider + `Harvestable` child, then add it to `World`'s
  `_build_flora()` prop list and to the props tests.
