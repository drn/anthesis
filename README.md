# Anthesis

A cosmic-whimsical open-source voxel adventure game — smooth diggable terrain, Sanderson-inspired magic, deep crafting, and EDM-driven adaptive music.

> **Status: Pre-alpha.** Phase 0 (foundation) is done. Phase 1 (the beautiful diggable cosmic world) is in progress. Nothing is playable yet.

---

## Vision

### 1. Beautiful Living Cosmic World
Bioluminescent flora, nebula skies, volumetric fog, real-time global illumination. The world is a place you want to inhabit before you ever swing a pickaxe.

### 2. Dig and Build
Fully smooth, continuous SDF terrain — not blocky cubes. Every surface is diggable. Caves, tunnels, arches, and overhangs emerge naturally. What you remove stays removed.

### 3. Magic and Crafting
A hard-magic system (Sanderson rules: defined costs, defined limits). Spells and crafting recipes are data-driven resources — moddable, composable, and emergent. Discovering the rule set is part of the game.

### 4. Music as a Pillar
The soundtrack is generative and adaptive, not looping background tracks. Long-term goal: an in-world music sequencer that lets players compose and play instruments as a first-class game mechanic, blurring the line between game and instrument.

### 5. Adventure and Combat
Exploration-first. Combat serves the world, not the other way around. Creatures, factions, and ruins that reward curiosity.

---

## Status

| Phase | Description | State |
|-------|-------------|-------|
| 0 — Foundation | Engine setup, voxel module, CI, project structure, test harness | Done |
| 1 — The World | Smooth SDF terrain, biomes, bioluminescent flora, sky/fog/lighting | **In progress** |
| 2 — Systems | Crafting, inventory, magic propagation, tick simulation | Not started |
| 3 — Audio | Adaptive music engine, FMOD integration | Not started |
| 4 — Combat & Story | Creatures, abilities, ruins, narrative hooks | Not started |

---

## Tech

- **Engine**: Godot 4.6 (custom build) + [godot_voxel v1.6](https://github.com/Zylann/godot_voxel) — smooth Transvoxel/SDF meshing
- **Renderer**: Forward+ (Metal on macOS, Vulkan elsewhere)
- **Language**: GDScript (tabs, snake_case, data-driven .tres resources)
- **Testing**: GUT 9.6.0 (vendored at `addons/gut/`), headless CI
- **Lint / format**: gdtoolkit 4.x (`gdformat`, `gdlint`)
- **Audio**: FMOD planned (not yet integrated)
- **Platform**: macOS (primary dev), Linux (CI)

Architecture overview: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## Getting Started

**Prerequisites**: macOS or Linux, `git`, `make`, Python 3 (for gdtoolkit).

```bash
# 1. Clone
git clone https://github.com/drn/anthesis.git
cd anthesis

# 2. Fetch the prebuilt Godot + Voxel editor binary
scripts/setup.sh

# 3. Open the project in the editor
make edit

# 4. Run tests (headless)
make test

# 5. Launch the game (once there is something to run)
make run
```

The editor binary lands at `tools/godot/macos_editor.app` (gitignored).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide.

Short version: every change ships with tests, lint passes, squash-merge only.

---

## License

MIT — see [LICENSE](LICENSE).
