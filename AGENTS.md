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
