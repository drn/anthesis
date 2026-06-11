# Anthesis — AI Build Conventions

Anthesis is a single-player, open-source (MIT) cosmic-whimsical voxel adventure game with smooth diggable terrain, Sanderson-inspired magic, deep crafting, and adaptive EDM music.

---

## Tech Stack

| Fact | Value |
|------|-------|
| Engine | Godot 4.6 custom build (`4.6.stable.custom_build`) |
| Voxel module | Zylann `godot_voxel` v1.6 (compiled in) |
| Renderer | Forward+ (Metal on macOS) |
| Language | GDScript |
| Lint / format | gdtoolkit 4.x — `gdlint`, `gdformat` |
| Test framework | GUT 9.6.0 (vendored at `addons/gut/`) |
| Editor binary | `tools/godot/macos_editor.app/Contents/MacOS/Godot` (macOS, gitignored) |
| Repo | https://github.com/drn/anthesis |
| License | MIT, 2026. Author: Darren Cheng |

Prebuilt binaries: https://github.com/Zylann/godot_voxel/releases/tag/v1.6

**Nested-zip note (macOS):** `godot.macos.editor.app.zip` contains `macos_editor.app.zip` which contains `macos_editor.app`. `scripts/setup.sh` handles this automatically.

---

## Key Commands

```bash
make setup         # download Godot+voxel prebuilt
make stems         # (re)generate the adaptive-music stem WAVs (deterministic)
make import        # import assets (required before first test run)
make test          # headless GUT test suite
make lint          # gdlint all *.gd files
make format        # gdformat all *.gd files
make format-check  # format check (CI-safe, no writes)
make edit          # open Godot editor
make run           # run the game
```

Headless test invocation (for reference):
```
<godot-binary> --headless --path . -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
```

---

## Documentation Map

Every doc, what it covers, and when to read it:

| Doc | Covers |
|-----|--------|
| `README.md` | Project status, screenshot gallery, controls, quick start |
| `docs/GAMEPLAY.md` | Player-facing guide — items, recipes, abilities, creatures, sequencer how-to. Update when gameplay-visible values change |
| `CLAUDE.md` (this file) | AI build conventions, hard rules, layout, cookbook, gotchas |
| `AGENTS.md` | One-page mirror of the essentials for any agent |
| `CONTRIBUTING.md` | Human contributor workflow |
| `docs/ARCHITECTURE.md` | The layer model + per-phase subsections — read before structural changes |
| `docs/COMMANDS.md` | The command/intent layer all world mutations route through |
| `docs/systems/*.md` | Per-system deep dives (extend-this-system docs); one file per system |

Per-system docs under `docs/systems/` go deeper than the architecture doc: each
is an "I need to extend this system" guide (key files, real flow with real symbol
names, how-to-extend steps, which tests to copy, gotchas).

---

## Verification

Two repo skills under `.claude/skills/` capture the workflows that ship phases:

- **`verify-live`** — boot the real `world.tscn` windowed via a `SceneTree`
  harness, drive gameplay through `world.command_bus().execute(...)`, screenshot
  the framebuffer, and check for script errors. Use to prove a change works in
  the running game (not just in tests) and to make PR media.
- **`new-phase`** — the pinned-contract parallel workflow that built phases 1-7:
  scout → contracts → strict file ownership → parallel builders → integrator →
  skeptic → live verify → PR + squash-merge.

Live-harness one-liner (windowed; never `--headless` for visual verification):

```bash
HOME=/tmp/anthesis-home tools/godot/macos_editor.app/Contents/MacOS/Godot \
  --path . -s res://scripts/tools/verify/<name>.gd
```

The full GUT suite (note the same `HOME` override):

```bash
HOME=/tmp/anthesis-home tools/godot/macos_editor.app/Contents/MacOS/Godot \
  --headless --path . -s res://addons/gut/gut_cmdln.gd \
  -gconfig=res://.gutconfig.json -gexit
```

Lint / format (gdtoolkit 4.x):

```bash
find scripts tests -name "*.gd" | xargs uvx --from "gdtoolkit==4.*" gdformat
find scripts tests -name "*.gd" | xargs uvx --from "gdtoolkit==4.*" gdlint
```

---

## Adding Content Cookbook

All game content is data (`.tres`), loaded by a registry, wired by `World`.
Mutations route through the command bus. Quick map of "I want to add X":

