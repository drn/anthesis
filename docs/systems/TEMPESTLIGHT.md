# Tempestlight System

Tempestlight is Anthesis's third magic resource: a held pool of living storm
energy that heals over time, amplifies speed, and fuels two lash abilities. Unlike
lumen (harvested continuously from flora) or metal reserves (stockpiled from
mining), Tempestlight is **front-loaded and leaking** — you inhale a gem and spend
the next ~40 seconds cashing it out.

The gem economy is a deliberate two-item design: the raw form (dun gem) does
nothing by itself, but racking it on a sky-exposed storm catcher during a
Resonance Storm transmutes it into a charged gem worth 40 Tempestlight. The
limitation (you must weather the storm to charge your gems) is as interesting as
the power itself.

---

## Key Files

| File | Role |
|------|------|
| `scripts/systems/magic/tempest_light.gd` | `TempestLight` — held-light pool, leak, regen, status wiring |
| `scripts/systems/magic/lash_math.gd` | `LashMath` — pure axis-snap helper |
| `scripts/systems/world/tempest_rig.gd` | `TempestRig` — integrator extract that builds and wires both systems |
| `resources/abilities/sky_lash.tres` | `sky_lash` ability data |
| `resources/abilities/bond_lash.tres` | `bond_lash` ability data |
| `resources/items/dun_gem.tres` | Raw storm gem |
| `resources/items/charged_gem.tres` | Charged storm gem (inhale fuel) |
| `resources/items/storm_catcher.tres` | Placeable charging pylon |
| `tests/unit/test_tempest_light.gd` | Inhale exchange, leak, regen, speed-modifier edges |
| `tests/unit/test_lash_math.gd` | Axis-snap corner cases |
| `tests/unit/test_tempest_content.gd` | Registry smoke tests for new .tres files |
| `tests/integration/test_world_tempest.gd` | World-level integration: inhale, lash, gravity restore |

---

## TempestLight

`TempestLight` (`extends Node`, named `"Tempest"`) owns the held-light pool.

```gdscript
class_name TempestLight extends Node

signal holding_changed(active: bool)  # edge-triggered when pool crosses zero

const CAPACITY            := 100.0
const INHALE_CHARGE       := 40.0   # per charged gem
const LEAK_PER_TICK       := 0.1    # 1.0/s; one gem ≈ 40 s
const REGEN_INTERVAL_TICKS := 10    # 1 s
const REGEN_COST          := 2.0    # Tempestlight spent per regen tick
const REGEN_AMOUNT        := 1.0    # HP healed per regen tick
const SPEED_BONUS         := 1.2    # multiplicative speed modifier while holding

func setup(status: StatusEffectSystem, health: Health, target_id: Callable,
        glow: Light3D, speed_modifier: Callable) -> void
func well() -> LumenWell
func inhale(inventory: Object) -> bool
func on_tick(tick: int) -> void
```

### Tick behavior

`on_tick` runs three passes in order:

1. **Leak.** Drains `min(LEAK_PER_TICK, current)` each tick (~0.1 charge per
   tick = 1 charge/s). At capacity 100, a single charged gem (40 charge) lasts
   about 40 seconds.
2. **Regen.** Every `REGEN_INTERVAL_TICKS` (every 10 ticks = 1 s), if the player's
   `Health` is below maximum and the well can afford `REGEN_COST` (2.0): spend 2
   charge and heal 1 HP. Effective rate while holding: 1 HP/s at a cost of 2
   charge/s — slightly faster than the base leak.
3. **Holding edge.** If the pool crosses zero from above, `holding_changed(false)`
   fires, the `&"tempest"` status effect is cleared (restoring speed), and glow
   goes dark. If it crosses zero from below (after an `inhale`), `holding_changed(true)`
   fires, the `&"tempest"` status effect is applied (speed ×1.2), and glow
   begins scaling.

