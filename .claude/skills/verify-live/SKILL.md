---
name: verify-live
description: 'Run Anthesis windowed with a SceneTree harness script to verify a change live: drive gameplay via command bus, capture screenshots, check for script errors. Use when asked to verify a change works in the real game, take screenshots, or test gameplay end-to-end.'
---

# verify-live — drive the real game and prove a change works

GUT tests assert wiring; this skill proves *behavior* by booting the actual
`world.tscn`, driving gameplay through the same command path the player uses,
and capturing PNG screenshots. Use it after a feature lands to confirm it works
in the live game, and to produce media for the PR.

## The harness shape

A `SceneTree` script (run with `-s`) is the verification unit. It is **not** part
of the GUT suite — it boots the world, advances frames, drives intents, snaps a
PNG, and quits. Mirror the proven pattern in `scripts/tools/net_smoke/host_test.gd`.

The binary, HOME prefix, and path are fixed:

```bash
HOME=/tmp/anthesis-home tools/godot/macos_editor.app/Contents/MacOS/Godot \
  --path . -s res://scripts/tools/verify/<name>.gd
```

- **`HOME=/tmp/anthesis-home`** — every Godot invocation in this repo overrides
  HOME so the editor's user data / config never touches the real `~`. Always
  prefix it. Use the same value the GUT suite uses.
- **Windowed (no `--headless`)** — terrain meshing and `get_texture()` need a
  real rendering context to produce a non-black screenshot. Headless boots but
  the framebuffer is empty and terrain collision never streams.
- **`-s <script>`** runs the script as a `SceneTree` `MainLoop`. Put harness
  scripts under `scripts/tools/verify/` (a sibling of `net_smoke/`, also outside
  the GUT suite — GUT only scans `tests/`).
- **`--import` first** if you touched any `.tres` / asset: a fresh worktree has
  no `.godot/imported/` cache. Run `HOME=/tmp/anthesis-home <binary> --headless
  --path . --import` once (or `make import`) before the windowed run.

## Harness template

```gdscript
# scripts/tools/verify/<name>.gd — SceneTree harness, NOT a GUT test.
extends SceneTree

const WORLD_SCENE := "res://scenes/world/world.tscn"

var _world: World
var _frame := 0
var _had_error := false


func _initialize() -> void:
	_world = load(WORLD_SCENE).instantiate()
	root.add_child(_world)


# Returning true quits the loop. Drive actions on specific frame marks: terrain
# streams in asynchronously, so wait ~120 frames before expecting height_at() to
# be non-NAN and the player to have dropped onto the surface.
func _process(_delta: float) -> bool:
	_frame += 1

	if _frame == 120:
		# --- drive gameplay here (see scenarios below) ---
		_world.command_bus().execute(DigCommand.new(Vector3.ZERO, 2.0))

	if _frame == 240:
		_snap("res://artifacts/verify-<name>.png")
		print("VERIFY_OK frame=%d" % _frame)
		return true
	return false


func _snap(path: String) -> void:
	var img := root.get_texture().get_image()
	# res:// is read-only at runtime; write under user:// and copy, or write an
	# absolute OS path. Simplest: ProjectSettings.globalize_path on a res:// dir
	# that exists, or just save to user:// and read it back from the harness log.
	var abs := ProjectSettings.globalize_path(path)
	var err := img.save_png(abs)
	print("SNAP %s err=%d" % [abs, err])
```

Notes on the snapshot:
- `root.get_texture().get_image()` returns the current frame's framebuffer as an
  `Image`. Call it from `_process` after the frame you want has rendered.
- `Image.save_png(path)` wants a writable filesystem path. `res://` is read-only
  in a run; use `ProjectSettings.globalize_path("res://artifacts/...")` (create
  the `artifacts/` dir first) or `user://`. Then read the PNG back with the
  Read tool by its absolute OS path.
- **Register artifacts.** Screenshots you produce for a PR or for the caller
  should be registered as artifacts (via `artifact_register`) so the
  orchestrator surfaces them — don't leave them only in `/tmp`.

## Catching script errors

A windowed run prints GDScript errors to stderr but exits 0 anyway. To fail
loud, capture stderr and grep:

```bash
HOME=/tmp/anthesis-home tools/godot/macos_editor.app/Contents/MacOS/Godot \
  --path . -s res://scripts/tools/verify/<name>.gd 2>&1 | tee /tmp/verify.log
grep -E "SCRIPT ERROR|Parse Error|Cannot call|Invalid (get|call)" /tmp/verify.log \
  && echo "FAILED" || echo "CLEAN"
```

Print a unique `VERIFY_OK` / `VERIFY_FAIL <reason>` line from the harness and
assert on it — same convention as `HOST_OK` in the net smoke test.

## Driving gameplay — `World` introspection surface

Everything you need to drive and inspect a live world is exposed on the `World`
node (see `scripts/systems/world/world.gd`). The command path is the contract:
**drive mutations through `world.command_bus().execute(...)`** (or
`world.router().submit(...)` for the authority-aware path), never by poking
nodes. The full getter surface:

| Getter | Returns | Use for |
|--------|---------|---------|
| `command_bus()` | `CommandBus` | execute any `WorldCommand` directly (solo path) |
| `router()` | `CommandRouter` | authority-aware submit (use in session scenarios) |
| `voxel_world()` | `VoxelWorld` | `height_at(Vector2)`, `voxel_tool()` |
| `player()` | `Player` | read `global_position`, `velocity` |
| `flora()` | `FloraScatter` | inspect scattered props (children) |
| `inventory()` | `Inventory` | assert on item counts after harvest/craft |
| `registry()` | `ItemRegistry` | resolve `item(id)` / `recipe(id)` |
| `hud()` | `Hud` | presentation; `show_hint`, bars |
| `lumen_well()` | `LumenWell` | `current()`, `capacity()`, `add(amount)` |
| `magic()` | `MagicSystem` | `can_cast`, `cooldown_remaining` |
| `combat()` | `CombatService` | `health_of(id)`, `node_of(id)`, `apply_damage` |
| `player_health()` | `Health` | player HP pool (owned by World, not Player) |
| `creatures()` | `CreatureRegistry` | resolve creature defs for spawns |
| `music()` | `MusicSystem` | `players()` (stem `AudioStreamPlayer`s) |
| `intensity()` | `IntensityModel` | read the soundtrack heat signal |
| `blocks_container()` | `Node3D` | placed sequencer blocks (children) |
| `block_place()` | `BlockPlacementService` | inventory-gated block spawn/remove |
| `session()` | `NetworkSession` | `host()`, `join()`, `has_authority()` |
| `command_log()` | `CommandLog` | `size()`, `entries()` for replay assertions |

There is **no** public getter for the `SimulationClock`; it is a named child —
`world.get_node("SimulationClock")` — gating it under the World public-method
cap (see Gotchas in CLAUDE.md). Ticks fire from its `_process`, so they only
advance in a windowed/real run, not when you instantiate World bare.

## Common scenarios (drop into `_process` at a frame mark)

**Dig a crater** (Phase 1). Wait for terrain to stream first.
```gdscript
if _frame == 120 and not is_nan(_world.voxel_world().height_at(Vector2.ZERO)):
	_world.command_bus().execute(DigCommand.new(_world.player().global_position, 3.0))
```

**Cast an ability** (Phase 3). Casts route through `CastCommand`; cost/cooldown
are enforced inside the rule gate. Pre-load the well so the cast succeeds.
```gdscript
var ability := AbilityRegistry.new().ability(&"shape_burst")
_world.lumen_well().add(50.0)  # ensure affordable
_world.command_bus().execute(CastCommand.new(ability, _world.player().global_position))
# verify: well.current() dropped by ability.lumen_cost
```

**Spawn an Umbral** (Phase 4). Spawning is host-authority and tick-driven, so in
a windowed run Umbrals condense on their own once the player is placed. To force
one for a screenshot, damage path is the cleanest assertion:
```gdscript
# after a tick has spawned one, find it and strike it through the command path:
for child in _world.get_node("Umbrals").get_children():
	if child is Umbral:
		_world.command_bus().execute(DamageCommand.new(child.get_instance_id(), 12.0, Vector3.UP * 2.0))
		break
```

**Place sequencer blocks** (Phase 6). Block placement is inventory-gated — grant
the items first, then place a Core, then a Note Block near it.
```gdscript
_world.inventory().add(&"sequencer_core", 1)
_world.inventory().add(&"note_block", 4)
var p := _world.player().global_position
_world.command_bus().execute(PlaceBlockCommand.new(&"sequencer_core", p + Vector3(2, 0, 0)))
_world.command_bus().execute(PlaceBlockCommand.new(&"note_block", p + Vector3(3, 0, 0)))
# verify: _world.blocks_container().get_child_count() == 2
```

**Host a session** (Phase 7). Solo already reports `has_authority() == true`, so
the command path is identical. To verify the session lifecycle live:
```gdscript
if _frame == 60:
	_world.session().host()  # opens server on DEFAULT_PORT (24565)
if _frame == 120:
	# committing through the router now logs to command_log for late-join replay
	_world.router().submit(DigCommand.new(Vector3.ZERO, 2.0))
if _frame == 180:
	print("LOG_SIZE %d" % _world.command_log().size())  # expect >= 1
```
For a true two-instance check, run the existing `scripts/tools/net_smoke/`
host/client pair (host first, then client on loopback) — see the header of
`host_test.gd` for the exact two-process invocation.

## Gotchas

- **Terrain is async.** `height_at()` returns `NAN` until the chunk under the
  player streams in (~1-2s windowed). Gate every position-dependent action on
  `not is_nan(height_at(Vector2.ZERO))` or a generous frame count. World itself
  parks the player at `PLAYER_SAFE_ALTITUDE` (220m) until terrain is ready.
- **Headless = black screenshot.** `get_texture().get_image()` under
  `--headless` is empty/black and terrain collision never streams. Always run
  windowed for visual verification.
- **`res://` is read-only at runtime.** Save PNGs via
  `ProjectSettings.globalize_path(...)` to a real dir, or `user://`.
- **Forgot `--import`.** A fresh worktree errors on missing `.import` files /
  black props. Run `make import` once.
- **Always prefix `HOME=/tmp/anthesis-home`** or the run pollutes the real home.

## Related

- `scripts/tools/net_smoke/host_test.gd` — the canonical SceneTree harness.
- `tests/integration/test_world_boot.gd` — the wiring assertions GUT covers.
- `docs/COMMANDS.md` — the command layer you drive through.
- `.claude/skills/new-phase/SKILL.md` — where live verification fits in a phase.
