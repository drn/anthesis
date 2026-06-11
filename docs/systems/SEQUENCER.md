# In-World Music Sequencer

The signature feature of Anthesis: the player crafts a Sequencer Core and places Note Blocks around it. Where you place a block around the core — its angle — determines which of the 16 beat steps it fires on. The spatial arrangement of crystals IS the rhythm. All timing is locked to the same 110 BPM grid as the adaptive soundtrack.

## Key Files

| File | Role |
|---|---|
| `scripts/systems/sequencer/step_timeline.gd` | `StepTimeline` — pure BPM/step math |
| `scripts/systems/sequencer/sector_math.gd` | `SectorMath` — angle→step mapping |
| `scripts/systems/sequencer/sequencer_core.gd` | `SequencerCore` — rotating prism, transport lock, block registry |
| `scripts/systems/sequencer/note_block.gd` | `NoteBlock` — placeable crystal, pitch bank, fire/flash |
| `scripts/systems/sequencer/block_placement_service.gd` | `BlockPlacementService` — inventory-gated spawn/remove |
| `scripts/core/commands/place_block_command.gd` | `PlaceBlockCommand` |
| `scripts/core/commands/remove_block_command.gd` | `RemoveBlockCommand` |
| `scripts/core/commands/cycle_note_command.gd` | `CycleNoteCommand` |
| `scripts/tools/generate_notes.py` | Procedural pluck synthesizer (8 notes) |
| `resources/items/note_block.tres` | ItemDef for the Note Block item |
| `resources/items/sequencer_core.tres` | ItemDef for the Sequencer Core item |
| `resources/recipes/note_block.tres` | Crafting recipe |
| `resources/recipes/sequencer_core.tres` | Crafting recipe |
| `assets/audio/notes/` | Generated pluck WAVs (gitignored; run `make notes`) |
| `tests/unit/test_step_timeline.gd` | StepTimeline unit tests |
| `tests/unit/test_sector_math.gd` | SectorMath unit tests |
| `tests/unit/test_sequencer_core.gd` | SequencerCore unit tests |
| `tests/unit/test_note_block.gd` | NoteBlock unit tests |
| `tests/unit/test_block_placement_service.gd` | BlockPlacementService unit tests |
| `tests/unit/test_block_commands.gd` | Command layer tests |
| `tests/integration/test_world_sequencer.gd` | Full-world sequencer integration |

## StepTimeline Math

`StepTimeline` (`RefCounted`) models a looping musical bar. Default construction: 110 BPM, 16 steps, subdivision 4 (= sixteenth notes in 4/4).

Key numbers at the defaults:

| Quantity | Formula | Value |
|---|---|---|
| Step duration | 60 / 110 / 4 | **~0.1364 s** (one sixteenth note) |
| Loop duration | 16 × 0.1364 | **~2.182 s** (one bar) |
| Playback position wraps at | `loop_duration()` | ~2.182 s |

`step_at(playback_s)` wraps the position into `[0, loop_duration)` with `fposmod`, floors to a step index, and clamps defensively. Result: 0–15.

`steps_crossed(prev_s, now_s)` returns the ordered list of steps whose boundaries were entered in the half-open interval `(prev_s, now_s]`. Handles three cases:
- Same step: empty list.
- Forward skip: every intermediate step in order.
- Wrap (`now_s < prev_s`): `delta += loop_duration` first, then the same boundary count.

This is what drives `SequencerCore._process` — every frame, the difference between last and current transport position yields the list of steps to fire.

## SectorMath: Angle to Step

`SectorMath.step_for_offset(offset, steps=16)` maps a `Vector3` offset (block position minus core position) to a step index 0–15.

The convention: **north (−Z) = step 0**, **clockwise increasing** (east / +X = step 4, south / +Z = step 8, west / −X = step 12).

Implementation:
```gdscript
var angle := atan2(offset.x, -offset.z)   # north=0, east=+PI/2
angle = wrapf(angle, 0.0, TAU)             # normalise to [0, TAU)
var sector := TAU / count                  # 2*PI/16 = PI/8 radians per step
var index := int(round(angle / sector)) % count  # round to nearest centre
```

`round` (not `floor`) is used deliberately so a block exactly on a boundary snaps to the nearest sector centre rather than flickering between two steps.

Y is ignored entirely — height doesn't affect which step a block plays.

## SequencerCore: Transport Lock and Block Registry

`SequencerCore` (`Node3D`) is the rotating glowing prism the player crafts and places.