| Add a… | Create | Wired / loaded by | Deep dive |
|--------|--------|-------------------|-----------|
| Item | `resources/items/<id>.tres` (`ItemDef`) | `ItemRegistry` (auto-scans dir) | `docs/systems/CRAFTING.md` |
| Recipe | `resources/recipes/<id>.tres` (`Recipe`) | `ItemRegistry` / `CraftingService` | `docs/systems/CRAFTING.md` |
| Ability | `resources/abilities/<id>.tres` (`AbilityDef`) + effect `Callable` in `world.gd` `_install_ability_effects` (`kind`→fn) | `AbilityRegistry` + `MagicSystem` | `docs/systems/MAGIC.md` |
| Metal ability | Same as Ability + set `resource_kind = &"<metal>"` on the `.tres`; add the kind → flake-id pair to `FLAKE_MAP` in `world.gd` if it's a new metal | `MagicSystem` multi-well resolver | `docs/systems/METALLURGY.md` |
| Sustained channel | `channels.install(id, def)` in `FerromancyRig.install_channels` (def: `{resource_kind, drain_per_tick, on_start, on_stop}`) + input action in `project.godot` + player signal + route in `world.gd` | `ChannelSystem` + `StatusEffectSystem` | `docs/systems/METALLURGY.md` |
| Metal source | Add `var metal_mass: float` + `func is_metal_anchored() -> bool` + `add_to_group(&"metal_sources")` in `_ready` to any Node3D | `FerroKinetics.select_source` (scene tree group query) | `docs/systems/METALLURGY.md` |
| Creature | `resources/creatures/<id>.tres` (`CreatureDef`) | `CreatureRegistry` + `SpawnSystem` | `docs/systems/COMBAT.md` |
| Music stem | `resources/music/<id>.tres` (`MusicStemDef`) + WAV via `make stems` | `MusicStemRegistry` + `MusicSystem` | `docs/systems/MUSIC.md` |
| Command | `scripts/core/commands/<name>_command.gd` (`extends WorldCommand`) + a `WorldContext` field if it needs a new service + `CommandCodec` case if replicable | `CommandBus` / `CommandRouter` | `docs/COMMANDS.md` |

Rules of thumb: a new ability `kind` needs **both** a `.tres` (data) and an effect
`Callable` registered in `world.gd` (behavior). A metal ability also needs
`resource_kind` on the `.tres` — leave it empty or `&"lumen"` for lumen abilities.
A new replicable command needs a `CommandCodec.encode`/`decode` case or it stays
client-local. Registries auto-scan their directory — no code edit to add a
pure-data item/recipe/creature/stem. Copy an existing `.tres` for the exact
typed-array / sub-resource syntax.

---

## Hard Rules

These rules are non-negotiable. Every agent, every PR, every change.

1. **Tests required.** Every change ships with GUT tests. Run `make test` before declaring done. All tests must pass.
2. **Never touch `addons/`.** The `addons/` tree is vendored (GUT, godot_voxel). Do not modify, move, or delete anything under it.
3. **No secrets, no tools/.** Never commit credentials, tokens, or `.env` files. Never commit anything under `tools/` (it is gitignored).
4. **Command layer for world mutations.** All writes to voxel/world data must route through the command/intent layer. Direct mutations from presentation or render code are forbidden.
5. **Data as resources, not code.** Items, recipes, flora, and biomes are Godot `.tres` resource files under `resources/`. Do not encode game data as GDScript constants or dictionaries.
6. **Deterministic RNG.** All randomness uses seeded `WorldSeed` streams. Never call `randf()` or `randi()` directly in game logic.
7. **GDScript style.** Tabs for indentation (Godot/gdformat convention). `snake_case` for variables, functions, and files. `PascalCase` for classes/nodes.
8. **Squash-merge only.** PRs land as a single squash commit onto `master`. No merge commits, no rebase-merges.

---

## Architecture Overview

Layered, multiplayer-ready:

```
voxel/world data (source of truth)
  ⟂ render mesh (disposable, regenerated on demand)
    ⟂ tick-based simulation
      ⟂ presentation (UI, VFX, audio)
```

See `docs/ARCHITECTURE.md` for the full design.

---

## Directory Layout