The OmniLight3D glow child's `light_energy` is set to `3.0 × fill_ratio` every
tick (fill_ratio = current / CAPACITY). At full capacity the glow reaches 3.0
energy; at empty it disappears. Range is 7 m.

### Inhale

`inhale(inventory)` performs the gem exchange:

1. Check `inventory.count_of(&"charged_gem") > 0`. If not: return `false`.
2. `inventory.remove(&"charged_gem", 1)`.
3. `well().add(INHALE_CHARGE)` (40 charge; clamps at CAPACITY if near-full).
4. `inventory.add(&"dun_gem", 1)` — the spent gem leaves an inert dun gem in your
   pack.
5. Return `true`.

The dun-gem refund is intentional: even "spent" gems can be re-racked on a catcher
and recharged in the next storm.

### Speed Modifier

`TempestLight` does not set `player.speed_scale` directly. It calls the
`speed_modifier` Callable injected at `setup()`. In `world.gd` (via `TempestRig`),
this is `_set_speed_mod.bind(&"tempest")` — the speed-modifier table that composes
all multiplicative bonuses (vigor 1.4, pewter-drag 0.6, tempest 1.2). All three
can overlap; the product drives `speed_scale`. A vigor + tempest stack gives
1.4 × 1.2 = 1.68× move speed.

---

## Gem Economy: Two-Item Design Rationale

The two-item split (dun_gem ≠ charged_gem) serves three design goals:

1. **Storm as prerequisite, not obstacle.** Without a storm you simply cannot
   charge gems. The weather cycle becomes a supply cadence, not random punishment.
2. **Catcher placement is a skill expression.** You must find sky-exposed ground,
   place catchers before the storm hits, and defend yourself while they charge. The
   shelter dilemma is real.
3. **Inhale is a meaningful mode switch.** You choose *when* to pop a charged gem
   and enter holding mode. Saving it for a tough fight or an exploratory leap is a
   tactical decision, not housekeeping.

The capacity (100) deliberately prevents hoarding: two gems (80 charge) lands
you near-full with a bit of overflow. You can carry up to 16 charged gems in a
stack, but only one inhale can be active at a time.

---

## LashMath

`LashMath` (`extends RefCounted`) is a pure static helper. No node, no state.

```gdscript
static func snap_axis(dir: Vector3) -> Vector3
    # Returns the dominant-axis unit vector with sign.
    # e.g. (0.2, 0.7, -0.1) -> Vector3.UP (0, 1, 0)
    # Zero or near-zero input -> Vector3.DOWN (safe fallback).
```

Used by the `sky_lash` effect to snap the camera forward direction to the nearest
cardinal axis (UP, DOWN, FORWARD, BACK, LEFT, RIGHT) before calling
`player.set_gravity_dir(axis)`. This is what makes Skylash produce clean
"wall-running" or "falling sideways" gravity rather than diagonal weirdness.

---

## Lash Abilities

### sky_lash (Slot 6)

| Field | Value |
|-------|-------|
| `resource_kind` | `&"tempest"` |
| `lumen_cost` | 20.0 |
| `cooldown_ticks` | 10 (1.0 s) |
| `magnitude` | 6.0 (lash duration in seconds = 60 ticks) |

**Effect:**

1. Snap the player's camera forward direction to a cardinal axis via
   `LashMath.snap_axis(camera_basis.z)`.
2. Apply the snapped axis as the new gravity direction:
   `player.set_gravity_dir(snapped_axis)`.
3. Apply status `&"sky_lash"` on the player for `int(magnitude * 10) = 60` ticks,
   whose `on_expire` calls `player.set_gravity_dir(Vector3.DOWN)` (restore normal
   gravity).
4. Re-casting before expiry refreshes the duration (the status `apply` refresh
   semantic) and re-snaps to the current camera forward — `set_gravity_dir` is
   called again before the re-apply so the axis updates without waiting for expiry.

