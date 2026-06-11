# Command System

Every mutation of authoritative world state — digging, crafting, casting, dealing
damage — is expressed as a `WorldCommand` and routed through `CommandBus` (offline)
or `CommandRouter` (online). No input handler, player script, or presentation node
ever touches world state directly.

---

## Key Files

| File | Role |
|------|------|
| `scripts/core/commands/world_command.gd` | Abstract base |
| `scripts/core/commands/command_bus.gd` | Execution entry point |
| `scripts/core/commands/world_context.gd` | Dependency bundle passed to every command |
| `scripts/core/commands/dig_command.gd` | Voxel removal + dig loot |
| `scripts/core/commands/place_command.gd` | Voxel addition |
| `scripts/core/commands/craft_command.gd` | Recipe execution |
| `scripts/core/commands/harvest_command.gd` | Prop harvest + lumen gather |
| `scripts/core/commands/cast_command.gd` | Magic ability cast |
| `scripts/core/commands/damage_command.gd` | Hit routing |
| `scripts/core/commands/place_block_command.gd` | Sequencer block placement |
| `scripts/core/commands/remove_block_command.gd` | Sequencer block removal + refund |
| `scripts/core/commands/cycle_note_command.gd` | Note Block pitch cycle |
| `scripts/core/commands/toggle_channel_command.gd` | Toggle a named metal channel (vigor / keensight) |
| `scripts/core/commands/set_flare_command.gd` | Enable / disable flare on all active channels |
| `scripts/core/commands/throw_coin_command.gd` | Consume one ferric coin from inventory and spawn it |
| `scripts/core/net/command_codec.gd` | Wire serialization for replication |
| `scripts/core/net/command_log.gd` | Ordered, bounded replication log |
| `scripts/systems/net/command_router.gd` | Authority-aware submit seam |
| `tests/unit/test_commands.gd` | Core command tests + stub patterns |
| `tests/unit/test_cast_command.gd` | CastCommand + HarvestCommand lumen tests |
| `tests/unit/test_block_commands.gd` | PlaceBlock / RemoveBlock / CycleNote |
| `tests/unit/test_toggle_channel_command.gd` | ToggleChannelCommand + SetFlareCommand routing |
| `tests/unit/test_throw_coin_command.gd` | ThrowCoinCommand — coin consume + spawn args |
| `tests/unit/test_command_codec.gd` | Encode/decode/range-gate tests |
| `tests/unit/test_command_router.gd` | Router authority/routing tests |
| `tests/unit/test_command_log.gd` | Log append/eviction/clear tests |

---

## Core Types

### WorldCommand

```gdscript
class_name WorldCommand
extends RefCounted

func apply(_ctx: WorldContext) -> void  # abstract — must override
```

All parameters are captured in `_init`. `apply` acts on the world exclusively
through services exposed on `WorldContext`. Commands never call `get_node` or
touch the scene tree directly.

### WorldContext

The dependency bundle. Every field is optional (may be null / invalid Callable) so
commands degrade gracefully when only part of the context is wired.

| Field | Type | Used by |
|-------|------|---------|
| `terrain_edit` | `TerrainEditService` | DigCommand, PlaceCommand |
| `registry` | `ItemRegistry` | (injected for service use) |
| `inventory` | `Inventory` | CraftCommand, RemoveBlockCommand |
| `crafting` | `CraftingService` | CraftCommand |
| `loot` | `LootService` | DigCommand, HarvestCommand |
| `flora_harvest` | `Callable(node)` | HarvestCommand |
| `magic` | `MagicSystem` | CastCommand |
| `ability_effects` | `Dictionary[StringName, Callable]` | CastCommand |
| `lumen_gain` | `Callable(amount: float)` | HarvestCommand |
| `combat` | `CombatService` | DamageCommand |
| `block_place` | `BlockPlacementService` | PlaceBlockCommand, RemoveBlockCommand, CycleNoteCommand |
| `status` | `StatusEffectSystem` | DamageCommand (vigor resist), ToggleChannelCommand |
| `channels` | `ChannelSystem` | ToggleChannelCommand, SetFlareCommand |
| `metal_reserves` | `MetalReserves` | CastCommand (auto-swallow pre-gate) |
| `coin_spawn` | `Callable(origin: Vector3, velocity: Vector3)` | ThrowCoinCommand |

### CommandBus

```gdscript
class_name CommandBus
extends RefCounted

signal command_executed(cmd: WorldCommand)

func _init(ctx: WorldContext) -> void
func execute(cmd: WorldCommand) -> void
```

`execute` calls `cmd.apply(_ctx)` then emits `command_executed`. This is the only
place that calls `apply`; nothing else invokes a command directly.

