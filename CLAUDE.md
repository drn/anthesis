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
scenes/              Godot scene files (.tscn)
scripts/core/        Engine-level systems (world, voxels, commands)
scripts/systems/     Gameplay systems (magic, crafting, flora, biomes)
scripts/ui/          UI scripts
resources/           Data resources (.tres) — items, recipes, flora, biomes
shaders/             GLSL / Godot shaders
assets/              Art, audio, fonts (binary, gitignored if large)
tests/unit/          GUT unit tests
tests/integration/   GUT integration tests
addons/              Vendored (GUT, godot_voxel) — DO NOT MODIFY
docs/                Design docs and architecture
tools/               Local binaries (gitignored)
scripts/             Shell scripts (setup.sh, etc.) + GDScript subdirs
```

---

## Orchestration Notes

Argus orchestrates dynamic multi-agent workflows for this repo:

- **Fable** — top-level orchestrator; coordinates agents and workflows.
- **Opus sub-agents** — complex / novel work: shaders, terrain algorithms, voxel simulation, novel systems design.
- **Sonnet sub-agents** — mechanical work: boilerplate, data authoring (.tres), documentation, test scaffolding.

See also: `CONTRIBUTING.md`
