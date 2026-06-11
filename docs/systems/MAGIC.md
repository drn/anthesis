# Magic System

The Anthesis magic system is Sanderson's First Law made executable: every ability
has a fixed lumen cost and a tick-based cooldown, the rule gate is deterministic
(same tick, same well, same ability always gives the same outcome), and the only
source of lumen is harvesting living bioluminescent flora. Nothing is conjured for
free.

---

## Key Files

| File | Role |
|------|------|
| `scripts/core/sim/simulation_clock.gd` | Fixed-rate tick heartbeat |
| `scripts/systems/magic/lumen_well.gd` | The finite lumen reservoir |
| `scripts/systems/magic/magic_system.gd` | Cooldown/cost/effect rule gate |
| `scripts/core/magic/ability_def.gd` | Immutable ability data type |
| `scripts/systems/magic/ability_registry.gd` | Disk scan + id-keyed catalog |
| `scripts/systems/flora/harvestable.gd` | Per-prop lumen value + drop table |
| `scripts/core/commands/cast_command.gd` | Command layer entry point for casts |
| `scripts/core/commands/harvest_command.gd` | Lumen gather happens here |
| `resources/abilities/` | `.tres` ability data files |
| `tests/unit/test_magic_system.gd` | Rule gate tests (cooldown, cost, effect-false) |
| `tests/unit/test_lumen_well.gd` | Well arithmetic tests |
| `tests/unit/test_cast_command.gd` | CastCommand + HarvestCommand lumen tests |
| `tests/unit/test_ability_registry.gd` | Registry scan tests |

---

## SimulationClock

`SimulationClock` (`extends Node`) is the tick heartbeat. It runs in `_process`
(not `_physics_process`) so it can be paused independently of physics.

```
ticks_per_second = 10  (default, configurable via @export)
MAX_TICKS_PER_FRAME = 10  (hard cap, prevents catch-up spiral)
```

Each frame it accumulates real delta time; for each whole tick interval it
increments `_tick_index` by exactly 1 and emits `ticked(tick_index: int)`.
Surplus time beyond the per-frame cap is dropped (not carried forward).

`current_tick() -> int` returns the most recently emitted index (-1 before the
first tick). During a `ticked` handler, `current_tick()` equals the just-emitted
index.

`MagicSystem` reads `current_tick()` via an injected `Callable` so it never
depends on the clock node directly.

---

## LumenWell

`LumenWell` (`extends RefCounted`) is the player's finite lumen reservoir.
Default capacity is 100; the world starts the player at 30.

```gdscript
signal changed(current: float, capacity: float)

func _init(capacity := 100.0)
func add(amount: float) -> float      # returns overflow (0 when all fit)
func spend(amount: float) -> bool     # all-or-nothing; false if unaffordable
func can_afford(amount: float) -> bool
func current() -> float
func capacity() -> float
```

`add` clamps at capacity and emits `changed` only when stored amount actually
moves. `spend` is all-or-nothing: it either deducts the full amount and emits
`changed`, or returns `false` and leaves the well untouched. A non-positive `spend`
amount returns `true` (trivial success); non-positive `add` amounts change
nothing.

The HUD lumen orb connects to `changed` for cheap one-shot refreshes.

---

## MagicSystem

`MagicSystem` (`extends RefCounted`) is the sole adjudicator of casts. It holds
the per-ability last-cast-tick map and enforces the rule gate.

```gdscript
signal cast_succeeded(ability: AbilityDef)
signal cast_failed(ability: AbilityDef, reason: StringName)

func _init(well: LumenWell, clock_tick: Callable)
func can_cast(ability: AbilityDef) -> bool
func cooldown_remaining(ability: AbilityDef) -> int
func try_cast(ability: AbilityDef, effect: Callable) -> bool
```

### Rule Gate Semantics

`try_cast` enforces three gates **in a fixed order**:

1. **Cooldown** — `cooldown_remaining(ability) > 0` → emit `cast_failed(&"cooldown")`, return false.
2. **Cost** — `not well.can_afford(ability.lumen_cost)` → emit `cast_failed(&"cost")`, return false.
3. **Effect** — call `effect.call()` (returns `bool`):
   - `false` → emit `cast_failed(&"no_effect")`, **spend nothing**, return false.
   - `true` → call `well.spend(lumen_cost)`, record `_last_cast[ability.id] = current_tick()`, emit `cast_succeeded`, return true.

Key invariant: **nothing is spent until the effect succeeds**. A failed effect
refunds nothing because nothing was spent. This keeps costs consistent and replay
deterministic.

Cooldowns are keyed by `ability.id` (not `kind`) so different abilities sharing a
kind have independent cooldowns.

---

## AbilityDef and .tres Format

`AbilityDef` (`extends Resource`) declares:

| Field | Type | Example (shape_burst) |
|-------|------|-----------------------|
| `id` | `StringName` | `&"shape_burst"` |
| `display_name` | `String` | `"Worldshaper Burst"` |
| `kind` | `StringName` | `&"shape_burst"` |
| `lumen_cost` | `float` | `25.0` |
| `cooldown_ticks` | `int` | `30` |
| `magnitude` | `float` | `4.0` (carve radius) |
| `swatch_color` | `Color` | blue |
| `description` | `String` | flavor text |

Three abilities ship:

| id | kind | cost | cooldown | magnitude |
|----|------|------|----------|-----------|
| `shape_burst` | `shape_burst` | 25 | 30 | 4.0 (carve radius) |
| `lumen_bloom` | `lumen_bloom` | 15 | 20 | 6.0 (light radius) |
| `skyward` | `skyward` | 10 | 15 | 14.0 (impulse m/s) |

