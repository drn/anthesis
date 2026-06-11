# Contributing to Anthesis

Thanks for contributing. These rules are non-negotiable — they keep the codebase trustworthy and the architecture clean.

---

## Quick Rules

1. **Every change ships with tests.** No exceptions. If a behavior is worth adding, it is worth testing.
2. **CI must be green before merge.** Squash-merge only. No merge commits.
3. **Lint and format before pushing.** Run `make lint` and `make format`.
4. **Never modify `addons/`.** Vendored dependencies are read-only. Open an issue if you need a version bump.
5. **Architecture rules hold.** Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before making structural changes.

---

## Tests

We use [GUT 9.6.0](https://github.com/bitwes/Gut), vendored at `addons/gut/`.

```bash
make test         # run all tests, headless
```

Tests live in:
- `tests/unit/`       — pure logic, no scene tree required
- `tests/integration/` — scene-level, may require the engine loop

Every new script should have a corresponding test file. Every bug fix should add a regression test.

The headless test command (for reference):
```
<godot-binary> --headless --path . -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
```

In a fresh checkout, import assets before running tests:
```
<godot-binary> --headless --path . --import
```

---

## Lint and Format

Install gdtoolkit:
```bash
pip install gdtoolkit
```

Run:
```bash
make lint      # gdlint on all .gd files
make format    # gdformat on all .gd files (in-place)
```

Format enforces tabs (Godot convention). Do not configure your editor to use spaces for `.gd` files.

---

## GDScript Style

- **Indentation**: tabs, always.
- **Naming**: `snake_case` for variables, functions, files. `PascalCase` for class names.
- **Class docstrings**: every autoload, system, and non-trivial class gets a `## Description` block at the top.
- **No magic numbers**: named constants or resource properties.
- **No game logic in input handlers**: route mutations through the command layer (see Architecture).

---

## Architecture Rules

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The short version:

- All world mutations (dig, place, craft, damage) go through the **command/intent layer**. No exceptions. Input handlers call commands; they do not touch world data directly.
- World data and render mesh are strictly separated. The mesh is disposable.
- Randomness derives from **WorldSeed streams only** — no bare `randf()` or `randi()` in game logic.
- Items, recipes, blocks, flora, biomes, spells: `.tres` resources, not code.
- Systems are autonomous modules with injected dependencies — independently testable.

Violations of these rules will be caught in review and must be fixed before merge.

---

## Pull Request Checklist

- [ ] Tests added or updated
- [ ] `make lint` passes
- [ ] `make format` applied (no diff)
- [ ] Architecture rules respected
- [ ] PR description explains *why*, not just *what*
- [ ] Squash-ready (tidy commit history or single commit)

---

## Documentation Map

Start here and follow the chain for the depth you need:

| Doc | Audience / purpose |
|-----|--------------------|
| [README.md](README.md) | Project overview, status, gallery, controls |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Layer model, command/intent layer, all 7 phases, data-driven content, deterministic RNG, directory layout — read before any structural change |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Environment setup (nested-zip, `HOME` override), every `make` target, edit/run/test loop, screenshot-verification harness pattern, debugging tips |
| [docs/TESTING.md](docs/TESTING.md) | GUT conventions, full test-file index, testability patterns (pure-logic classes, fake/stub patterns, determinism testing), CI pipeline anatomy |
| [docs/COMMANDS.md](docs/COMMANDS.md) | Command/intent layer reference — every `WorldCommand` subclass, `CommandBus`, `WorldContext` fields |
| [CONTRIBUTING.md](CONTRIBUTING.md) | This file — quick rules, PR checklist, style guide |
| [AGENTS.md](AGENTS.md) | Orchestration notes for AI agents working in this repo |
| [CLAUDE.md](CLAUDE.md) | Claude Code / AI agent conventions and hard rules |

For per-system depth (magic, combat, sequencer, audio, networking), read the relevant
subsection in `docs/ARCHITECTURE.md`, then the corresponding test files listed in
`docs/TESTING.md`.

---

## Opening Issues

Bug reports and feature proposals welcome. For large changes, open an issue and discuss before writing code — it saves everyone time.
