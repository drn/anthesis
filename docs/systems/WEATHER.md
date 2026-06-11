# Weather System

The weather system drives Resonance Storms — the environmental hazard that
forces the player above ground *and* provides the only source of charged gems
that power Tempestlight. The design is deliberately punishing and rewarding at
once: survival requires preparation; a well-placed storm catcher turns the storm
into a harvest.

---

## Key Files

| File | Role |
|------|------|
| `scripts/systems/weather/weather_system.gd` | `WeatherSystem` — deterministic storm schedule |
| `scripts/systems/weather/storm_catcher.gd` | `StormCatcher` — crystal pylon that charges dun gems |
| `scripts/ui/storm_visuals.gd` | `StormVisuals` — environmental presentation layer |
| `scripts/systems/world/tempest_rig.gd` | `TempestRig` — integrator extract; owns storm wiring in `World` |
| `scripts/systems/audio/intensity_model.gd` | `IntensityModel` — receives `storm_warning` / `storm` heat events |
| `tests/unit/test_weather_system.gd` | Determinism, state machine, pulse cadence, force_storm |
| `tests/unit/test_storm_catcher.gd` | Deposit/collect/charge bounds, signal |
| `tests/integration/test_world_tempest.gd` | World boot, force_storm, catcher charging end-to-end |

---

## WeatherSystem

`WeatherSystem` (`extends Node`, named `"Weather"`) owns the storm schedule.

```gdscript
class_name WeatherSystem extends Node

signal weather_changed(state: StringName)  # &"calm" / &"warning" / &"storm"
signal storm_pulse(pulse_index: int)       # every PULSE_INTERVAL ticks during storm

const WARNING_TICKS     := 450    # 45 s
const STORM_TICKS       := 900    # 90 s
const STORM_MIN_GAP_TICKS := 3600 # 6 min
const STORM_MAX_GAP_TICKS := 6000 # 10 min
const PULSE_INTERVAL    := 20     # 2 s between pulses

func setup(rng: RandomNumberGenerator) -> void
func state() -> StringName         # starts &"calm"
func ticks_until_storm() -> int    # 0 during warning/storm
func force_storm() -> void         # debug: next on_tick enters warning with a 10-tick gap
func on_tick(tick: int) -> void
```

### Lifecycle

```
calm (6–10 min, drawn from rng) ──► warning (45 s) ──► storm (90 s) ──► calm
                                                            ▲
                                                     pulse every 2 s
                                                     (pulse_index 0, 1, 2…)
```

- `weather_changed` fires on every transition; it does not fire at setup.
- During the storm, `storm_pulse` fires 45 times per storm (every 20 ticks for
  900 ticks), `pulse_index` incrementing from 0.
- After the storm ends, a new calm gap is rolled from the injected `rng` stream
  and the cycle restarts.

### Determinism

`WeatherSystem` consumes randomness exclusively from the `RandomNumberGenerator`
passed to `setup()`. In `World`, this is `_world_seed.derive("weather")`. Same
seed → identical storm schedule every session. No wall-clock, no `randf()`.

The gap to the first storm is drawn at `setup`; subsequent gaps are drawn at the
moment each storm ends. Two instances seeded identically produce the same
transition-tick sequence over any number of storms.

---

## Storm Damage and Exposure Rule

On each `storm_pulse`, `TempestRig._on_storm_pulse` (authority-gated via
`_session.has_authority()`) does two things:

1. **Player exposure check.** A physics ray is cast from the player origin + 0.5 m
   upward to + 200 m. If no hit: the player is sky-exposed → submit
   `DamageCommand.new(player_id, 3.0, Vector3.ZERO)`.
2. **Catcher charge sweep.** For each node in group `&"storm_catchers"`, the same
   ray is cast. If sky-exposed: `catcher.charge_one()` converts one dun gem to
   charged.

**Exposure rule:** a structure directly overhead blocks storm damage. Dig a shelter
or roof your catcher site and neither you nor your gems get zapped.

The 3 HP per pulse and 2-second cadence set a tolerable survival window but punish
complacency: standing in the open for a full 90-second storm costs 135 HP —
far more than the player's max. Find cover or die.

---

## StormCatcher

`StormCatcher` (`extends StaticBody3D`, scene `scenes/props/storm_catcher.tscn`)
is the crystal pylon that racks dun gems and charges them during a storm.

```gdscript
class_name StormCatcher extends StaticBody3D

signal gems_changed(dun: int, charged: int)

const CAPACITY := 4  # maximum gems in the rack

func deposit(count: int) -> int      # accepts up to remaining capacity; returns accepted count
func collect() -> Dictionary         # {"dun": int, "charged": int}; empties the rack
func charge_one() -> bool            # one dun -> charged; false when no dun present
func dun_count() -> int
func charged_count() -> int
```

`StormCatcher` joins group `&"storm_catchers"` in `_ready` so `TempestRig` can
sweep them on each pulse.