`kind` is the dispatch key for `WorldContext.ability_effects`. One ability can
share a `kind` with another if both should invoke the same effect Callable.

---

## AbilityRegistry

Scans `res://resources/abilities/` at construction, loads every `.tres` that is
an `AbilityDef` with a non-empty `id`, and indexes by `id`. Handles
`.tres.remap` suffixes for exported builds.

```gdscript
func _init(dir := "res://resources/abilities")
func ability(id: StringName) -> AbilityDef   # null if not found
func abilities() -> Array[AbilityDef]          # sorted by id (stable hotkey order)
func ability_ids() -> Array[StringName]        # sorted alphabetically
```

Abilities returned by `abilities()` are sorted by id (alphabetical). With the
current three abilities the stable hotkey order is: `lumen_bloom` (1), `shape_burst`
(2), `skyward` (3).

---

## Lumen Gathering

Lumen enters the well exclusively through `HarvestCommand`. When `ctx.magic` and
`ctx.lumen_gain` are both wired, the command looks up the `Harvestable` component
on the harvested prop node (by `get_node_or_null("Harvestable")`) and, if
`harvestable.lumen > 0`, calls `ctx.lumen_gain.call(harvestable.lumen)`.

`Harvestable` lumen values by prop type (see `resources/flora/`):
mushroom = 8, flower = 10, crystal = 15.

In `World`, `ctx.lumen_gain` is wired as `func(amount): lumen_well.add(amount)`.

---

## CastCommand Flow (End-to-End)

```
Player.cast_requested(slot, target)
    -> World maps slot -> AbilityDef (via AbilityRegistry hotkey order)
    -> World submits CastCommand.new(ability, target)
        -> CommandRouter.submit
            -> CommandBus.execute (client-local, not replicated)
                -> CastCommand.apply(ctx)
                    -> ctx.ability_effects.get(ability.kind)  -> effect Callable or null
                    -> ctx.magic.try_cast(ability, lambda)
                        [gate: cooldown -> cost -> effect]
                        -> effect.call(ability, target)  -> bool
                        -> (on true) well.spend(cost), record tick, emit cast_succeeded
```

The actual effect Callable (e.g. terrain carve, bloom spawn, player impulse) lives
in `World` — never inside `CastCommand` or `MagicSystem`.

### LumenBloomMote

The `lumen_bloom` effect spawns `scenes/props/lumen_bloom.tscn`
(`scripts/systems/flora/lumen_bloom_mote.gd`): an emissive orb + `OmniLight3D`.
`configure(radius)` sets the light range from the ability's `magnitude` (6.0); the
mote pulses, self-frees after `lifetime_s` (25 s), and counts as a glow point that
repels Umbral spawns while it lives — see [FLORA.md](FLORA.md) and
[COMBAT.md](COMBAT.md).

---

## How to Add a New Ability

**Step 1 — Create the .tres resource:**

```
resources/abilities/my_ability.tres
```

Minimal content (use an existing `.tres` as a template):

```
[gd_resource type="Resource" script_class="AbilityDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/core/magic/ability_def.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"my_ability"
display_name = "My Ability"
kind = &"my_ability"
lumen_cost = 20.0
cooldown_ticks = 25
magnitude = 2.0
swatch_color = Color(1, 0.5, 0, 1)
description = "Does something cool."
```

`AbilityRegistry` will discover it automatically on next boot.

**Step 2 — Register the effect in `World`:**

```gdscript
# In World._ready or World._setup_context():
ctx.ability_effects[&"my_ability"] = func(ability: AbilityDef, target: Vector3) -> bool:
    # Return false if the effect could not run (e.g. target out of range).
    _do_my_effect(ability.magnitude, target)
    return true
```

**Step 3 — Write a unit test** in `tests/unit/`:

```gdscript
# See test_cast_command.gd -> test_cast_runs_registered_effect_with_ability_and_target
# for the exact EffectSpy + _magic_context() pattern to copy.
```

**No changes to `CastCommand` or `MagicSystem` are needed.**

---

## Testing Notes

`tests/unit/test_magic_system.gd` is the canonical reference. Key patterns:

- `FakeClock` (inner class): holds a mutable `tick: int`; `clock.now` is passed as
  the `clock_tick` Callable. Advance with `clock.tick = N`.
- `_full_well(capacity)`: creates a well and fills it (`well.add(capacity)`) because
  the well starts empty by design.
- `EffectSpy` (inner class): records calls and controls the return value via `result`.

`tests/unit/test_cast_command.gd` tests `CastCommand` routing end-to-end through
a real `MagicSystem`, including the `no_effect` path and the `HarvestCommand` lumen
gather hook.

---

## Gotchas

- The well **starts empty** (`_current = 0`). Tests that need to cast must call
  `well.add(capacity)` explicitly.
- `cooldown_remaining` never goes negative — it is clamped at 0. A long-idle
  ability always reports 0, never a negative number.
- When both cooldown and cost would fail, **cooldown wins** (it is checked first).
  This keeps the failure reason stable regardless of well state.
- `ability.kind` (not `ability.id`) is the dispatch key for `ability_effects`.
  If you forget to register an effect for a new kind, casts will emit
  `cast_failed(&"no_effect")` silently — check `ctx.ability_effects` wiring first.
- `AbilityRegistry` sorts by `id`, so hotkey order depends on alphabetical ordering
  of ability ids. Name new abilities accordingly if position matters.
