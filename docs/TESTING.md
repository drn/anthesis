# Anthesis — Testing Guide

This guide covers GUT conventions, the full test-file index, testability patterns used
in the codebase, stub/fake patterns, determinism testing, and CI pipeline anatomy.

---

## GUT conventions

The project uses [GUT 9.6.0](https://github.com/bitwes/Gut), vendored at
`addons/gut/`. Configuration lives in `.gutconfig.json`:

```json
{
    "dirs": ["res://tests/unit", "res://tests/integration"],
    "include_subdirs": true,
    "should_exit": true,
    "log_level": 1
}
```

### File and class rules

- Test files are named `test_*.gd` and live under `tests/unit/` or
  `tests/integration/`.
- Every test script begins with `extends GutTest` (not `extends Node`).
- Test functions are named `test_*` — GUT discovers them by prefix.
- Use `add_child_autofree(node)` to add nodes to the scene tree inside a test. GUT
  frees them after each test, preventing leaks.
- `before_each()` / `after_each()` hooks are the right place for per-test setup and
  teardown.

### Assertions

Prefer GUT's typed assertions for clear failure messages:

```gdscript
assert_eq(a, b, "message")
assert_true(condition, "message")
assert_false(condition, "message")
assert_not_null(value, "message")
assert_almost_eq(a, b, epsilon, "message")  # for floats
assert_gt(a, b, "message")
assert_signal_emitted(object, "signal_name")
assert_signal_emitted_with_parameters(object, "signal_name", [arg1, arg2])
```

To assert signals, call `watch_signals(object)` before the action that fires them.

---

## Test file index

### Unit tests (`tests/unit/`)

| File | What it covers |
|------|---------------|
| `test_ability_registry.gd` | `AbilityRegistry` scan and id resolution |
| `test_ability_resources.gd` | `.tres` ability resource field validation |
| `test_block_commands.gd` | `PlaceBlockCommand`, `RemoveBlockCommand`, `CycleNoteCommand` apply logic |
| `test_block_items.gd` | Note-block item def and inventory integration |
| `test_block_placement_service.gd` | `BlockPlacementService` grid-snap, inventory gate, core binding |
| `test_cast_command.gd` | `CastCommand` routing through `MagicSystem` |
| `test_combat_service.gd` | `CombatService` registration, damage routing, knockback |
| `test_command_codec.gd` | `CommandCodec` encode/decode round-trips, range gates, null on stale target |
| `test_command_log.gd` | `CommandLog` append, eviction at `MAX_ENTRIES` (5000), `dropped()` counter |
| `test_command_router.gd` | `CommandRouter` offline/host/client routing, `_commit`/`_handle_request`/`_handle_commit`, state handshake |
| `test_commands.gd` | `DigCommand`, `PlaceCommand`, `HarvestCommand`, `CraftCommand` base apply contracts |
| `test_crafting_service.gd` | `CraftingService` atomicity (no partial consume), output-fits guard |
| `test_creature_registry.gd` | `CreatureRegistry` scan and id resolution |
| `test_creature_resources.gd` | `.tres` creature resource field validation |
| `test_damage_command.gd` | `DamageCommand` applies damage and knockback via `CombatService` |
| `test_environment.gd` | Environment_Rig scene structure and `WorldEnvironment` presence |
| `test_flora_scatter.gd` | `FloraScatter` deterministic placement from `WorldSeed` |
| `test_health.gd` | `Health` `take_damage` clamp, `died` fires once, `heal` clamp, dead guard |
| `test_hud.gd` | `Hud` wiring: inventory panel, lumen bar, ability slots, crafting callback |
| `test_hud_combat.gd` | `Hud` health bar binding, hurt vignette, death overlay signals |
| `test_intensity_model.gd` | `IntensityModel` heat values, decay, clamp, determinism, no-RNG guard |
| `test_inventory.gd` | `Inventory` 24-slot stack add/remove, overflow, `changed` signal |
| `test_item_registry.gd` | `ItemRegistry` scan, `item()`, `recipe()` resolution |
| `test_item_resources.gd` | `.tres` item resource field validation |
| `test_loot_service.gd` | `LootService` deterministic drops from `WorldSeed` "loot" stream |
| `test_lumen_well.gd` | `LumenWell` `add`/`spend` clamp, all-or-nothing spend, `changed` signal |
| `test_magic_system.gd` | `MagicSystem` cooldown gate, cost gate, effect-first adjudication |
| `test_music_assets.gd` | WAV file presence, length, format (44100 Hz, mono, ~17.45 s) |
| `test_music_stem_registry.gd` | `MusicStemRegistry` scan and id resolution |
| `test_music_stem_resources.gd` | `.tres` stem resource field validation |
| `test_music_system.gd` | `MusicSystem` pure `volume_db_for` mapping, player construction, slew |
| `test_network_session.gd` | `NetworkSession` offline defaults, constants, API surface |
| `test_note_assets.gd` | Note-bank WAV file presence and format |
| `test_note_block.gd` | `NoteBlock` pitch cycling, emissive colour update |
| `test_player.gd` | `Player` signal declarations, input-handler no-mutation contract |
| `test_player_sync.gd` | `PlayerSync` position broadcast interval, `_send` override capture |
| `test_props.gd` | Harvestable prop scene structure and `Harvestable` signal wiring |
| `test_remote_player.gd` | `RemotePlayer` lerp, snap-beyond-8m, label update |
| `test_sector_math.gd` | `SectorMath.step_for_offset` — north=0, clockwise, boundary snap |
| `test_sequencer_core.gd` | `SequencerCore` step firing, marker ring, transport binding |
| `test_session_panel.gd` | `SessionPanel` host/join/leave UI wiring |
| `test_simulation_clock.gd` | `SimulationClock` tick rate, catch-up cap, pause/resume |
| `test_spawn_system.gd` | `SpawnSystem` interval gating, population cap, glow-rejection, determinism |
| `test_step_timeline.gd` | `StepTimeline` durations, `step_at`, `steps_crossed` (including wrap) |
| `test_terrain_edit_service.gd` | `TerrainEditService` dig/place delegation to voxel tool |
| `test_umbral.gd` | `Umbral` node: dissolve on death, `perished` signal |
| `test_umbral_ai.gd` | `UmbralAI` state machine, wander cadence, attack cooldown, determinism |
| `test_voxel_world.gd` | `VoxelWorld` scene structure, mesher type, generator type, seed wiring |
| `test_world_seed.gd` | `WorldSeed` same-seed reproducibility, cross-stream isolation |

### Integration tests (`tests/integration/`)

| File | What it covers |
|------|---------------|
| `test_world_boot.gd` | Full `world.tscn` subsystem graph: terrain, player, flora, command bus wiring, Phase 3 magic substrate |
| `test_world_combat.gd` | Phase 4 combat wiring: `CombatService`, `SpawnSystem`, player `Health`, Umbral lifecycle |
| `test_world_music.gd` | Phase 5 music wiring: `IntensityModel`, `MusicSystem`, stem players, `command_executed` intensity feed |
| `test_world_net.gd` | Phase 7 net wiring: offline default, router seam, `rebuild_for_session`, command log |
| `test_world_sequencer.gd` | Phase 6 sequencer wiring: `BlockPlacementService`, `SequencerCore` step firing, note-bank playback |

---

## Testability patterns

### Pure-logic classes (the exemplar pattern)

The most important testability technique in this codebase: extract all decision-making
logic into a class that has no scene-tree dependencies, no node references, and no
side effects. The owning node drives it with plain data and applies the result.

Exemplars:

| Class | What it is | What the node does |
|-------|-----------|-------------------|
| `UmbralAI` | Pure state machine — takes positions + tick, returns `{state, move_dir, attack}` | `Umbral` caches the decision from the tick signal, applies gravity+movement in `_physics_process` |
| `SpawnSystem` | Pure planner — takes tick/positions/count/glow, returns `[{def, position}]` | `World` instantiates the returned creatures |
| `StepTimeline` | Pure arithmetic — `step_at(pos)`, `steps_crossed(prev, now)` | `SequencerCore` queries the timeline each frame |
| `IntensityModel` | Pure accumulator — `on_event(kind)`, `tick()`, `level()` | `MusicSystem` reads `level()` on every tick |

To test these, just construct them directly — no `add_child`, no scene tree:

```gdscript
var ai := UmbralAI.new(creature_def, rng)
var decision := ai.tick(self_pos, target_pos, tick_index)
assert_eq(decision["state"], &"chase")
```

### Stub and fake patterns

**FakeSession** (`test_command_router.gd`): extends `NetworkSession` and overrides
`is_active()`, `has_authority()`, `unique_id()` with plain flags. Lets router tests
force offline/host/client posture without opening a socket.

**FakeRouter** (`test_command_router.gd`): extends `CommandRouter` and overrides
`_send(method, args, peer)` to append to a `sent: Array` instead of calling `rpc`.
The whole routing protocol is tested by inspecting this array.

**FakeCodec** (`test_command_router.gd`): duck-typed `encode/decode/is_replicable`
implementation. Encodes to `{t: tag, valid: true/false}`; `is_replicable` is true when
the tag begins with `"repl"`. Lets router tests independently control what is/is not
replicable and what decodes cleanly.

**FakeVoxelTool** (used in `test_terrain_edit_service.gd`): a minimal stand-in for
the `VoxelTool` returned by `godot_voxel`. Records calls without touching voxel data.

**FakeSession / transport `_send` override** pattern applies broadly: whenever a class
has a thin `_send` or `_emit` method, override it in a subclass to capture calls
instead of transmitting them. This makes the class fully testable without real I/O.

### Determinism testing via WorldSeed

`WorldSeed` is tested exhaustively in `test_world_seed.gd`. When testing any system
that draws from a `WorldSeed` stream, construct two systems with the same seed and
assert they produce identical output:

```gdscript
func test_same_seed_yields_identical_decision_sequence() -> void:
    var a := UmbralAI.new(_def(), _rng(7))
    var b := UmbralAI.new(_def(), _rng(7))
    for tick in range(0, 200):
        var da: Dictionary = a.tick(Vector3.ZERO, far, tick)
        var db: Dictionary = b.tick(Vector3.ZERO, far, tick)
        assert_eq(da["state"], db["state"], "state diverged at tick %d" % tick)
```

The `IntensityModel` test goes further: it asserts that the source file contains no
`randf`, `randi`, `randomize`, `RandomNumberGenerator`, `Time.`, or `OS.get_ticks`
calls — a static guard against accidental nondeterminism.

### Two-instance network smoke test

The live ENet protocol cannot be meaningfully exercised in a headless unit test
(binding a real port requires two running processes). The smoke test lives in
`scripts/tools/net_smoke/` and is NOT part of the GUT suite. It boots two real
`world.tscn` instances on loopback (port 24571) and asserts the full replication path:

- `host_test.gd`: hosts, waits for a client to connect, submits a `DigCommand` via
  `router().submit(...)`, then prints `HOST_OK <log_size>` after 8 seconds.
- `client_test.gd`: joins, receives the host's `commit_command` broadcast (routed
  through the bus), and prints `CLIENT_GOT_DIG` when the first `DigCommand` arrives.

