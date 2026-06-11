# Agents

See CLAUDE.md for the full AI build conventions, tech stack, and architecture.

## Hard Rules (inlined)

1. **Tests required.** Every change ships with GUT tests. Run `make test` before declaring done. All tests must pass.
2. **Never touch `addons/`.** Vendored tree — do not modify, move, or delete anything under it.
3. **No secrets, no tools/.** Never commit credentials, tokens, `.env` files, or anything under `tools/`.
4. **Command layer for world mutations.** All voxel/world writes must go through the command/intent layer. No direct mutations from presentation or render code.
5. **Data as resources, not code.** Items, recipes, flora, and biomes live in `resources/` as `.tres` files — not GDScript constants.
6. **Deterministic RNG.** Use seeded `WorldSeed` streams. Never call `randf()` / `randi()` directly in game logic.
7. **GDScript style.** Tabs for indentation, `snake_case` names, `PascalCase` classes.
8. **Squash-merge only.** PRs land as a single squash commit onto `master`.

## Docs Map

- `docs/ARCHITECTURE.md` — layer model + per-phase subsections (read before structural changes).
- `docs/COMMANDS.md` — the command/intent layer all world mutations route through.
- `docs/systems/*.md` — per-system deep dives (extend-this-system guides).
- `CLAUDE.md` — full conventions, content cookbook, known gotchas.

## Verification

Repo skills under `.claude/skills/`: **`verify-live`** (boot `world.tscn`
windowed, drive gameplay via `world.command_bus().execute(...)`, screenshot) and
**`new-phase`** (the pinned-contract parallel workflow that shipped phases 1-7).

```bash
# full GUT suite (windowed harness: drop --headless, swap the -s script)
HOME=/tmp/anthesis-home tools/godot/macos_editor.app/Contents/MacOS/Godot \
  --headless --path . -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
# lint / format
find scripts tests -name "*.gd" | xargs uvx --from "gdtoolkit==4.*" gdformat
find scripts tests -name "*.gd" | xargs uvx --from "gdtoolkit==4.*" gdlint
```

## Adding Content (data → registry → World; mutations via the bus)

- **Item / recipe / creature / stem** → add a `.tres` under `resources/<kind>/`; the
  matching registry auto-scans the dir. Copy an existing `.tres` for typed-array syntax.
- **Ability** → `.tres` in `resources/abilities/` **plus** an effect `Callable` in
  `world.gd` `_install_ability_effects` keyed by `kind`.
- **Command** → `scripts/core/commands/<name>_command.gd extends WorldCommand`; add a
  `WorldContext` field for any new service and a `CommandCodec` case if replicable.

## Top Gotchas

- Prefix `HOME=/tmp/anthesis-home`; run `make import` before first test / after adding assets.
- `height_at` returns `NAN` until terrain streams — gate position logic on `not is_nan(...)`.
- Use built-in `FastNoiseLite` (not `ZN_FastNoiseLite`) for `VoxelGeneratorNoise.noise`.
- Keep RNG in `WorldSeed.derive(...)`; hold the owner of any `Callable` seam (GC).
- `.tres` typed arrays: `Array[ExtResource("2")]([SubResource("x")])`, not bare `[...]`.
- `project.godot` and `world.gd` are integrator-only — never edit in a parallel builder slice.