**v1 limitation:** the camera does NOT reorient with gravity. XZ movement input
remains yaw-based (look direction horizontal). When gravity is sideways, "forward"
still means "camera forward projected onto XZ". This is an accepted v1 limitation
documented in-game and here. The planned upgrade (camera reorient + input remapping
to the new gravity plane) is deferred to a future phase.

**Sticky-patch** (gravity sticking to walls) and **reverse-lash** (lashing the
player back to normal gravity mid-air) are also deferred.

### bond_lash (Slot 1)

| Field | Value |
|-------|-------|
| `resource_kind` | `&"tempest"` |
| `lumen_cost` | 15.0 |
| `cooldown_ticks` | 10 (1.0 s) |
| `magnitude` | 5.0 (root duration in seconds = 50 ticks) |

**Effect:**

1. Scan group `"umbrals"` for the nearest node within 2.0 m of the cast target.
2. If none found: return `false` (cost not spent).
3. Apply status `&"rooted"` on the Umbral's instance ID for
   `int(magnitude * 10) = 50` ticks.
   - `on_apply`: `umbral.set_rooted(true)` (guarded with `is_instance_valid`).
   - `on_expire`: `umbral.set_rooted(false)` (guarded with `is_instance_valid`).

`Umbral.set_rooted(true)` zeroes horizontal velocity and holds position each tick
while rooted; the Umbral keeps attacking if the player is in range but cannot chase.
The effect is purely movement-suppression, not a damage amplifier in v1.

---

## Gravity Refactor (player.gd)

`sky_lash` required a gravity vector refactor in `player.gd`:

```gdscript
var gravity_dir := Vector3.DOWN

func set_gravity_dir(dir: Vector3) -> void:
    if dir.length_squared() < 0.001:
        gravity_dir = Vector3.DOWN
    else:
        gravity_dir = dir.normalized()
    up_direction = -gravity_dir  # CharacterBody3D orientation

func _physics_process(delta: float) -> void:
    # Was: velocity.y -= gravity * delta
    # Now: velocity += gravity_dir * gravity * delta
    ...

    # Jump: zero the along-gravity component, then push opposite to gravity.
    # Was: velocity.y = JUMP_VELOCITY
    # Now:
    velocity -= velocity.project(gravity_dir)
    velocity += -gravity_dir * JUMP_VELOCITY
```

`up_direction = -gravity_dir` is what makes `CharacterBody3D.move_and_slide()`
treat the anti-gravity plane as the floor. When gravity_dir is `Vector3.RIGHT`,
the floor is the YZ plane and the player stands on walls.

**Gotcha:** forgetting to set `up_direction` in `_ready` (for the default DOWN
case) leaves the player unable to be "on the floor" before the first tick. The
refactored `_ready` calls `up_direction = Vector3.UP` explicitly.

---

## TempestRig

`TempestRig` (`extends Node`, added by the integrator in `World._ready`) is an
extraction that keeps weather and tempest wiring out of `world.gd` (which is at
the gdlintrc line ceiling). It mirrors the `FerromancyRig` pattern.

Responsibilities:
- Instantiate and configure `WeatherSystem` (named `"Weather"`) and `TempestLight`
  (named `"Tempest"`).
- Build the player's glow `OmniLight3D` (range 7 m, parented to `_player`).
- Connect both systems to `_clock.ticked`.
- Own the `_on_storm_pulse` handler (authority-gated sky-exposure sweep).
- Realize the `sky_lash` and `bond_lash` ability effects.
- Publish `_context.tempest` and `_context.weather`.
- Register `&"tempest"` in `MagicSystem`'s well resolver → `_tempest.well()`.
- Bind `_hud.bind_tempest(_tempest)`.

Explicit parameters passed to `TempestRig.build()`: `_clock`, `_world_seed`,
`_status`, `_env_rig`, `_context`, `_set_speed_mod`. Player, router, session,
intensity, health, and HUD are accessed via `World`'s public getters to keep the
call site short.

---

## How to Extend

### Add a new tempest-powered ability