The unit tests in `test_command_router.gd` and `test_network_session.gd` cover the
offline contract and routing logic without a live peer. The smoke test covers the
actual wire (encode → transmit → decode → execute).

---

## CI pipeline anatomy

`.github/workflows/ci.yml` runs two parallel jobs on every push and PR:

### Job 1: `lint` (ubuntu-latest, ~15 min)

1. `actions/checkout@v4`
2. `actions/setup-python@v5` — Python 3.12
3. `pip install "gdtoolkit==4.*"`
4. Discover lint targets: `scripts/`, `tests/unit/`, `tests/integration/` — only dirs
   that contain `.gd` files are included (avoids errors on empty dirs).
5. `gdformat --check` — fails on any formatting diff; never writes.
6. `gdlint` — fails on any lint error.

### Job 2: `test` (ubuntu-latest, ~15 min)

1. `actions/checkout@v4`
2. Cache `~/godot-bin` keyed by `godot-voxel-v1.6-linuxbsd-x86_64`. Cache hit skips
   the download.
3. Download `godot.linuxbsd.editor.x86_64.zip` from the Zylann v1.6 release. The
   CI download script handles the same nested-zip pattern as `setup.sh` (loops
   until no more `*.zip` files remain).
4. Resolve the binary path: prefers a name matching `godot*linuxbsd*` or `*.x86_64`,
   falls back to any executable non-`.so` file.
5. `--headless --version` — prints the Godot version as a sanity check.
6. `--headless --path . --import` — asset import; `|| true` because import may exit
   non-zero when the display is absent, but the `.godot/` folder is written correctly.
7. `--headless --path . -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
   — runs the full GUT suite and exits non-zero on failure.

Both jobs run in parallel. Concurrency group `ci-<workflow>-<ref>` cancels in-progress
runs on the same branch when a new push arrives.
