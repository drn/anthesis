# Metallurgy System

The Anthesis metallurgy system is the second magic tier: where lumen is gathered
from the living world and spent on instant-effect abilities, metals are mined from
the earth, refined at the crafting bench, and *burned* over time through sustained
channels. Ferropull, Ferropush, Vigor, and Keensight are all powered by metal
reserves rather than the lumen well — the player now manages two orthogonal
economies.

The design is Sanderson's Second Law at the system level: the limitation (finite
reserves, the pewter-drag crash, the flare multiplier) is as interesting as the
power itself.

---

## Key Files

| File | Role |
|------|------|
| `scripts/systems/magic/metal_reserves.gd` | Per-kind `LumenWell` bundle + auto-swallow |
| `scripts/systems/magic/channel_system.gd` | Sustained-burn tick loop + flare multiplier |
| `scripts/systems/magic/ferro_kinetics.gd` | Pure-math push/pull impulse calculator |
| `scripts/systems/magic/magic_system.gd` | Multi-well rule gate (extended for Phase 8) |
| `scripts/systems/status/status_effect_system.gd` | Timed / indefinite effect tracking |
| `scripts/systems/world/ferromancy_rig.gd` | Extractor: channel boon Callables + physics application |
| `scripts/core/magic/ability_def.gd` | Gained `resource_kind` field (Phase 8) |
| `scripts/core/commands/toggle_channel_command.gd` | Toggle vigor / keensight |
| `scripts/core/commands/set_flare_command.gd` | Shift flare on/off |
| `scripts/core/commands/throw_coin_command.gd` | Consume + launch ferric coin |
| `scripts/core/commands/cast_command.gd` | Pre-cast auto-swallow hook (Phase 8 addition) |
| `scripts/core/commands/damage_command.gd` | Vigor damage-reduction branch (Phase 8) |
| `scripts/systems/flora/metal_deposit.gd` | StaticBody3D metal source prop |
| `scripts/systems/magic/ferric_coin.gd` | RigidBody3D coin; struck signal |
| `scripts/ui/hud.gd` | `bind_metals(reserves, channels)` (Phase 8 addition) |
| `scripts/ui/metal_line_overlay.gd` | Blue-line metal-sense overlay |
| `resources/items/` | 9 new `.tres` (4 ores, 4 flake kinds, ferric_coin) |
| `resources/recipes/` | 5 new `.tres` (4 refine recipes + coin forge) |
| `resources/abilities/` | `ferro_pull.tres`, `ferro_push.tres` |
| `resources/creatures/shardling.tres` | Now carries `metal_mass = 60.0` |
| `scenes/props/metal_deposit_*.tscn` | 4 deposit scenes (lodestone/skysteel/vigorite/keenglass) |
| `scenes/props/ferric_coin.tscn` | Throwable coin scene |
| `tests/unit/test_metal_reserves.gd` | Auto-swallow, capacity, signal re-emission |
| `tests/unit/test_channel_system.gd` | Tick drain, flare, depleted force-stop |
| `tests/unit/test_ferro_kinetics.gd` | Pure-math cone/range/impulse cases |
| `tests/unit/test_status_effect_system.gd` | Apply/expire/refresh/clear_all |
| `tests/unit/test_toggle_channel_command.gd` | Channel + flare routing |
| `tests/unit/test_throw_coin_command.gd` | Coin consume + spawn args |
| `tests/unit/test_metal_content.gd` | Registry-level content smoke tests |
| `tests/integration/test_world_ferromancy.gd` | World boot + 7 integration scenarios |

---

## MetalReserves

`MetalReserves` (`extends RefCounted`) is a thin wrapper around one `LumenWell`
per metal kind, with the critical `ensure` auto-swallow mechanic that makes flakes
disappear from inventory silently mid-burn.