1. Create `resources/abilities/<id>.tres` with `resource_kind = &"tempest"`,
   `lumen_cost`, `cooldown_ticks`, and `magnitude` per the design.
2. Register the effect in `TempestRig._install_tempest_effects` (or wherever
   lash effects are registered) as:
   ```gdscript
   ctx.ability_effects[&"my_kind"] = func(ability, target) -> bool:
       ...
       return true
   ```
3. Update the ability slot table in `docs/GAMEPLAY.md` and `docs/systems/MAGIC.md`
   (slot order is alphabetical by id).
4. Test with the `test_cast_command.gd` EffectSpy pattern.

### Change leak or regen rate

All four constants live in `tempest_light.gd` as class constants. Changing them
is a data edit (one file, no wiring change). Re-run `make test` to catch any
test that asserts exact numeric values.

---

## Testing Notes

`tests/unit/test_tempest_light.gd` key patterns:

- **Inhale exchange.** Construct a real `Inventory`, add one `&"charged_gem"`.
  Call `inhale(inventory)`. Assert `well().current() == INHALE_CHARGE`,
  `inventory.count_of(&"dun_gem") == 1`, `inventory.count_of(&"charged_gem") == 0`.
- **Leak to zero + edge signals.** Fill the well, drive ticks until zero.
  Assert `holding_changed(false)` fires. Add `spy.calls.clear()` after
  the setup-reconcile tick (which emits a rising edge) so the assert only catches
  the falling edge — the integrator test fix for the off-by-one spy accumulation.
- **Regen cadence.** Start with a hurt `Health` and partial well. Drive 10 ticks.
  Assert exactly one heal at tick 10; assert well deducted `REGEN_COST`.
- **Speed modifier edges.** Pass a `SpyCallable` as `speed_modifier`. Assert it is
  called with `true` on the first inhale crossing from 0 → positive, and with
  `false` when the pool drains to 0.

`tests/unit/test_lash_math.gd`: dominant axis with each cardinal direction, Y-up,
Y-down, XZ dominant vs. Y dominant, zero-length fallback to DOWN.

---

## Gotchas

- **`up_direction` must be set in `_ready`.** The gravity refactor in `player.gd`
  sets `up_direction = -gravity_dir` in `set_gravity_dir`. But `_ready` must also
  set `up_direction = Vector3.UP` explicitly for the default DOWN gravity case —
  otherwise `CharacterBody3D` starts with the default zero vector and the player
  cannot land on the floor before the first `set_gravity_dir` call.
- **`sky_lash` re-cast refreshes but does not re-fire `on_apply`.** The
  `StatusEffectSystem` re-apply semantic refreshes duration but does not call
  `on_apply` again. The lash effect handles this by calling `set_gravity_dir`
  directly before the re-apply so the axis updates regardless.
- **`bond_lash` `on_expire` must guard `is_instance_valid`.** The Umbral may
  despawn before the 50-tick root expires. The `on_expire` Callable is stored
  in `StatusEffectSystem` and will fire even after the node is freed; always
  guard with `is_instance_valid(umbral)`.
- **Tempest well starts empty.** Like all `LumenWell` instances, `TempestLight.well()`
  starts at 0. Tests must call `inhale` or `well().add(...)` explicitly before
  asserting non-zero behavior.
- **Speed modifiers are multiplicative, not additive.** Vigor (1.4) + Tempest (1.2)
  gives 1.4 × 1.2 = 1.68, not 1.4 + 0.2 = 1.6. The `_speed_mods` table in
  `world.gd` takes the product of all active entries. Clear a modifier with
  `_set_speed_mod(id, 1.0)` (neutral element) rather than removing the key, so
  the product remains correct.
- **LashMath axis-snap uses dominant component.** If the camera is looking
  45° between two axes, the snap will pick one based on which component has the
  larger absolute value. In practice, near-diagonal looks produce surprising gravity
  snaps. This is expected behavior, not a bug.