**Internal state:**
- `_timeline`: `StepTimeline.new(110.0, 16, 4)` — always at the canonical tempo.
- `_playback_pos`: `Callable` returning the current transport position in seconds. Supplied by `World._transport_position()`, which reads `Stem_pad`'s `get_playback_position()`.
- `_registry`: `Dictionary` of `step_index -> Array[Node]`.
- `_markers`: 16 `MeshInstance3D` nodes arranged in a ring of radius `RING_RADIUS` (1.2 m) at `RING_HEIGHT` (0.0). Each has its own `StandardMaterial3D` instance so it brightens independently.

**`_process(delta)` each frame:**
1. `rotate_y(SPIN_SPEED * delta)` — `SPIN_SPEED = 0.6` rad/s.
2. `_decay_markers(delta)` — emission energy decays toward `MARKER_DIM` (0.4) at `MARKER_DECAY` (14.0) energy/s.
3. If `_playback_pos` is valid, call it to get `now`. On the first valid sample, seed `_last_pos` and light the current step without firing. On subsequent frames, call `steps_crossed(_last_pos, now)` and `_advance_to(step)` for each.

**`_advance_to(step)`:** brightens the marker to `MARKER_BRIGHT` (6.0), iterates the step's block bucket and calls `block.fire()` on each live block, prunes freed blocks, emits `step_advanced(step)`.

**`register_block(block)`:** computes `SectorMath.step_for_offset(block.global_position - global_position, 16)`, appends block to that step bucket, sets `block.assigned_step` if the property exists.

**`unregister_block(block)`:** scans all buckets, erases the block, prunes empty buckets.

**GROUP constant:** `&"sequencer_cores"`. All cores join this group so `BlockPlacementService` can iterate them.

## NoteBlock: Pitch Bank and Colors

`NoteBlock` (`Node3D`) is a small placeable crystal.

**Pitch bank:** static `_bank: Array[AudioStream]` loaded once from `res://assets/audio/notes/pluck_0.wav` through `pluck_7.wav`. The `_ensure_bank_loaded()` guard means the disk hit happens only on the first instance in a session.

**8 pitches** (A-minor pentatonic, ascending over two octaves):

| `pitch_index` | Note | Frequency |
|---|---|---|
| 0 | A3 | 220.00 Hz |
| 1 | C4 | 261.63 Hz |
| 2 | D4 | 293.66 Hz |
| 3 | E4 | 329.63 Hz |
| 4 | G4 | 392.00 Hz |
| 5 | A4 | 440.00 Hz |
| 6 | C5 | 523.25 Hz |
| 7 | E5 | 659.26 Hz |

**Color gradient:** `pitch_index = 0` → cyan `(0.1, 0.9, 1.0)`, `pitch_index = 7` → magenta `(1.0, 0.15, 0.9)`, lerped linearly. Stored as per-instance `StandardMaterial3D` (duplicated from scene resource in `_resolve_material()` so instances are independent).

**`fire()`:** plays the current pluck note via `AudioStreamPlayer3D`, then tweens emission_energy_multiplier up to `_base_energy * 3.0` and back, and pops the crystal scale to 1.25 and back.

**`cycle_pitch()`:** increments `pitch_index` mod `PITCH_COUNT` (8), then calls `fire()` as a preview.

**`assigned_step`:** set by `SequencerCore.register_block`. Defaults to -1 (dormant, no core in range).

GROUP: `&"note_blocks"`.

## BlockPlacementService

`BlockPlacementService` (`RefCounted`) is the inventory-gated spawn/remove seam.
As of Phase 9 it also handles `&"storm_catcher"` placement — it is no longer
sequencer-only.

**Construction:**
```gdscript
BlockPlacementService.new(inventory, container_provider, core_lookup)
```
- `container_provider`: Callable returning the `Blocks` `Node3D`.
- `core_lookup`: Callable from `Vector3` → nearest `SequencerCore` within `RADIUS` (10.0 m), or null.

**`place(item_id, position) -> bool`:**
1. Resolves (and caches) the `PackedScene` from `_SCENE_PATHS`.
2. Removes one `item_id` from inventory — refuses if unavailable.
3. Instantiates the scene, snaps to the `GRID` (0.5 m) grid with `snappedf`.
4. Names the node `"Block_%d" % _spawn_counter` and increments `_spawn_counter`.
5. Adds to the container.
6. For `&"note_block"`: binds to nearest core via `_bind_note_to_core`. For
   `&"sequencer_core"`: adopts all dormant Note Blocks within RADIUS via
   `_adopt_dormant_notes`. For `&"storm_catcher"`: no sequencer binding — placed
   as-is, joining `&"storm_catchers"` group in its own `_ready`.
7. Emits `block_placed`.

**Deterministic names:** `Block_0`, `Block_1`, ... The counter increments monotonically per successful place. Late-join replay reproduces identical names because placements replay in the same order they were committed. Use `spawn_count()` to confirm two peers are in sync.