```gdscript
const DEFAULT_CAPACITY := 60.0   # per metal well
const FLAKE_CHARGE    := 30.0   # charge added per flake consumed

func _init(flake_map: Dictionary, capacity := DEFAULT_CAPACITY) -> void
    # flake_map: {metal_kind: flake_item_id}  e.g. {&"iron": &"iron_flakes"}
    # One LumenWell per key, each starts empty.

func kinds() -> Array             # sorted StringName list (lexical)
func well(kind: StringName) -> LumenWell   # null for unknown kind
func add(kind: StringName, amount: float) -> float  # overflow (0 when all fit)
func ensure(kind: StringName, amount: float, inventory: Object) -> bool
    # Auto-swallows flakes while well < amount and inventory holds them.
    # Returns well.can_afford(amount) after topping up.
func ensure_for_cost(ability: AbilityDef, inventory: Object) -> bool
    # No-op / true for &"lumen" or unknown kinds.
    # Else: ensure(ability.resource_kind, ability.lumen_cost, inventory).
```

`ensure` is the auto-swallow rule: while the target well holds fewer than `amount`
and the inventory contains at least one flake for that kind, it removes one flake
(`inventory.remove(flake_id, 1)`) and calls `well.add(FLAKE_CHARGE)`. It consumes
the *minimum* number of flakes necessary and stops the moment the well can afford
the cast. Excess capacity is not pre-filled.

`changed` re-emits each inner well's `changed` signal as
`changed(kind: StringName, current: float, capacity: float)` so the HUD metal
bars need only one subscription point.

---

## ChannelSystem

`ChannelSystem` (`extends Node`, named `"Channels"`) is the sustained-burn engine.
A channel burns a metal reserve once per tick at a configurable drain rate. The
player can enable the `flare` multiplier (Shift) to triple the drain for triple the
effect — but the same reserves feed the channel, so flare burns through stock fast.

```gdscript
const FLARE_DRAIN_MULT := 3.0

func setup(reserves: MetalReserves, inventory: Object) -> void
func install(channel_id: StringName, def: Dictionary) -> void
    # def: {resource_kind, drain_per_tick, on_start: Callable,
    #        on_stop: Callable(reason: StringName)}
func toggle(channel_id: StringName) -> bool
    # ON: calls ensure(kind, drain, inventory); if still unaffordable → false (stays off).
    #     Calls on_start, emits channel_changed(id, true), returns true.
    # OFF: on_stop(&"manual"), channel_changed(id, false), returns true.
func is_active(channel_id: StringName) -> bool
func set_flare(active: bool) -> void
func is_flaring() -> bool
func active_channels() -> Array   # sorted ids
func on_tick(_tick: int) -> void
    # Per active channel: drain *= FLARE_DRAIN_MULT if flaring.
    # If well.spend(drain) fails: ensure then retry; still failing → force-stop
    # (on_stop(&"depleted"), channel_changed(id, false)).
```

**Force-stop on depletion** is the core danger: the reserves ran out mid-burn.
For vigor (pewter) this triggers the pewter-drag crash (see Gotchas).

A `Node` (not `RefCounted`) so the `ticked` signal connection cannot be GC'd.

---

## StatusEffectSystem

`StatusEffectSystem` (`extends Node`, named `"StatusEffects"`) tracks timed and
indefinite effects on arbitrary integer target IDs (using `get_instance_id()`).

```gdscript
signal effect_applied(target_id: int, effect_id: StringName)
signal effect_expired(target_id: int, effect_id: StringName)

func apply(target_id: int, effect_id: StringName, duration_ticks: int,
        on_apply: Callable, on_expire: Callable) -> void
    # Re-apply refreshes duration; on_apply does NOT re-fire on refresh.
    # duration_ticks <= 0 → indefinite.
func has(target_id: int, effect_id: StringName) -> bool
func clear(target_id: int, effect_id: StringName) -> void  # on_expire fires if present
func clear_all(target_id: int) -> void
func on_tick(_tick: int) -> void  # decrement durations; expire at 0
```

Phase 8 effects registered by `FerromancyRig` via `world.gd`:

| `effect_id` | `duration_ticks` | on_apply | on_expire |
|-------------|-------------------|----------|-----------|
| `&"vigor"` | 0 (indefinite) | `player.speed_scale = 1.4` | restore `1.0` |
| `&"keensight"` | 0 (indefinite) | ambient light +60% | restore ambient |
| `&"pewter_drag"` | 100 (10 s) | `player.speed_scale = 0.6` | restore `1.0` |

---

## MagicSystem Multi-Well