```
scenes/              Godot scene files (.tscn) — incl. scenes/ui/, scenes/creatures/
scripts/core/        Engine-level systems (world, voxels, commands, items)
scripts/core/items/  Item/recipe data contracts (ItemDef, ItemAmount, Recipe)
scripts/core/magic/  Ability data contract (AbilityDef)
scripts/core/combat/ Creature data contract (CreatureDef)
scripts/core/audio/  Music stem data contract (MusicStemDef)
scripts/core/sim/    Tick substrate (SimulationClock)
scripts/core/net/    Replication wire format (CommandCodec, CommandLog) — pure, no networking
scripts/systems/     Gameplay systems (items, inventory, crafting, flora, biomes)
scripts/systems/magic/   Lumen + metal magic (LumenWell, MagicSystem, AbilityRegistry, MetalReserves, ChannelSystem, FerroKinetics, FerricCoin)
scripts/systems/combat/  Combat (Health, CombatService, CreatureRegistry, Umbral, SpawnSystem)
scripts/systems/status/  Status effects (StatusEffectSystem — vigor, keensight, pewter drag)
scripts/systems/world/   World-level integrator extractions (FerromancyRig)
scripts/systems/audio/   Adaptive music (IntensityModel, MusicStemRegistry, MusicSystem)
scripts/systems/sequencer/ In-world sequencer (StepTimeline, SectorMath, SequencerCore, NoteBlock, BlockPlacementService)
scripts/systems/net/ Co-op runtime (NetworkSession, CommandRouter, PlayerSync, RemotePlayer)
scripts/systems/settings/ Settings (GameSettings model, SettingsApplier — pause menu, Escape)
scripts/tools/       Dev/build scripts (generate_stems.py, generate_notes.py — procedural audio synth)
scripts/tools/net_smoke/ Two-instance live co-op smoke test (host_test.gd, client_test.gd — NOT in GUT suite)
scripts/ui/          UI scripts (hud, inventory_panel, session_panel, pause_menu)
resources/items/     Item .tres definitions (soil, crystal_shard, …)
resources/recipes/   Crafting recipe .tres files (bloom_brick, lumen_torch)
resources/abilities/ Ability .tres files (shape_burst, lumen_bloom, skyward)
resources/creatures/ Creature .tres files (voidmoth, shardling)
resources/music/     Music stem .tres files (pad, bass, arp, drums, shimmer)
resources/           Data resources (.tres) — items, recipes, abilities, creatures, flora
assets/audio/music/  Procedurally generated stem WAVs (regenerate via `make stems`)
shaders/             GLSL / Godot shaders
assets/              Art, audio, fonts (binary, gitignored if large)
tests/unit/          GUT unit tests
tests/integration/   GUT integration tests
scripts/tools/verify/ Live SceneTree verification harnesses (windowed; NOT in GUT suite)
addons/              Vendored (GUT, godot_voxel) — DO NOT MODIFY
docs/                Design docs and architecture
docs/systems/        Per-system deep dives (one .md per system)
docs/media/          PR/README screenshots (committed)
.claude/skills/      Repo skills (verify-live, new-phase)
tools/               Local binaries (gitignored)
scripts/             Shell scripts (setup.sh, etc.) + GDScript subdirs
```

---

## Known Gotchas

Traps seen building phases 1-8. Check these before debugging from scratch:

- **`HOME` override.** Every raw binary invocation must prefix
  `HOME=/tmp/anthesis-home` so the editor never writes to the real home. `make`
  targets handle this (via `GODOT_RUN`); direct invocations do not. The
  directory must exist first — Godot segfaults in `RotatedFileLogger` when it
  cannot create `user://logs` (e.g. sandboxed writes to the real home), so
  `mkdir -p /tmp/anthesis-home` before any direct invocation.
- **`make setup` before anything in a fresh worktree.** `tools/` is gitignored,
  so a new worktree has no Godot binary — every `make` target that invokes the
  editor fails with exit 1 until `make setup` downloads it.
- **`--import` first.** A fresh worktree has no `.godot/imported/` cache. Run
  `make import` (or `<binary> --headless --path . --import`) before the first
  test run or after adding any `.tres` / asset, or you get missing-import errors.
  Also re-run it after a rebase/pull that brings in new scripts — a stale
  `class_name` cache produces walls of `Identifier "X" not declared` parse errors.
