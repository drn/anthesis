# Combat System

The combat system covers health pools, damage routing, the two Umbral creature types, their pure AI, the deterministic spawn planner, and the full death/respawn flow. All state mutations flow through `DamageCommand` so the command-layer rule is never broken.

## Key Files

| File | Role |
|---|---|
| `scripts/systems/combat/health.gd` | `Health` — bounded HP pool, signals `changed` / `died` |
| `scripts/systems/combat/combat_service.gd` | `CombatService` — id-keyed registry + damage router |
| `scripts/core/commands/damage_command.gd` | `DamageCommand` — command-layer entry point for every hit |
| `scripts/core/combat/creature_def.gd` | `CreatureDef` — exported resource schema |
| `scripts/systems/combat/creature_registry.gd` | `CreatureRegistry` — scans `resources/creatures/` |
| `scripts/systems/combat/umbral_ai.gd` | `UmbralAI` — pure deterministic state machine |
| `scripts/systems/combat/umbral.gd` | `Umbral` — `CharacterBody3D` that applies AI decisions |
| `scripts/systems/combat/spawn_system.gd` | `SpawnSystem` — pure spawn planner |
| `resources/creatures/voidmoth.tres` | Fast, fragile; violet core |
| `resources/creatures/shardling.tres` | Slow, tanky; blue core |
| `tests/unit/test_health.gd` | Health pool unit tests |
| `tests/unit/test_combat_service.gd` | Service routing unit tests |
| `tests/unit/test_umbral_ai.gd` | AI state machine unit tests |
| `tests/unit/test_spawn_system.gd` | Spawn planner unit tests |
| `tests/integration/test_world_combat.gd` | Full-world combat integration |

## How It Works

### Health → CombatService → DamageCommand flow

`Health` (`RefCounted`) is a pure HP pool. `take_damage(amount)` reduces current HP, emits `changed`, and emits `died` exactly once when HP first reaches zero. Subsequent hits on a dead pool are silent no-ops.

`CombatService` (`RefCounted`) holds two parallel dictionaries: `_health_by_id` and `_node_by_id`, keyed by `node.get_instance_id()`. Registration is done at spawn time by `World`:

```
combat.register(player.get_instance_id(), player_health, player)
combat.register(umbral.get_instance_id(), umbral.health(), umbral)
```

`apply_damage(target_id, amount, knockback)` finds the Health, calls `take_damage`, adds `knockback` to the node's velocity if the node is a `CharacterBody3D`, and emits `damage_applied(target_id, dealt)`.

`DamageCommand` wraps `(target_id, amount, knockback)` and routes to `ctx.combat.apply_damage(...)` in `apply(ctx)`. This is the only legal path to damage a combatant.

### CreatureDef .tres resources

Every creature is a `CreatureDef` resource under `resources/creatures/`. Key exported fields:

| Field | Voidmoth | Shardling |
|---|---|---|
| `max_health` | 12.0 | 30.0 |
| `move_speed` | 3.2 m/s | 2.4 m/s |
| `attack_damage` | 4.0 | 9.0 |
| `attack_range` | 1.6 m | 1.9 m |
| `aggro_range` | 14.0 m | 11.0 m |
| `attack_cooldown_ticks` | 12 | 18 |
| `wander_radius` | 6.0 m | 6.0 m |
| `drops` | 1x glow_spore | 2x crystal_shard |
| `lumen_reward` | 4.0 | 8.0 |
| `core_color` | violet `(0.7, 0.3, 1.0)` | cyan `(0.3, 0.7, 1.0)` |

`CreatureRegistry` scans `res://resources/creatures/` on `_init`, loading any `.tres` or `.tres.remap` file that is a `CreatureDef` with a non-empty `id`.

### UmbralAI State Machine

`UmbralAI` (`RefCounted`) is purely functional — no scene tree, no node references. Each `tick(self_pos, target_pos, tick_index)` call returns a `Dictionary`:

```gdscript
{"state": StringName, "move_dir": Vector3, "attack": bool}
```

Five states; transitions are distance-driven each tick:

| State | Condition | `move_dir` | `attack` |
|---|---|---|---|
| `&"dead"` | `mark_dead()` called | zero | false |
| `&"wander"` | dist > `aggro_range` and not at leg goal | toward wander goal (XZ, normalized) | false |
| `&"idle"` | in wander leg, within `WANDER_ARRIVE_DISTANCE` (0.6 m) | zero | false |
| `&"chase"` | dist <= `aggro_range`, dist > `attack_range` | toward target (XZ, normalized) | false |
| `&"attack"` | dist <= `attack_range` (XZ plane only; Y ignored) | zero | true only when cooldown elapsed |

Wander cadence: a fresh "leg" (random angle + radius within `wander_radius` of home) is chosen every `WANDER_LEG_TICKS` (30) ticks via the injected `RandomNumberGenerator`. The home position is set from `self_pos` on the first tick.

Attack gating: `attack` is `true` only when `tick_index - _last_attack_tick >= attack_cooldown_ticks`. The initial `_last_attack_tick` is `-1_000_000`, so the very first in-range tick always strikes.

All randomness passes through the `rng` injected at construction — same seed, same sequence, every time.

### Umbral (the scene node)

`Umbral` (`CharacterBody3D`) wraps the AI. Setup via `setup(def, clock, rng, target)`:

1. Constructs an `UmbralAI` and a `Health` pool from the def.
2. Connects `Health.died` → `_on_died`.
3. Subscribes `SimulationClock.ticked` → `_on_tick`.

Each clock tick: `_on_tick` calls `_ai.tick(...)`, caches `_move_dir` and `_wants_attack`. If `attack` is true and the target is still in range, `attack_landed(damage)` is emitted.

Each physics frame: `_physics_process` applies gravity + blends velocity toward `_move_dir * move_speed` using `ACCEL` (10.0) as a lerp factor.

Body is built procedurally in `_build_body()`: a squashed dark sphere (body, radius `BODY_RADIUS * body_scale`), a bright emissive core sphere, and an `OmniLight3D`.

### Death / Respawn Flow

**Creature death:**
1. `Health.died` fires → `_on_died()`.
2. `_dying = true`, AI marked dead, collision disabled, movement zeroed.
3. `_play_dissolve()` creates a tween: core emission spikes to 9.0, scale tweens to `Vector3.ZERO` over `DISSOLVE_TIME` (0.6 s), light fades.
4. On tween completion: `perished.emit(def, death_pos)`, then `queue_free()`.
5. `World._on_umbral_perished(def, at)` awards drops via `LootService` and adds `lumen_reward` to the well.

**Player death:**
1. `player_health.died` → `World._on_player_died()`.
2. `_player_dead = true`. HUD `show_death(respawn_in_s)` is called.
3. A `SceneTreeTimer` fires after `RESPAWN_DELAY` (4.0 s) → `_on_respawn_timer()`.
4. Player position reset to `_spawn_point`, health restored via `Health.heal(max_health())`, `_player_dead = false`, HUD `hide_death()`.

### SpawnSystem

`SpawnSystem` (`RefCounted`) is pure logic. Constants:

| Constant | Value | Meaning |
|---|---|---|
| `SPAWN_INTERVAL_TICKS` | 40 | Plan only on multiples of 40 |
| `POPULATION_CAP` | 6 | No spawn when alive_count >= 6 |
| `MIN_GLOW_DISTANCE` | 9.0 m | Candidate rejected if within 9 m of any glow point |
| `RING_MIN` | 20.0 m | Inner radius of spawn ring |
| `RING_MAX` | 42.0 m | Outer radius of spawn ring |

`plan(tick, player_pos, alive_count, glow_points, height_fn)` returns an array of `{def, position}` dicts (empty or one entry per round). Draw order is deterministic: angle, radius, species index. Glow points come from flora props and active Lumen Blooms; the darkness rule rejects any candidate within `MIN_GLOW_DISTANCE` on the XZ plane.

The RNG is derived from `WorldSeed.derive("spawning")` so spawn patterns are world-seed-reproducible.

**Despawn:** `World._on_combat_tick` also despawns any Umbral farther than `UMBRAL_DESPAWN_DISTANCE` (60 m) from the player each tick.

## How to Extend

### Adding a new creature

1. Duplicate `resources/creatures/voidmoth.tres` → `resources/creatures/<name>.tres`.
2. Set `id`, `display_name`, and tune the stats. The creature is automatically picked up by `CreatureRegistry` on next boot — no code changes.
3. To customize the visual beyond scale/color, subclass `Umbral` and override `_build_body()`, then load your scene in `World._build_combat()`.
4. Write a test in `tests/unit/test_creature_resources.gd` asserting the new resource loads and has a valid id.

### Adding a new hit source (e.g. spell AOE)

1. Create a new `WorldCommand` subclass (e.g. `AoeCommand`).
2. In `apply(ctx)`, iterate nearby combatants from the scene tree and call `ctx.combat.apply_damage(id, amount, knockback)` for each.
3. Submit via `world.router().submit(AoeCommand.new(...))`.
4. Add a `CommandCodec.encode/decode` branch if the command must replicate in co-op.
5. Test with `test_combat_service.gd` patterns (register a `Health`, confirm `apply_damage` returns the dealt amount).

## Testing Notes

- `test_health.gd`: pool math, `died` fires exactly once, subsequent hits are no-ops.
- `test_combat_service.gd`: routing, knockback on `CharacterBody3D`, unknown-id safety, `damage_applied` signal.
- `test_umbral_ai.gd`: all five states, boundary conditions on all three distance cutoffs, wander leg cadence, cooldown gate at exact boundary tick, determinism across 200 ticks.
- `test_spawn_system.gd`: interval gating, population cap, single-spawn-per-round guarantee, darkness rule (XZ-only), ring bounds across 200 seeds, NAN height rejection, determinism.
- Pattern to copy for a new creature resource: `test_creature_resources.gd` — assert `id != ""`, `max_health > 0`, `drops.size() >= 0`.

## Gotchas

- Distance in UmbralAI is XZ-plane-only (`Vector2(to_target.x, to_target.z).length()`). A target directly overhead is in attack range regardless of vertical gap.
- `Umbral.setup()` is safe to call before the node enters the tree; `_build_body()` runs immediately. The clock subscription is deferred until setup so there is no tick before the AI is ready.
- `CombatService` tolerates unknown IDs everywhere. Umbrals can despawn between a hit being queued and applied without crashing.
- The `_spawn_counter` in `World` is not the same as `SpawnSystem`; the spawner only plans, the counter tracks actual instantiations for block naming.
- `lumen_reward` is added directly to the `LumenWell` in `World._on_umbral_perished`, bypassing the command bus (it is a presentation-side credit, not a world mutation).
