# Anthesis — Development Guide

This guide covers environment setup, every `make` target, the edit/run/test loop, headless scripting for verification, and debugging tips.

---

## Environment Setup

### Prerequisites

- macOS (Apple Silicon or Intel) or Linux x86_64
- `curl`, `unzip` (macOS: already present; Linux: install via package manager)
- Python 3.x with `pip` (for gdtoolkit and asset generation)

### Download the Godot+voxel editor

```bash
make setup
```

`scripts/setup.sh` downloads the Zylann `godot_voxel` v1.6 prebuilt editor from
`https://github.com/Zylann/godot_voxel/releases/download/v1.6/`.

**Nested-zip note (macOS):** The macOS asset (`godot.macos.editor.app.zip`) contains a
second `macos_editor.app.zip` inside it. `setup.sh` handles this automatically: it
extracts the outer zip, locates the inner `*.zip`, and extracts that into
`tools/godot/`. The final binary lands at:

```
tools/godot/macos_editor.app/Contents/MacOS/Godot
```

On Linux x86_64 the asset (`godot.linuxbsd.editor.x86_64.zip`) extracts a single
binary directly into `tools/godot/`.

The `GODOT` Makefile variable defaults to the macOS path. Override it for a local
installation:

```bash
GODOT=/path/to/your/Godot make test
```

Set `FORCE=1` to re-download even when the binary is already present:

```bash
FORCE=1 make setup
```

### Install gdtoolkit

```bash
pip install "gdtoolkit==4.*"
```

This installs `gdlint` and `gdformat`. CI pins `gdtoolkit==4.*` and uses the same
`pip install` step.

---

## HOME override for sandboxed/headless agents

Godot writes editor caches, import data, and the project's `.godot/` folder relative
to `HOME`. In sandboxed CI or isolated agent environments, override `HOME` before any
Godot invocation to keep caches out of the user's home directory and avoid stale-cache
failures between runs:

```bash
export HOME=/tmp/anthesis-home
```

The net-smoke scripts in `scripts/tools/net_smoke/` include this in their header
comments. The GUT test suite in CI does not need it explicitly (each CI job gets a
clean runner), but local agents running headless must set it.

---

## Make targets

| Target | What it does |
|--------|-------------|
| `make setup` | Download Godot+voxel prebuilt; idempotent |
| `make edit` | Open the Godot editor (background process) |
| `make run` | Run the game interactively |
| `make import` | Headless asset import (required before first test run on a fresh checkout) |
| `make test` | Run `make import` then the full GUT suite headlessly |
| `make lint` | `gdlint` on all `*.gd` files under `scripts/` and `tests/` |
| `make format` | `gdformat` on all `*.gd` files in-place |
| `make format-check` | `gdformat --check` — no writes, CI-safe |
| `make stems` | Regenerate adaptive-music WAVs via `scripts/tools/generate_stems.py` |
| `make notes` | Regenerate sequencer note-bank WAVs via `scripts/tools/generate_notes.py` |

Lint and format scan `scripts/` and `tests/` only. `addons/` is vendored and
excluded.

The stem/note generators are stdlib-only Python (no external packages) and are
deterministic (fixed seed, no wall-clock), so re-running them produces byte-identical
WAVs.

---

## Edit / run / test loop

1. `make edit` — opens the Godot editor; edit scenes and scripts there.
2. `make run` — launches the game directly (no editor, interactive window).
3. `make test` — runs the full GUT suite headlessly and exits non-zero on failure.

For a tighter loop during test-driven work:

```bash
make test 2>&1 | tail -30
```

GUT exits with a non-zero code when any test fails. The tail of the output shows the
summary line (`X passed, Y failed`).

---

## Screenshot / headless verification harness

For visual verification of world changes, drive the game headlessly with a
`SceneTree` script that boots `world.tscn`, applies commands through the
`CommandBus`, and saves a viewport PNG.

Below is a complete, copy-pasteable example that boots the world, submits a
`DigCommand` through the command bus, waits two seconds for terrain to stream, and
saves a screenshot:

```gdscript
# scripts/tools/verify_dig.gd
extends SceneTree

const WORLD_SCENE := "res://scenes/world/world.tscn"
const OUT_PATH := "/tmp/verify_dig.png"
const WAIT_SECONDS := 2.0

var _world: World
var _elapsed := 0.0
var _done := false


func _initialize() -> void:
    _world = load(WORLD_SCENE).instantiate()
    root.add_child(_world)


func _process(delta: float) -> bool:
    _elapsed += delta
    if not _done and _elapsed >= WAIT_SECONDS:
        _done = true
        # Route a dig through the command bus (world-mutation rule applies).
        _world.command_bus().execute(DigCommand.new(Vector3(0, 0, 0), 3.0))
        # Capture the viewport.
        var img := root.get_texture().get_image()
        img.save_png(OUT_PATH)
        print("SCREENSHOT_SAVED %s" % OUT_PATH)
        quit(0)
        return true
    return false
```

Invoke it:

```bash
export HOME=/tmp/anthesis-home
GODOT="tools/godot/macos_editor.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . -s res://scripts/tools/verify_dig.gd
```

Key patterns:
- Extend `SceneTree`, not `Node`. The `_process(delta) -> bool` override drives the
  loop; return `true` to stop.
- Add world to `root`, not to a scene that does not exist yet.
- Route mutations through `command_bus().execute(...)` or `router().submit(...)`, never
  directly.
- Use `_elapsed` accumulation for timing; never `sleep`.
- See `scripts/tools/net_smoke/host_test.gd` and `client_test.gd` for the two-instance
  variant of this pattern.

---

## Debugging tips

### Headless renderer noise (benign)

Running headless emits several warning lines that are expected and harmless:

```
WARNING: ...RenderingDevice...  (Metal/Vulkan not available headless)
ERROR: Can't open display.
```

These do not affect test correctness. GUT still runs, and all assertions fire.

### `--import` when class_name cache is stale

After adding a new `class_name` to a GDScript file (or after a fresh checkout),
Godot's class cache may be out of date. Symptoms: `Identifier "MyNewClass" not found`.
Fix:

```bash
make import
# or directly:
tools/godot/macos_editor.app/Contents/MacOS/Godot --headless --path . --import
```

`make test` always runs `make import` first, so CI never hits this.

### gdlint quirks

`gdlint` enforces several rules that catch contributors off guard:

- **Signals first.** Signal declarations must appear before `var` declarations at the
  top of the class. If `gdlint` reports "signal should be declared before members",
  move `signal` lines above all `var` lines.
- **20 public-method cap.** A class may not expose more than 20 public methods. Add an
  underscore prefix to any method that is implementation-internal (e.g., `_apply`,
  `_do_thing`). `World` is near this cap — check before adding new public methods.
- **int64 literals.** Very large integer literals (> 2^31) must be written in hex or
  cast explicitly; bare large decimal literals trigger a lint warning.
- **Callable lifetime.** A `Callable` created from a lambda (`func(): ...`) is not
  automatically kept alive. Assign it to a variable or member before passing it, or
  gdlint may flag it.

Run `make lint` before pushing. CI runs `gdformat --check` (no writes) and `gdlint`
as the first job.

### Terrain edits no-op headless ("Area not editable")

`godot_voxel` streams chunks asynchronously. In a headless run chunks near the player
do not stream in unless the engine loop runs long enough. A `DigCommand` or
`PlaceCommand` that targets an un-streamed chunk emits `Area not editable` and
no-ops silently. This is expected in integration tests and smoke scripts that run for
only a few seconds. The replication path (command routing, logging, broadcast) still
exercises correctly — the net-smoke scripts assert this explicitly.

### Two-instance net smoke test

The live replication smoke test is not in the GUT suite; it needs two real Godot
processes:

```bash
export HOME=/tmp/anthesis-home
GODOT="tools/godot/macos_editor.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . -s res://scripts/tools/net_smoke/host_test.gd &
sleep 1
"$GODOT" --headless --path . -s res://scripts/tools/net_smoke/client_test.gd
```

Success: host prints `HOST_OK <log_size>` (log size >= 1), client prints
`CLIENT_GOT_DIG`. Port 24571 is used (differs from the game default 24565 to avoid
conflicts). See the header comments in each script for details.