- **Push with an explicit refspec.** A bare `git push` (or
  `git push --force-with-lease`) under `push.default=matching` pushes *every*
  matching local branch — a stale local `master` will force-rewind
  `origin/master`, and `--force-with-lease` does not protect against it (the
  lease checks the expected remote value, not the direction of movement). Use
  `git push origin HEAD` / `git push origin <branch>`, or set
  `git config push.default current` in the clone.
- **`height_at` returns NAN.** Terrain streams asynchronously; `VoxelWorld.height_at`
  returns `NAN` until the chunk streams in. Gate all position-dependent logic on
  `not is_nan(...)`. World parks the player at `PLAYER_SAFE_ALTITUDE` and polls.
- **`ZN_FastNoiseLite` type trap.** `VoxelGeneratorNoise.noise` is typed to Godot's
  built-in `FastNoiseLite`, not `godot_voxel`'s `ZN_FastNoiseLite`. Use built-in
  `FastNoiseLite` (`frequency` directly) — see `voxel_world.gd`.
- **Tick rate is 10/s.** `SimulationClock.ticks_per_second = 10.0` — convert
  `cooldown_ticks` and other tick counts at 10 ticks per second (20 ticks =
  2.0 s), not 20 or 60. Easy to get wrong when writing player-facing docs.
- **int64 literals.** Keep seed/hash math inside `WorldSeed.derive(...)` streams;
  hand-rolled bit math overflows 32-bit and wraps silently.
- **Callable GC.** A `Callable` seam (clock-tick fn, `voxel_tool` provider) is
  collected if nothing holds its owning object. Store the owner, not just the fn.
- **gdlint ceilings.** `gdlint` caps public methods per class (20). World is at the cap
  — `SimulationClock` is fetched via `get_node("SimulationClock")`, not a getter.
  Don't add gratuitous getters near the cap; gate introspection on named nodes.
  Test files hit it too (every `test_*` func is public): the convention is to
  split into a focused sibling file (see `test_cast_command.gd`,
  `test_inventory_hotkey.gd`), not to disable the check.
- **`.tres` typed-array syntax.** Use `field = Array[ExtResource("2")]([SubResource("x")])`,
  not a bare `[...]`. Copy an existing `.tres` exactly (e.g. `voidmoth.tres`).
- **`connected_to_server` deferral.** RPCs to the host before the ENet handshake
  are silently dropped. `NetworkSession` defers `session_started(false)` until
  `connected_to_server` — never RPC the host the instant after `join()`.
- **Parallel file collisions.** `project.godot` and `world.gd` are integrator-only
  (see `new-phase`). Builders never edit them, or parallel work collides on merge.
- **`gdlintrc` raises `max-file-lines: 1200`.** Added in Phase 8 to accommodate
  `world.gd` (1145 lines after `FerromancyRig` extraction). Only the line-count
  heuristic is relaxed — all correctness rules keep their defaults. Do not raise
  it further without extracting more behaviour first.
- **`kinds()` StringName sort.** `metal_reserves.kinds()` uses `sort_custom` with
  a `String(a) < String(b)` comparator — NOT `Array.sort()`, which orders by
  internal hash. Any code that iterates `kinds()` and expects stable UI order
  depends on lexical ordering. Don't revert this to a bare `sort()`.
- **Metal wells start empty.** Like `LumenWell`, every metal well starts at 0
  charge. Tests that need to cast a metal ability must either `add(kind, amount)`
  directly or pre-stock the test inventory with flakes.
- **`ensure` is lazy, not eager.** `MetalReserves.ensure` tops up only until the
  well can afford the requested `amount`. It does not fill the well to capacity.
  Passing `inventory = null` is safe and means "don't swallow, just check".
- **`ChannelSystem` is a `Node`, not `RefCounted`.** If you instantiate it outside
  the scene tree and connect `SimulationClock.ticked` to `on_tick`, it can be
  GC'd. Always `add_child` it (the integrator names it `"Channels"`).

---

## Orchestration Notes

Argus orchestrates dynamic multi-agent workflows for this repo:

- **Fable** — top-level orchestrator; coordinates agents and workflows.
- **Opus sub-agents** — complex / novel work: shaders, terrain algorithms, voxel simulation, novel systems design.
- **Sonnet sub-agents** — mechanical work: boilerplate, data authoring (.tres), documentation, test scaffolding.

See also: `CONTRIBUTING.md`