`MagicSystem._init` now accepts either a `LumenWell` (legacy, every ability spends
from it) or a `Callable(kind: StringName) -> LumenWell` resolver. The internal
helper `_well_for(ability)` maps `ability.resource_kind` (empty string → `&"lumen"`)
through the resolver. A resolver returning null for a kind makes that ability
unaffordable (`cast_failed(&"cost")`). The rule-gate order (cooldown → cost →
effect) is unchanged.

In `world.gd`, the resolver maps `&"lumen"` → `_well` and each metal kind →
`_metal_reserves.well(kind)`. `CastCommand` calls
`ctx.metal_reserves.ensure_for_cost(ability, ctx.inventory)` before the gate runs,
so flakes auto-swallow transparently.

---

## FerroKinetics

`FerroKinetics` (`extends RefCounted`) is pure math — no node, no tree, fully
unit-testable. All constants are pinned:

```
PLAYER_MASS    = 80.0
MAX_RANGE      = 24.0 m
MIN_AIM_DOT    = 0.866  (30° half-cone)
MASS_RATIO_MIN = 0.3
MASS_RATIO_MAX = 3.0
```

```gdscript
static func select_source(origin: Vector3, aim: Vector3, candidates: Array) -> Node3D
    # Returns the candidate within MAX_RANGE whose aim dot >= MIN_AIM_DOT with
    # the HIGHEST dot (ties: nearest). null if none qualify.

static func resolve(origin: Vector3, source_pos: Vector3, source_mass: float,
        anchored: bool, magnitude: float, pull: bool) -> Dictionary
    # Returns {"player_impulse": Vector3, "source_impulse": Vector3}.
    # Anchored or heavy (mass >= PLAYER_MASS): player is yanked/pushed; source unmoved.
    # Light and unanchored: source is yanked/pushed; player unmoved.
    # Impulse magnitude is scaled by the mass ratio clamped to [MASS_RATIO_MIN, MASS_RATIO_MAX].
```

Pull direction = toward source (`+line`); push = away from source (`-line`).
For pull, `world.gd` adds `Vector3.UP * 2.0` to the player impulse so ground
friction doesn't eat it.

---

## Metal-Source Protocol

Anything that can be pulled or pushed joins scene group `&"metal_sources"` and
exposes two members:

```gdscript
var metal_mass: float          # > 0
func is_metal_anchored() -> bool
```

There is no registry class. Consumers gather candidates via
`get_tree().get_nodes_in_group(&"metal_sources")` at cast time.

| Source | `metal_mass` | `is_metal_anchored()` |
|--------|-------------|----------------------|
| Metal deposits | 400.0 | always true |
| Ferric coins | 0.4 | sleeping OR `linear_velocity.length() < 0.5` |
| Shardling (Umbral) | 60.0 | always false |

---

## FerromancyRig

`FerromancyRig` (`extends Node`, added by integrator at `_build_magic`) is an
extraction that keeps channel-boon closures and the physical application of
Ferropull/Ferropush out of `world.gd`. Its public interface:

```gdscript
func install_channels(channels: ChannelSystem, status: StatusEffectSystem,
        player_id: int) -> void  # installs vigor + keensight channel defs
func setup(world: Node, status: StatusEffectSystem, combat: Object) -> void
    # Called after player exists. Stores collaborator refs for lazy player lookup.
func ferro_pull(ability: AbilityDef, _target: Vector3) -> bool
func ferro_push(ability: AbilityDef, _target: Vector3) -> bool
```

`ferro_pull` / `ferro_push` are registered in `world.gd` `_install_ability_effects`
as the effect Callables for those ability kinds, making them subject to the normal
cooldown/cost/effect gate.

---

## Ferric Coin

`FerricCoin` (`extends RigidBody3D`, scene `scenes/props/ferric_coin.tscn`) is a
metal-source projectile. Key constants and behavior:

```
metal_mass  = 0.4
THROW_SPEED = 18.0 m/s
despawn     = 60.0 s (scene-tree timer)
anchor rule = sleeping OR linear_velocity.length() < 0.5
```

```gdscript
signal struck(target_id: int, speed: float)
```

`struck` fires on `body_entered` when the body is in group `"umbrals"`. `world.gd`
connects this and submits `DamageCommand.new(target_id, 8.0, knockback)` when
`speed > 6.0`. The coin needs `contact_monitor = true`, `max_contacts_reported = 4`.

---