**`remove(block) -> StringName`:**
Identifies the item from the block's group, unregisters it from cores (for Note
Blocks) or releases its blocks to dormant (for Sequencer Core), frees it via
`queue_free()`, returns the item id for the caller to refund. For `&"storm_catcher"`
the refund is simply the item id — no sequencer cleanup needed. Note: `queue_free`
is deferred; tests must `await get_tree().process_frame` before asserting block
count. `RemoveBlockCommand` handles the inventory refund side.

## The Three Block Commands

| Command | Args | Effect |
|---|---|---|
| `PlaceBlockCommand` | `item_id: StringName, position: Vector3` | Routes to `ctx.block_place.place(...)` |
| `RemoveBlockCommand` | `target: Node` | Routes to `ctx.block_place.remove(...)`, refunds item to inventory |
| `CycleNoteCommand` | `target: Node` | Calls `target.cycle_pitch()` if target is in group `&"note_blocks"` |

All three replicate over the network via `CommandCodec` (see [MULTIPLAYER.md](MULTIPLAYER.md)).

## generate_notes.py

Located at `scripts/tools/generate_notes.py`. Run via `make notes`. Writes `assets/audio/notes/pluck_0.wav` through `pluck_7.wav`.

Each pluck is ~0.55 s, mono 16-bit 44100 Hz, peaks at -6 dBFS. Synthesis: saw+sine blend through a one-pole lowpass whose cutoff sweeps down from `freq * 8` Hz over 0.12 s (bright attack → mellow tail), exponential amplitude decay (`decay_tau = 0.18 s`), plus a tiny detuned shimmer partial at `freq * 2.004` for a glassy tail.

Each note gets its own `random.Random(SEED + idx)` stream so pitches are independent. Verify:
```
python3 scripts/tools/generate_notes.py --verify
```

## Composing: Player-Facing Guide

Place a Sequencer Core (craftable: requires some crystal shards). The core begins rotating and its 16 tiny sphere markers trace the loop. Place Note Blocks around the core — each block's angular position from the core's centre picks which of the 16 sixteenth-note steps it fires. The block closest to due north fires on beat 1 (step 0); rotate clockwise to reach later steps (east = step 4, south = step 8, west = step 12). Interact with a block (E) to cycle its pitch through 8 notes of the A-minor pentatonic scale — the crystal colour shifts from cyan (low) to magenta (high). Remove blocks with F. The timing locks to the soundtrack's 110 BPM so your layout becomes a rhythm that rides the music.

## Extending: Adding New Block Types

1. Create a new scene with a root `Node3D` that:
   - Calls `add_to_group(&"<my_group>")` in `_ready()`.
   - Exposes a `fire()` method (called when the step fires).
   - Exposes an `assigned_step: int` property (set to -1 initially; `SequencerCore.register_block` writes the resolved step).
2. Add the scene path to `BlockPlacementService._SCENE_PATHS`.
3. Add group constants to `BlockPlacementService.GROUP_CORE` / `GROUP_NOTE` (or add a new group alongside them) and update `_item_id_for`.
4. Add a new `ItemDef` resource and a recipe resource.
5. Add a `CommandCodec` wire branch if the block command must replicate.
6. Write tests: `test_block_placement_service.gd` shows how to stub the container and core_lookup callables.

## Testing Notes

- `test_step_timeline.gd`: step_at wrap-around, steps_crossed forward/same/wrap cases, degenerate BPM/steps guards.
- `test_sector_math.gd`: north=0, clockwise cardinal steps, boundary rounding, Y ignored.
- `test_sequencer_core.gd`: register/unregister, step_advanced signal, freed blocks pruned, no spurious fire on first sample.
- `test_block_placement_service.gd`: inventory gate (refuses on empty), grid snap, deterministic naming, dormant adoption, dormant release on core remove.
- `test_block_commands.gd`: PlaceBlockCommand, RemoveBlockCommand, CycleNoteCommand (ignores non-note-blocks).

## Gotchas

- `SequencerCore.setup(playback_pos)` must be called after the core is added to the tree. `World._on_block_placed` handles this via `_lock_new_cores_to_transport()`.
- The first `_process` sample sets `_last_pos` and fires nothing — this prevents a burst of all 16 steps on the first frame.
- `SectorMath.step_for_offset` uses the block's `global_position` at registration time. Moving a block after registration does not change its step. Remove and re-place to reassign.
- `NoteBlock._bank` is static — all instances share one loaded bank. The bank is never cleared. If you need to reload assets (e.g. after `make notes` while the editor is running), restart the editor.
- The `GRID = 0.5` snap means you cannot place two blocks at the exact same position — useful for debugging grid alignment issues.
