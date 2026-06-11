# Music System

The adaptive music system layers five phase-locked WAV stems whose volumes crossfade in response to a game-intensity accumulator. The intensity signal is driven by gameplay events (combat, digging, casting) and proximity to Umbrals. All mixing is deterministic: same event sequence, same mix.

## Key Files

| File | Role |
|---|---|
| `scripts/core/audio/music_stem_def.gd` | `MusicStemDef` — resource schema (id, stream_path, thresholds) |
| `scripts/systems/audio/music_stem_registry.gd` | `MusicStemRegistry` — loads `resources/music/*.tres` |
| `scripts/systems/audio/intensity_model.gd` | `IntensityModel` — pure heat accumulator + per-tick decay |
| `scripts/systems/audio/music_system.gd` | `MusicSystem` — one `AudioStreamPlayer` per stem, volume slew |
| `resources/music/` | Five `.tres` stem definitions (pad, arp, bass, drums, shimmer) |
| `assets/audio/music/` | Generated WAV files (gitignored; run `make stems`) |
| `scripts/tools/generate_stems.py` | Procedural synthesizer — stdlib only, deterministic |
| `tests/unit/test_intensity_model.gd` | IntensityModel unit tests |
| `tests/unit/test_music_system.gd` | MusicSystem mapping + slew tests |
| `tests/unit/test_music_stem_registry.gd` | Registry scan tests |
| `tests/integration/test_world_music.gd` | Full-world music integration |

## Why Built-in Audio, Not FMOD

FMOD requires a native plugin that complicates the open-source build and the headless CI runner. Godot's built-in `AudioStreamPlayer` + manual volume math replicates the No Man's Sky stem/intensity model at zero dependency cost. The tradeoff is no built-in beat-sync or DSP graph — loop sync is achieved by starting all players in the same frame (`_start_in_sync`) and the sequencer locks to the playback position of `Stem_pad` as its transport.

## generate_stems.py

Located at `scripts/tools/generate_stems.py`. Run via `make stems` (`python3 scripts/tools/generate_stems.py`). Writes five WAV files to `assets/audio/music/`.

**Synthesis approach:**
- Stdlib only (`wave`, `math`, `struct`, `random`) — no audio libraries.
- Each stem gets its own `random.Random` seeded from `SEED + offset` (offset = insertion order in `STEMS`). Adding a new stem never changes any existing stem's bytes.
- All loops are exactly `N_FRAMES = round(44100 * 32 * 60.0 / 110)` = **769745 frames** (~17.45 s) at 44100 Hz, 16-bit mono. 32 beats = 8 bars of 4/4 at 110 BPM.
- `normalize(buf, -3.0 dBFS)`: DC removal then peak normalization.

**What each stem is:**

| Stem | Style | Key technique |
|---|---|---|
| `pad.wav` | Warm chord drone (Am-F-C-G) | Detuned saw+sine blend, 0.9 s attack, 1-pole lowpass at 900 Hz |
| `bass.wav` | Sub sine pulse on roots | Per-beat sidechain duck (0.35 → 1.0 gain over 85% of beat) |
| `arp.wav` | Plucky 16th-note arpeggio | 6-note pattern, 3/16 delay echo at 0.35 gain (wrapped, seamless) |
| `drums.wav` | Four-on-floor EDM groove | Pitch-drop kick (90→40 Hz), hi-pass noise hats, clap on 2 & 4 |
| `shimmer.wav` | High pentatonic sparkle | 70% chance plink per beat, 0.6–1.1 s tails, noise swell into bar 5 |

**Verify mode:**
```
python3 scripts/tools/generate_stems.py --verify
```
Prints per-file stats (frames, channels, bits, rate, peak dBFS, DC) and exits 0 if all files match the contract.

## MusicStemDef Thresholds

| Stem id | `always_on` | `threshold` | `full_at` | `base_db` |
|---|---|---|---|---|
| `pad` | true | 0.0 | 1.0 | -8.0 dB |
| `arp` | false | 0.10 | 0.30 | -9.0 dB |
| `bass` | false | 0.30 | 0.50 | -6.0 dB |
| `drums` | false | 0.50 | 0.70 | -5.0 dB |
| `shimmer` | false | 0.70 | 0.90 | -10.0 dB |

The `pad` is always audible at -8 dB regardless of intensity. At intensity 0 only the pad is heard. The full band (pad + arp + bass + drums + shimmer) is only reached at intensity >= 0.9.

## IntensityModel: Heat and Decay

`IntensityModel` (`RefCounted`) is pure — no engine dependencies.

**Heat added per event (`on_event(kind)`):**