## Cast/Channel Flow (End-to-End)

### Instant ability (Ferropull / Ferropush)

```
Player.cast_requested(slot, target)           # slot 1 or 2
  -> World maps slot -> ferro_pull/ferro_push AbilityDef
  -> World submits CastCommand.new(ability, target)
      -> CommandRouter.submit (client-local)
          -> CastCommand.apply(ctx)
              -> ctx.metal_reserves.ensure_for_cost(ability, ctx.inventory)
                 [auto-swallows flakes until well can afford the 12-charge cost]
              -> ctx.magic.try_cast(ability, effect_lambda)
                  [gate: cooldown (0.8 s) -> cost (12 iron/steel) -> effect]
                  -> FerromancyRig.ferro_pull/push(ability, target) -> bool
                      -> FerroKinetics.select_source(origin, aim, candidates)
                      -> FerroKinetics.resolve(...) -> impulses
                      -> apply impulse to player / source node
                  -> (on true) well.spend(12), record tick, emit cast_succeeded
```

### Sustained channel (Vigor / Keensight)

```
Player.channel_toggle_requested(&"vigor")
  -> World submits ToggleChannelCommand(&"vigor")
      -> ctx.channels.toggle(&"vigor")
          -> ensure(pewter, 0.25, inventory)   # check affordability
          -> on_start: status.apply(player_id, &"vigor", 0, set_speed, restore)
          -> channel_changed(&"vigor", true)
  Per tick (SimulationClock.ticked -> channels.on_tick):
      -> well.spend(0.25 * flare_mult)
      -> if depleted: on_stop(&"depleted")
          -> status.clear(player_id, &"vigor")
          -> status.apply(player_id, &"pewter_drag", 100, set_speed_0.6, restore)
```

### Coin throw

```
Player.throw_coin_requested(origin, velocity)
  -> World submits ThrowCoinCommand(origin, velocity)
      -> ctx.inventory.remove(&"ferric_coin", 1)  # abort if 0
      -> ctx.coin_spawn.call(origin, velocity)
          -> instantiate ferric_coin.tscn; set position + linear_velocity
          -> connect struck -> _on_coin_struck
```

---

## How to Extend

### Add a new metal kind

1. Add an `ItemDef` `.tres` for the ore and a `consumable` `.tres` for the flakes
   (`resources/items/`), following the same pattern as e.g. `lodestone_ore.tres` /
   `iron_flakes.tres`.
2. Add a refine recipe `.tres` (`resources/recipes/`): 1 ore → 2 flakes.
3. Add the kind → flake-id pair to the `FLAKE_MAP` constant in `world.gd`
   (integrator-owned) and to the metal-deposit mapping if a new deposit type is
   needed.
4. `MetalReserves` creates one `LumenWell` per key in `FLAKE_MAP` automatically —
   no code change to `metal_reserves.gd`.
5. If the new kind powers an ability, set `resource_kind` on the ability's `.tres`
   and ensure `MagicSystem`'s resolver returns the right well for it.
6. Add a row to `resources/music/` if the new metal should affect the ambient
   intensity (optional).
7. Copy `tests/unit/test_metal_reserves.gd` stubs for any new well behavior.

### Add a new sustained channel

