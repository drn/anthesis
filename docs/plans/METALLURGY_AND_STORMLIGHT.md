# Plan: Ferromancy & Tempestlight (Sanderson-Inspired Magic, Phases 8–9)

Research + implementation plan for adapting Brandon Sanderson's two signature
magic systems into Anthesis:

- **Allomancy** (Mistborn) → **Ferromancy** — burn refined metals as a
  consumable fuel for physical powers; steel-push/iron-pull physics traversal.
- **Stormlight / Surgebinding** (Stormlight Archive) → **Tempestlight** —
  periodic Resonance Storms charge gems; players inhale the light, hold it as a
  leaking glow, and spend it on lashings and passive enhancement.

Mechanics verified against coppermind.net. Codebase extension points verified
against the current `master` (post phase 7). This doc is the input for two
`new-phase` runs.

---

## 1. Research Digest

### 1.1 Allomancy — what makes it work

| Mechanic | Source rule | Why it's fun in a game |
|---|---|---|
| Metal reserves | Swallow metal flakes; burning drains a per-metal reserve; power cuts out instantly at zero | Per-metal fuel bars; resource anxiety (running dry mid-jump) is the failure state |
| Flaring | Burn faster for a stronger effect (~3–10× drain) | Hold-to-overcharge: efficiency-vs-power decision every fight |
| Steel (push) / Iron (pull) | Blue lines to every nearby metal source, thickness ∝ mass, through walls. Force along the line only; relative mass decides who moves — push a coin, it flies; push something anchored, *you* fly | A physics toy, not a spell. Coin-jumping (drop coin → push off it) is the signature traversal skill |
| Pewter | Strength/speed/durability while burning; "pewter drag" crash when it runs out | Sustained combat buff with a debuff cliff |
| Tin | Heightened senses | Detection vision: see in dark, sense creatures |
| Zinc/Brass (emotions) | Riot/soothe emotions of others | AI levers: enrage mobs onto each other, pacify aggro |
| Duralumin | Dumps *all* active reserves in one burst | "Empty the tank" ultimate whose cost is the resource itself |
| Feruchemy (adjacent) | Store an attribute now (be weak), tap it later (be superhuman), via worn metalminds | Self-loan battery; deferred — see §6 |

Action core for a single-player voxel game: **iron, steel, pewter, tin**.
Emotional metals become creature-AI effects; duralumin is a late ultimate.

### 1.2 Stormlight — what makes it work

| Mechanic | Source rule | Why it's fun in a game |
|---|---|---|
| Highstorm | Periodic, predictable, lethal-in-the-open world event that recharges every exposed gemstone | The threat *is* the mana fountain — a recurring shelter-or-harvest risk ritual |
| Gems as batteries+currency | Spheres hold Stormlight; go "dun" when drained; crack when overdrawn | Your wallet is your mana bar |
| Breathing it in | Inhale from gems into your body; it leaks constantly (you glow); use it or lose it | Anti-hoarding mana: decays, advertises your position |
| Passive holding effects | Strength/speed, rapid healing (drains the pool ∝ damage), no fatigue | HP and mana partially merge — big hits survivable but expensive |
| Basic Lashing | Rebind personal gravity to any direction — fall sideways/up, walk on walls | Headline traversal verb; counterplay = light runs out mid-air |
| Full Lashing | Infuse a surface so things bond to it until light runs out | Glue traps, sealing, sticking blocks |
| Reverse Lashing | Make an object attract airborne things | Projectile magnet/lure; deferred |
| Other surges | Soulcasting (transmute), Abrasion (frictionless), Progression (growth), Cohesion (shape stone) | Cohesion/Soulcast = terrain editing as magic — natural fits later |

Cross-cutting design takeaways:

1. Both systems are **consumable-fueled, not cooldown-fueled** — scarcity, not
   timers, gates power. Anthesis already works this way (lumen).
2. **Movement is the killer app** — steel-push and Basic Lashing are
   physics-driven traversal with a real skill curve.
3. **The world recharges the player** — storms make refueling a place-and-time
   decision, which Anthesis currently has no analog for.

---

## 2. Fit Against the Current Codebase

What exists and is reused as-is:

- **`AbilityDef` → `CastCommand` → `MagicSystem.try_cast` → effect `Callable`**
  (`world.gd _install_ability_effects`, kind→Callable). All new active powers
  are plain abilities through this pipe. No `MagicSystem` gate-order changes.