The scene geometry is a small antenna-like crystal pylon. A gem-row visual
brightens as `charged_count` rises (handled in a `gems_changed` callback that
swaps emissive materials or toggles per-gem `MeshInstance3D` visibility).

Interact with a catcher via **E** (see `InteractCatcherCommand`):
- If the rack holds any gems (dun or charged): **collect** — empty the rack into
  inventory (`dun_gem` and `charged_gem` counts credited).
- If the rack is empty: **deposit** — transfer up to `CAPACITY` dun gems from
  inventory into the rack.

---

## StormVisuals

`StormVisuals` (`extends Node`) is a pure presentation node that reacts to
`WeatherSystem.weather_changed`. It lives in the TempestRig and is presentation-only
— it never reads or writes game state.

```gdscript
class_name StormVisuals extends Node

func setup(weather: Object, environment_rig: Node) -> void
```

On `weather_changed`:

| State | Effect |
|-------|--------|
| `&"calm"` | Restore baseline fog density, moonlight energy, sky tint (tweened ~3 s) |
| `&"warning"` | Tween (~3 s): fog density ×2.5, moonlight energy ×0.6, sky tint toward bruised violet |
| `&"storm"` | Fog density ×5, moonlight energy ×0.35, GPUParticles3D wind layer activates (streaking translucent quads) |

Baseline values are cached from the `WorldEnvironment` and `Moonlight` children of
the environment rig at `setup()` time.

---

## IntensityModel (weather additions)

Two new HEAT entries drive the adaptive music during storms:

| Event kind | Heat added |
|-----------|------------|
| `&"storm_warning"` | 0.25 |
| `&"storm"` | 0.50 |

`world.gd` (via `TempestRig`) feeds `_intensity.on_event(&"storm_warning")` on the
warning transition and `_intensity.on_event(&"storm")` on the storm transition. The
music layers in progressively as the sky bruises.

---

## How to Extend

### Add a new weather state

1. Pick a `StringName` id (e.g. `&"blizzard"`).
2. In `WeatherSystem.on_tick`, add a branch between existing state transitions.
   Insert into the calm→warning→storm machine where it fits narratively.
3. Emit `weather_changed(&"blizzard")` on entry.
4. Add a visual block in `StormVisuals._on_weather_changed` that tweens the
   new appearance.
5. Wire an `IntensityModel.on_event` call in `TempestRig` if the new state
   should affect the music.
6. Test the new state with `test_weather_system.gd` — copy the
   `test_storm_returns_to_calm_with_new_gap` pattern for state-machine ordering.

### Add a new storm effect (e.g. lightning strike)

1. Connect a new handler to `WeatherSystem.storm_pulse` in `TempestRig`.
2. Gate on `_session.has_authority()` as the existing pulse handler does.
3. Do the effect through the command bus (e.g. a new `LightningStrikeCommand`) —
   never mutate world state from the presentation signal directly.
4. Write a unit test that calls `on_tick` enough times to trigger a pulse and
   asserts the command was submitted.

---

## Testing Notes

`tests/unit/test_weather_system.gd` key patterns:

- **Determinism test.** Two `WeatherSystem` instances, same seed. Manually drive
  `on_tick` over 20 000 simulated ticks. Assert every `weather_changed` emission
  matches between the two instances.
- **Pulse cadence.** Force a storm with `force_storm()`, then drive 10 + 900 ticks
  (10-tick warning + 900-tick storm). Assert exactly 45 `storm_pulse` emissions with
  indices 0–44.
- **Off-by-one trap.** The storm loop bound is `11 + STORM_TICKS` ticks from
  `force_storm()`: 1 calm + 10 warning + 900 storm. The test that was wrong used
  `10 + STORM_TICKS` and missed the last pulse.

`tests/unit/test_storm_catcher.gd`: deposit capacity, collect empties completely,
`charge_one` returns false with no dun, `gems_changed` signal fires on changes.

---

## Gotchas

- **`force_storm()` is for tests and harnesses only.** In normal gameplay the
  schedule is driven by the seeded RNG. Calling `force_storm()` in production wiring
  breaks determinism.
- **Sky-exposure ray excludes the node itself.** The PhysicsDirectSpaceState3D ray
  from the player or catcher must pass an exclusion set containing the querying
  node, or it will self-intersect and always report "blocked".
- **Authority gate matters.** Storm damage fires only on the authority peer
  (`_session.has_authority()`). In solo play (offline) that is always true.
  In co-op the host is the sole damage authority; clients see the visual effects
  but the host submits the damage commands.
- **`weather_changed` does not fire at `setup()`.** If you connect a handler after
  `setup()` has been called, you must read the initial `state()` yourself to sync
  your display to the current state; the signal will not back-fill the initial
  `&"calm"` transition.
- **Catcher collect vs. deposit is toggled by gem count.** `InteractCatcherCommand`
  calls `collect()` if `dun_count() + charged_count() > 0`, otherwise `deposit()`.
  A partially filled catcher always collects on the next E press — you cannot top
  up a non-empty rack via interact; manually remove gems first.