---

## Full Command Catalog

### DigCommand

```gdscript
func _init(center: Vector3, radius: float)
func apply(ctx: WorldContext)
```

Calls `ctx.terrain_edit.dig_sphere(center, radius)`, then calls
`ctx.loot.award_dig_loot(center, radius)` when `ctx.loot != null`.
Replicable (wire tag `"dig"`).

### PlaceCommand

```gdscript
func _init(center: Vector3, radius: float)
func apply(ctx: WorldContext)
```

Calls `ctx.terrain_edit.place_sphere(center, radius)`. No loot.
Replicable (wire tag `"place"`).

### CraftCommand

```gdscript
func _init(recipe: Recipe)
func apply(ctx: WorldContext)
```

Calls `ctx.crafting.craft(ctx.inventory, recipe)`. Silent no-op when
`ctx.crafting` or `ctx.inventory` is null. Not replicable (client-local).

### HarvestCommand

```gdscript
func _init(target: Node, drops: Array[ItemAmount])
func apply(ctx: WorldContext)
```

Order: (1) `ctx.loot.award_harvest_loot(drops)`, (2) lumen gather from the
target's `Harvestable` child via `ctx.lumen_gain`, (3) `ctx.flora_harvest.call(target)`.
Each step is independently guarded. Replicable (wire tag `"harvest"`; encoded
with the target's flora child index and the drops array).

### CastCommand

```gdscript
func _init(ability: AbilityDef, target: Vector3)
func apply(ctx: WorldContext)
```

Looks up `ctx.ability_effects[ability.kind]`; if found and valid, calls
`ctx.magic.try_cast(ability, func() -> bool: return effect.call(ability, target))`.
If no effect is registered, routes through `try_cast` with a failing lambda so the
rule gate still runs (`cast_failed(&"no_effect")`, nothing spent). Silent no-op
when `ctx.magic` is null. Not replicable (client-local).

### DamageCommand

```gdscript
func _init(target_id: int, amount: float, knockback := Vector3.ZERO)
func apply(ctx: WorldContext)
```

Calls `ctx.combat.apply_damage(target_id, amount, knockback)`. Silent no-op
when `ctx.combat` is null. Not replicable (client-local).

### PlaceBlockCommand

```gdscript
func _init(item_id: StringName, position: Vector3)
func apply(ctx: WorldContext)
```

Calls `ctx.block_place.place(item_id, position)`. No-op when `ctx.block_place`
is null. Replicable (wire tag `"pblock"`).

### RemoveBlockCommand

```gdscript
func _init(target: Node)
func apply(ctx: WorldContext)
```

Calls `ctx.block_place.remove(target)` → returns item id; when non-empty and
`ctx.inventory != null`, calls `ctx.inventory.add(id, 1)`. Replicable (wire
tag `"rblock"`; target encoded as block node name).

### CycleNoteCommand

```gdscript
func _init(target: Node)
func apply(_ctx: WorldContext)
```

Checks `target.is_in_group(&"note_blocks")` and `target.has_method("cycle_pitch")`,
then calls `target.cycle_pitch()`. No-op for non-note-block nodes. Does not use
`ctx` at all. Replicable (wire tag `"cycle"`; target encoded as block node name).

### ToggleChannelCommand

```gdscript
func _init(channel_id: StringName)
func apply(ctx: WorldContext)
```

Calls `ctx.channels.toggle(channel_id)`. Silent no-op when `ctx.channels` is null.
Not replicable (client-local). Used for G → vigor and T → keensight.

### SetFlareCommand

```gdscript
func _init(active: bool)
func apply(ctx: WorldContext)
```

Calls `ctx.channels.set_flare(active)`. Silent no-op when `ctx.channels` is null.
Not replicable (client-local). Submitted on Shift press (`active = true`) and
release (`active = false`).

### ThrowCoinCommand

```gdscript
func _init(origin: Vector3, velocity: Vector3)
func apply(ctx: WorldContext)
```

Requires `ctx.inventory` and a valid `ctx.coin_spawn` Callable. Calls
`ctx.inventory.remove(&"ferric_coin", 1)` — aborts silently if the return value
is 0 (no coin in inventory). On success, calls `ctx.coin_spawn.call(origin, velocity)`,
which instantiates `ferric_coin.tscn`, positions it, sets its `linear_velocity`, and
connects its `struck` signal to the damage handler. Not replicable (client-local).

---

## The Router Seam (Offline / Online)

In production all player-intent commands flow through `CommandRouter.submit(cmd)`,
never directly to `CommandBus.execute`. The router is authority-aware:

```
offline                 -> bus.execute(cmd)
online host + replic.   -> validate, bus.execute, log.append, broadcast commit_command
online host + local     -> bus.execute  (crafting, magic, combat stay local on host too)
online client + replic. -> rpc_id(1, "request_command", encoded)
online client + local   -> bus.execute  (inventory/magic/craft/combat stay client-side)
```

**Replicable** commands (shared-world mutations): `DigCommand`, `PlaceCommand`,
`PlaceBlockCommand`, `RemoveBlockCommand`, `CycleNoteCommand`, `HarvestCommand`.

**Client-local** (not replicable): `CastCommand`, `DamageCommand`, `CraftCommand`,
`ToggleChannelCommand`, `SetFlareCommand`, `ThrowCoinCommand`.

`CommandRouter` delegates to `CommandCodec` for encode/decode. All `@rpc` bodies
are one-liners that delegate to plain non-RPC methods (`_commit`, `_handle_request`,
`_handle_commit`, `_build_state`, `_handle_state`). Transport funnels through
`_send(method, args, peer)` — a test double overrides this to capture traffic.

---

## CommandCodec Wire Format

Pure static encode/decode. Fields are range-gated on the host.

| Tag | Shape | Notes |
|-----|-------|-------|
| `"dig"` | `{t, c:[x,y,z], r:radius}` | radius outside 0.1..10.0 rejected (decode -> null) |
| `"place"` | `{t, c:[x,y,z], r:radius}` | same range |
| `"pblock"` | `{t, item:"note_block", c:[x,y,z]}` | any item id |
| `"rblock"` | `{t, path:"Block_3"}` | node name under `blocks_container()` |
| `"cycle"` | `{t, path:"Block_3"}` | same lookup |
| `"harvest"` | `{t, idx:2, drops:[["seed",1],...]}` | flora child index |

`encode` returns `{}` for non-replicable or unresolvable commands.
`decode` returns `null` for unknown tags, bad types, out-of-range numerics, or
targets that no longer exist in the world.

### CommandLog

Ordered, bounded (`MAX_ENTRIES = 5000`) list of committed wire dictionaries.
The host appends every committed command's encoded form here. A joining client
requests `{seed, log}` via `request_state`; `World.rebuild_for_session` replays
each entry through the bus (not the router, so it applies without re-broadcasting).
Past 5000 entries, oldest entries are evicted and counted by `dropped()`.

---

## How to Add a New Command End-to-End

**Step 1 — Define the command:**

```gdscript
# scripts/core/commands/grow_flora_command.gd
class_name GrowFloraCommand
extends WorldCommand

var _pos: Vector3

func _init(pos: Vector3) -> void:
    _pos = pos

func apply(ctx: WorldContext) -> void:
    if ctx.flora_edit == null:
        return
    ctx.flora_edit.grow_at(_pos)
```

**Step 2 — Add the service field to `WorldContext`** (if needed):

```gdscript
# scripts/core/commands/world_context.gd
var flora_edit: FloraEditService
```

Wire it in `World._ready` or `World.setup`.

**Step 3 — Decide replicability.** If the command mutates shared world state
(terrain, blocks, flora) it must be replicable. Add encode/decode branches to
`CommandCodec` (`scripts/core/net/command_codec.gd`):

```gdscript
# In encode():
if cmd is GrowFloraCommand:
    return {"t": "grow", "c": _vec_to_arr(cmd._pos)}

# In decode() match block:
"grow":
    var gc: Variant = _arr_to_vec(data.get("c"))
    if gc == null:
        return null
    return GrowFloraCommand.new(gc)
```

**Step 4 — Write a unit test** in `tests/unit/`. Subclass the relevant service,
override the method under test to record calls, build a `WorldContext` with the
stub, and assert routing:

```gdscript
# See tests/unit/test_commands.gd -> RecordingEditService for the pattern.
```

**Step 5 — Submit through the router from gameplay code:**

```gdscript
command_router.submit(GrowFloraCommand.new(pos))
```

Never call `bus.execute` directly from gameplay code outside of `CommandRouter`.

---

## Gotchas

- `apply` is called on the host during replay (late join) — it must be idempotent
  with respect to already-applied state. Terrain digs are naturally idempotent
  (digging empty space is a no-op); block placements must check for duplicates.
- `CycleNoteCommand` does not use `ctx` at all — it acts directly on the target
  node. This is intentional because pitch state lives on the block node itself,
  not in any context service.
- Block node names (`"Block_0"`, `"Block_1"`, ...) are assigned monotonically by
  `BlockPlacementService` and must stay stable for replay correctness.
- A command that returns early (null guard) still causes `command_executed` to emit
  from `CommandBus`. Listeners must not assume the command actually did something.