- **`LumenWell`** (`add/spend/can_afford/changed`) is a generic reservoir —
  instantiate more of them for metal reserves and the tempest well.
- **`SimulationClock`** (10 ticks/s, deterministic) drives burn drain, light
  leak, status durations, and the storm schedule.
- **`CombatService.apply_damage(id, amount, knockback)`** already does
  velocity-additive knockback — push/pull on creatures rides this.
- **`IntensityModel.on_event`** — storms feed the adaptive music for free.
- **GUT patterns** — `FakeClock` + `EffectSpy` in `test_magic_system.gd` /
  `test_cast_command.gd` copy directly to every new system.

What does **not** exist and must be built (the real work):

| Gap | Needed by | Plan |
|---|---|---|
| Multi-resource casting (`AbilityDef.lumen_cost` is lumen-only) | Both | §3.1 — `resource_kind` on AbilityDef + well-resolver in MagicSystem |
| Status/buff system (Health is pure HP; knockback is the only secondary effect) | Pewter, tin, adhesion, stormlight passives | §3.2 — `StatusEffectSystem` |
| Sustained/toggled drains (casting is instantaneous-only) | Burning metals, holding light | §3.3 — `ChannelSystem` |
| Weather / scheduled world events (environment is static) | Highstorms | §5.2 — `WeatherSystem` |
| Per-instance item state (inventory is stack-based) | Gem charge | §5.3 — two item forms (`dun_gem` / `charged_gem`), never per-instance state |
| Metal-source awareness (nothing knows what's "metal") | Push/pull, blue lines | §4.2 — `MetalSourceRegistry` |
| Player gravity is hardcoded down (`velocity.y -= g`) | Basic Lashing | §5.5 — gravity-vector refactor in `player.gd` |

---

## 3. Shared Infrastructure (built in Phase 8, reused by Phase 9)

### 3.1 Multi-resource casting

- `AbilityDef`: add `@export var resource_kind: StringName = &"lumen"` (and
  rename nothing — `lumen_cost` stays as the cost field for compatibility;
  reading it as "resource cost" is a docs change).
- `MagicSystem._init(well, clock_tick)` →
  `MagicSystem._init(wells: Callable, clock_tick)` where `wells` is
  `func(kind: StringName) -> LumenWell`. World installs a resolver over
  `{&"lumen": _lumen_well, &"iron": ..., &"steel": ..., &"tempest": ...}`.
  Existing gate order (cooldown → cost → effect) is untouched; tests in
  `test_magic_system.gd` extend with a two-well fake.
- HUD `bind_magic` gains the extra wells; lumen bar logic is the template.

### 3.2 `StatusEffectSystem` (`scripts/systems/status/status_effect_system.gd`)

Tick-driven, `RefCounted`, owned by World, ticked from the clock handler:

```gdscript
func apply(target_id: int, effect_id: StringName, duration_ticks: int,
    on_apply: Callable, on_expire: Callable) -> void
func has(target_id: int, effect_id: StringName) -> bool
func clear(target_id: int, effect_id: StringName) -> void   # early removal
signal effect_applied(target_id, effect_id)
signal effect_expired(target_id, effect_id)
```

Re-applying refreshes duration (replace policy). Effects are *not* stat math —
they are paired callables (e.g. `on_apply` sets `player.speed_scale = 1.5`,
`on_expire` restores it), keeping the system tiny and gdlint-friendly. Targets
use the `CombatService` instance-id convention.

### 3.3 `ChannelSystem` (`scripts/systems/magic/channel_system.gd`)

Sustained drains the cast pipeline can't express:

```gdscript
func toggle(channel_id: StringName) -> bool   # via ToggleChannelCommand
func is_active(channel_id: StringName) -> bool
func set_flare(flaring: bool) -> void          # ×3 effect, ×3 drain
func tick() -> void   # drains the channel's well; deactivates at zero
signal channel_changed(channel_id, active)
```

A channel def binds: `resource_kind`, `drain_per_tick`, `on_start`/`on_stop`
callables (which usually delegate to `StatusEffectSystem`). When a reserve hits
zero the channel force-stops and fires `on_stop` — pewter drag hooks here.

New command: **`ToggleChannelCommand`** (`scripts/core/commands/`), client-local
like `CastCommand` (each player burns their own metals); no codec case needed.

---

## 4. Phase 8 — Ferromancy (metallurgy magic)

Player story: *mine lodestone and skysteel ore, refine them at the crafting
menu into burnable flakes, swallow a vial to fill that metal's reserve, then
burn it — yank a shardling off a ledge, coin-jump across a chasm, flare vigor
to win a melee, and watch the blue lines find ore veins through solid rock.*

### 4.1 Content (data-only, registry-scanned)

Items (`resources/items/`): `lodestone_ore`, `skysteel_ore`, `vigorite_ore`,
`keenglass_shard` (raw, mined/dropped); `iron_flakes`, `steel_flakes`,
`pewter_flakes`, `tin_flakes` (refined, the consumables); `ferric_coin`
(stackable throwable anchor — crafted cheaply, literally ammo-money).

Recipes (`resources/recipes/`): ore → flakes (×4), `crystal_shard + soil →
ferric_coin ×8`.

New world prop: **metal deposit** (flora-pattern prop like the crystal prop,
spawned by biome rules, harvestable → ore). Shardlings get a `metallic = true`
flag on `CreatureDef` (they already drop crystal; they become pullable).

**Swallowing flakes**: a `ConsumeItemCommand` (client-local) — using flakes
from the hotbar adds a fixed amount to that metal's reserve
(`MetalReserves.add`). Mirrors `HarvestCommand`'s `ctx.lumen_gain` pattern.

### 4.2 `MetalSourceRegistry` (`scripts/systems/magic/metal_source_registry.gd`)

Registry of pushable/pullable things: `register(node, mass, anchored)` /
`unregister(node)`; `sources_in_range(origin, radius) -> Array`. Registered by:
metal deposits (anchored, heavy), placed metal items, ferric coins (dynamic,
light), metallic creatures (dynamic, their body mass). Voxel terrain itself is
*not* metal — deposits are the in-terrain anchors, which keeps queries cheap
and gameplay legible.

**Blue lines**: while iron or steel reserve > 0 and the aim modifier is held,
an overlay (`scripts/ui/` or player-attached `ImmediateMesh`) draws lines from
the camera to each source in range, width ∝ mass, ignoring occlusion. Pure
presentation — reads the registry, mutates nothing (architecture rule 4 safe).

### 4.3 Abilities

All standard `AbilityDef` `.tres` + effect callables in
`world.gd _install_ability_effects` (file is integrator-only per `new-phase`):

| Ability | kind | resource | Effect |
|---|---|---|---|
| **Ferropull** | `ferro_pull` | iron | Nearest source along aim within range. Anchored or heavier-than-player → impulse player *toward* it (grapple). Lighter+dynamic → impulse it toward player (yank loot/coins/creatures; creatures via `apply_damage(id, 0.0, knockback)`) |
| **Ferropush** | `ferro_push` | steel | Mirror of pull. Anchored/heavier → launch player *away* (aim at ground deposit → vertical boost; the coin-jump: throw coin, push off it once it lands). Lighter → coin becomes a projectile (`DamageCommand` on hit) |
| **Vigor Burn** | channel `vigor` | pewter | Toggle: +40% move speed, +50% strike damage, 30% damage resist (statuses). On empty: **pewter drag** — inverse debuff for 10 s |
| **Keensight** | channel `keensight` | tin | Toggle: widened fog/brightness (environment tweak) + glow outline on creatures in 30 m (reuses glow-point presentation from FLORA) |
| **Ferric Surge** (duralumin, stretch) | `ferric_surge` | all | Dumps every reserve: one massive omnidirectional push + full vigor for 5 s |

Impulse math (kept simple, tunable): `impulse = magnitude * clampf(anchor_mass
/ player_mass, 0.3, 3.0)`, applied along the camera-to-source line only —
no lateral steering, which is the skill ceiling, per source material.

`ThrowCoinCommand` — **replicable** (spawns a world entity others must see):
needs a `CommandCodec` encode/decode case. Coin = small `RigidBody3D` scene
that self-registers with `MetalSourceRegistry` and despawns after ~60 s.

### 4.4 HUD

Four slim metal gauges (iron/steel/pewter/tin) beside the lumen bar, each
bound to its well's `changed` signal; channel-active glow; flare indicator.
Pattern-copy of the existing lumen bar in `scripts/ui/hud.gd`.

### 4.5 Phase 8 file ownership (new-phase contract)

| Builder | Owns |
|---|---|
| systems | `scripts/systems/status/*`, `scripts/systems/magic/channel_system.gd`, `metal_reserves.gd`, `metal_source_registry.gd` + unit tests |
| commands | `toggle_channel_command.gd`, `consume_item_command.gd`, `throw_coin_command.gd`, codec case + tests |
| content | all `.tres` (items/recipes/abilities), metal-deposit prop scene, coin scene + registry tests |
| presentation | HUD gauges, blue-line overlay + tests |
| integrator (solo) | `world.gd`, `world_context.gd`, `player.gd` input map, `project.godot`, `MagicSystem` resolver change |

Tests to copy from: `test_magic_system.gd` (gate), `test_cast_command.gd`
(command+spy), `test_lumen_well.gd` (reserves), `test_combat_service.gd`
(knockback), `test_spawn_system.gd` (deterministic deposit placement).

Docs: new `docs/systems/METALLURGY.md`; update `GAMEPLAY.md` (remember:
cooldowns at **10 ticks/s**), `CLAUDE.md` cookbook row for channels.

---

## 5. Phase 9 — Tempestlight & Resonance Storms

Player story: *the sky bruises violet and the music drops to a warning pulse —
a Resonance Storm is coming. You rack your dun gems on the storm catcher,
bolt for your dug-out shelter, and watch lightning hammer the surface. After,
you inhale a charged gem: your veins glow, wounds knit, and for ninety glowing
seconds you can fall sideways.*

### 5.1 Why storms first-class

Anthesis has no weather, day/night, or scheduled events — the storm is the
foundation Tempestlight stands on, and it doubles as the game's first world
event (music, lighting, danger). Build `WeatherSystem` generically enough that
future events (mist nights, aurora) reuse the scheduler.

### 5.2 `WeatherSystem` (`scripts/systems/weather/weather_system.gd`)

- **Deterministic schedule** from `WorldSeed.derive("weather")`: next storm in
  `randi_range(min,max)` ticks (default 6–10 min), pre-rolled so save-less
  sessions are still reproducible. States: `CALM → WARNING (45 s) → STORM
  (90 s) → CALM`, advanced on clock ticks. Signal: `weather_changed(state)`.
- **Warning**: sky/fog lerp via the environment scene, wind audio,
  `IntensityModel.on_event(&"storm_warning")` (new heat entry ~0.25).
- **Storm**: heavy fog + particle wind + `&"storm"` heat (~0.5); every 2 s,
  players/creatures **exposed to the sky** (upward `RayCast3D` clear) take
  storm damage via `DamageCommand` (routes through the command layer like all
  damage). Shelter = dig in or build a roof — existing verbs become survival.
- Exposure raycast result also gates gem charging (§5.3).

### 5.3 Gems — charge without per-instance state

Inventory is stack-based, so gem charge is **modeled as two items**, not a
stat: `dun_gem` ⇄ `charged_gem`. Conversion happens only in a placed
**storm catcher** (new placeable, crafted from `crystal_shard` +
`keenglass_shard`): during a storm, an exposed catcher converts its racked dun
gems to charged gems (a few per storm, capacity-limited). Charged gems are
also a rare shardling drop. No item-instance state anywhere — stacks stay
honest, replication stays trivial.

### 5.4 `TempestWell` — holding the light

A `LumenWell` instance (`&"tempest"`, capacity ~100) plus channel-like decay:

- **Inhale** (`InhaleCommand`, client-local): consumes one `charged_gem` from
  inventory → `+40` tempest, returns a `dun_gem` to inventory.
- **Leak**: `-0.5/tick` (~20 s per gem) ticked by `ChannelSystem` as an
  always-on channel while > 0 — built in Phase 8, reused here.
- **While holding** (statuses via `StatusEffectSystem`, refreshed each tick
  above zero): +20% move speed; **regeneration** — healing 1 HP costs 2
  tempest (the HP/mana merge from the source); a `Light3D` glow on the player
  scaled to the well level (stealth tradeoff arrives with stealth later).

### 5.5 Lashings (abilities, `resource_kind = &"tempest"`)

| Ability | kind | Effect |
|---|---|---|
| **Skylash** (Basic Lashing, self) | `sky_lash` | Rebind the player's gravity vector toward the aimed surface/direction for `magnitude` seconds. Requires the **gravity refactor**: `player.gd` replaces hardcoded `velocity.y -= g * delta` with a `_gravity_dir: Vector3` (default `DOWN`), sets `up_direction = -_gravity_dir` before `move_and_slide()`. **v1 scope: axis-aligned directions only** (fall up / four walls), no camera re-orientation — wall-*landing* works, full wall-*running* camera is a stretch goal. This refactor is the phase's hardest item and is integrator-owned |
| **Bondlash** (Full Lashing) | `bond_lash` | Cast at a creature: rooted status (velocity zeroed, AI hold) for `magnitude` s. Cast at terrain: a sticky patch (small `Area3D`) that roots whatever enters, until its tempest budget drains |
| **Gravity Well** (Reverse Lashing) | — | Deferred — needs projectile density to be worth it (see §6) |

Existing `skyward` ability stays as the lumen-school contrast; `sky_lash` at
`UP` is its sustained big sibling.

### 5.6 Phase 9 file ownership

| Builder | Owns |
|---|---|
| weather | `scripts/systems/weather/*`, storm visuals/audio hooks, IntensityModel heat entries + tests |
| gems | gem/catcher `.tres`, storm-catcher scene + placement (reuse `BlockPlacementService`), charge-conversion logic + tests |
| magic | `InhaleCommand`, tempest channel/status defs, lashing effect helpers + tests |
| presentation | HUD tempest meter + glow, storm warning banner + tests |
| integrator (solo) | `world.gd`, `world_context.gd`, **`player.gd` gravity refactor**, `project.godot` |

Docs: `docs/systems/WEATHER.md`, `docs/systems/TEMPESTLIGHT.md` (or one
combined STORMLIGHT doc); `GAMEPLAY.md`; ARCHITECTURE.md gains the weather
layer note.

---

## 6. Deferred (explicitly out of scope for 8–9)

- **Feruchemy metalminds** (store-now/tap-later) — wants per-instance item
  state or an equipment system; revisit after equipment exists.
- **Emotional metals** (riot/soothe AI), **bronze/copper** (magic
  radar/stealth) — want a richer AI aggro model first.
- **Reverse Lashing, Soulcasting, Abrasion, Cohesion** — Cohesion especially
  is a natural fit for smooth-voxel terrain editing, as a future lumen-school
  upgrade.
- **Aluminum** (push/pull immunity) as endgame counterplay gear.
- **Sneak/visibility** interactions with the tempest glow.

## 7. Risks & gotchas (pre-checked against CLAUDE.md)

- **`world.gd` public-method gdlint cap (20)** — World is at it. New systems
  hang off `WorldContext` fields and named child nodes, not World getters.
- **Effect-returns-false = no spend** — push/pull with no source in range must
  return `false` so no steel is wasted (free targeting check).
- **Cast is client-local; coin-throw and storm damage are not** —
  `ThrowCoinCommand` needs a codec case; storm damage routes `DamageCommand`s
  from the host-side weather tick in co-op.
- **Storm schedule + gem conversion must use `WorldSeed` streams** (rule 6) —
  no wall-clock time, no bare `randf()`; the storm clock is tick-indexed.
- **`height_at` NAN** — storm exposure raycasts, not terrain height queries.
- **Tick math** — all durations in this doc assume **10 ticks/s**.
- **Ability hotbar ordering is alphabetical by id** — name ability ids with
  intentional prefixes (`ferro_*`, `lash_*`) so slots group sensibly.
- **`.tres` typed arrays** — copy `voidmoth.tres` syntax exactly.

## 8. Suggested sequencing

1. **Phase 8 (Ferromancy)** first: it builds the shared substrate (statuses,
   channels, multi-well casting) with zero new world-state, so the risk is
   contained to systems code. Push/pull alone is a shippable, screenshot-able
   payoff (`verify-live`: coin-jump across a chasm).
2. **Phase 9 (Tempestlight)** second: weather rides the proven channel/status
   substrate; the only deep cut is the player gravity refactor.
3. Run each via the **`new-phase`** skill (scout → contracts → parallel
   builders → integrator → skeptic → live verify → PR), one squash-merged PR
   per phase, screenshots in `docs/media/`.