| Event kind | Heat |
|---|---|
| `&"player_hurt"` | 0.45 |
| `&"combat_hit"` | 0.35 |
| `&"cast"` | 0.15 |
| `&"enemy_near"` | 0.12 |
| `&"dig"` | 0.06 |
| `&"harvest"` | 0.04 |

Heat is clamped to `[0.0, 1.0]` immediately. Unknown event kinds are ignored.

**Decay:** `tick()` subtracts `DECAY_PER_TICK` (0.012) per call. The simulation clock runs at ~10 Hz so the natural decay rate is ~0.12/s. A `player_hurt` event (0.45) decays back to zero in about 3.75 seconds with no further events. Decay happens only in `tick()`; `on_event` never decays.

**Event sources wired in `World._build_music()`:**

- `CommandBus.command_executed` → `DigCommand` → `&"dig"`, `CastCommand` → `&"cast"`, `HarvestCommand` → `&"harvest"`
- `CombatService.damage_applied` → player's instance id → `&"player_hurt"`, otherwise `&"combat_hit"`
- `SimulationClock.ticked` → `World._on_music_tick` → `&"enemy_near"` if any Umbral within `ENEMY_NEAR_DISTANCE` (12 m)

## MusicSystem: Sync and Slew

`MusicSystem` (`Node`) is wired via `setup(stems, model, clock)`:

1. Builds one `AudioStreamPlayer` per `MusicStemDef`, named `Stem_<id>`.
2. Force-sets `LOOP_FORWARD` on any WAV whose import didn't flag it; `loop_end` is derived from `data.size() / bytes_per_frame`.
3. Calls `player.play()` on all players in the same frame (`_start_in_sync()`).
4. Seeds initial volume at the level-0 target (no ramp from silence on boot).
5. Connects `clock.ticked` → `_on_tick` → `tick_volumes()`.

**volume_db_for(stem, level)** — pure static function:
- `always_on` → returns `base_db` unconditionally.
- `level <= threshold` → `SILENT_DB` (-60 dB).
- `level >= full_at` → `base_db`.
- Between: `lerpf(SILENT_DB, base_db, (level - threshold) / (full_at - threshold))`.

**Slew rate:** each tick, each player's `volume_db` moves at most `MAX_DB_PER_TICK` (4.0 dB) toward the current target. This prevents zipper noise on fast intensity changes. With a 60 dB gap (silent to full), a stem converges in ~15 ticks (~1.5 s).

`MusicSystem` is headless-safe: players are created and configured even with no audio device, so `players()` and `volume_db_for` work in tests.

## Adding a New Stem

1. Add a new synthesizer function to `generate_stems.py` following the `gen_pad` pattern (takes a `random.Random`, returns a `list` of `N_FRAMES` floats). Add it to the `STEMS` dict. Re-run `make stems`.
2. Create `resources/music/<stem_id>.tres` as a `MusicStemDef`. Set `id`, `stream_path` (`res://assets/audio/music/<stem_id>.wav`), `threshold`, `full_at`, `base_db`, and `always_on`.
3. `MusicStemRegistry` picks it up automatically on next boot (scans `res://resources/music/`).
4. `World._build_music()` passes `_stem_registry.stems()` to `MusicSystem.setup()` — no code change needed.
5. Add a test in `test_music_stem_resources.gd`: assert the new resource loads, has a non-empty `id`, and has valid threshold/full_at ordering.

## Testing Notes

- `test_intensity_model.gd`: heat accumulation, clamp to 1.0, decay rate, unknown event ignored.
- `test_music_system.gd`: `volume_db_for` mapping (silence, base, linear midpoint, always_on, degenerate window), player count matches stem count, all started playing, slew cap (single step ≤ 4 dB), convergence in 30 steps.
- Pattern for a new stem resource test: load by path, assert `id != ""`, assert `threshold <= full_at`, assert `base_db < 0`.

## Gotchas

- All stem WAVs must have the same frame count (`N_FRAMES = 769745`) for phase coherence. `generate_stems.py --verify` checks this.
- `_load_loop` returns `null` when the WAV file doesn't exist (assets not yet generated). The `AudioStreamPlayer` is still created, just streamless. Tests pass in this state — assert on `player.stream != null` only when you know assets are present.
- The sequencer uses `Stem_pad`'s `get_playback_position()` as its transport clock (`World.TRANSPORT_STEM_PLAYER = "Stem_pad"`). Renaming the pad stem will break sequencer sync.
- `IntensityModel.tick()` must be called at the simulation clock rate (not per render frame) for the decay math to hold. `MusicSystem.tick_volumes()` calls `_model.tick()` then slews — it must not be called more than once per simulation tick.