1. In `FerromancyRig.install_channels` (or a new rig if you've hit the method cap),
   call `channels.install(id, def)` where `def` is:

   ```gdscript
   {
       resource_kind = &"my_metal",
       drain_per_tick = 0.15,
       on_start = func(): # apply effect,
       on_stop = func(reason: StringName): # restore; handle &"depleted" specially
   }
   ```

2. Add the corresponding input action to `project.godot` (integrator-owned) and
   wire the player signal → `ToggleChannelCommand` route in `world.gd`.
3. Add a `StatusEffectSystem.apply` call for any timed / indefinite side-effect.
4. If the channel has a HUD indicator, add a row in `hud.gd`'s `bind_metals` loop
   that listens to `channels.channel_changed`.
5. Copy `tests/unit/test_channel_system.gd` for the drain / deplete / flare cases.

### Add a new metal-source member

Any node that can be pulled or pushed only needs:

```gdscript
var metal_mass: float = 200.0

func _ready() -> void:
    add_to_group(&"metal_sources")

func is_metal_anchored() -> bool:
    return false  # or true for fixed anchors
```

No registration call, no registry class. `FerroKinetics.select_source` picks it up
from the scene tree automatically. Set `metal_mass` meaningfully: masses above
`PLAYER_MASS` (80) anchor the physics to the player; masses below send the object
flying.

---

## Testing Notes

Key patterns to copy:

- **`test_metal_reserves.gd`** — uses a real `Inventory.new(24, null)` with
  `add(id, count)` / `remove(id, count)` / `count_of(id)`. The auto-swallow test
  pre-fills the inventory with N flakes and asserts exactly the right number were
  consumed.
- **`test_channel_system.gd`** — `SpyCallable` inner class records `on_start` /
  `on_stop(reason)` calls. Tests cover: toggle on with no reserves (returns false),
  toggle off (reason `&"manual"`), force-stop (reason `&"depleted"`), flare × 3.0
  drain, auto-swallow mid-burn.
- **`test_ferro_kinetics.gd`** — plain `Node3D` test doubles with a `metal_mass`
  var and an `is_metal_anchored()` stub function. No Godot binary needed; all
  methods are static.
- **`test_status_effect_system.gd`** — re-apply semantic: second `apply` call
  refreshes the duration counter but does NOT fire `on_apply` again. Indefinite
  (`duration_ticks = 0`) effects survive tick advancement; `clear` fires `on_expire`.

---

## Gotchas

- **The pewter-drag crash.** If Vigor runs dry (forced depletion, not a clean
  toggle off), `on_stop(&"depleted")` fires, which applies `&"pewter_drag"` for
  100 ticks (10 s at 10 ticks/s): `player.speed_scale = 0.6`. Toggle Vigor off
  *before* the reserves empty to avoid this. The HUD pewter bar going orange is
  your warning.
- **Auto-swallow is lazy, not eager.** `ensure` tops up only to the point the
  well can afford the current cost. It does not pre-fill the well to capacity.
  Calling `ensure` with `inventory = null` is safe (no-op top-up — well is not
  touched and returns whether it was already affordable).
- **10 ticks/s conversion.** All `duration_ticks`, `drain_per_tick`, and
  `cooldown_ticks` values are in simulation ticks, not seconds.
  `cooldown_ticks = 8` = 0.8 s. `pewter_drag = 100 ticks` = 10 s.
  `vigor drain = 0.25/tick` = depletes 60-cap in 240 ticks = 24 s at 1× flare.
- **Flare triples drain of all active channels simultaneously.** Vigor (0.25) +
  Keensight (0.1) at 3× flare = 0.75 + 0.3 per tick. Both reserves drain fast;
  whichever hits zero first force-stops its channel.
- **`ensure_for_cost` skips lumen abilities.** `resource_kind = &"lumen"` (or
  empty) returns `true` without touching inventory. This is intentional — lumen
  abilities gather from flora, not from inventory items.
- **Metal reserves start empty.** Just like `LumenWell`, every metal well starts
  at 0 charge. Tests that need to cast a metal ability must either pre-fill via
  `metal_reserves.add(kind, amount)` or stock the inventory with flakes and call
  `ensure`.
- **Coin anchor rule is dynamic.** A coin that was in flight transitions to
  "anchored" the moment it stops sliding (sleeping OR speed < 0.5 m/s). This means
  a coin resting on terrain acts as a fixed anchor for Ferropull; the player can
  yank themselves to a coin they threw earlier.
- **`kinds()` is lexically sorted.** `metal_reserves.kinds()` uses
  `sort_custom(func(a,b): return String(a) < String(b))` — not hash-ordered. Code
  that iterates kinds and expects a stable UI order (HUD bar rows) relies on this.
  Never call `Array.sort()` on StringName lists.
- **The `FerromancyRig` player lookup is lazy.** `ferro_pull` / `ferro_push` read
  the player via `get_node_or_null("Player")` at call time, not at setup time.
  During tests that don't have a full scene tree, the effect will return false
  gracefully (no player found, no source selected → `cast_failed(&"no_effect")`).
- **`gdlintrc` raises `max-file-lines: 1200`.** Phase 8's irreducible wiring pushed
  `world.gd` past the default 1000-line ceiling. The override affects only that
  heuristic; all correctness rules keep their defaults.
