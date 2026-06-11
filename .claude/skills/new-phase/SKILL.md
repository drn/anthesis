---
name: new-phase
description: 'Plan and execute a new feature phase for Anthesis using the proven pinned-contract parallel workflow pattern. Use when starting a new major feature or phase.'
---

# new-phase — ship a feature phase the way phases 1-9 shipped

Anthesis grew from an empty project to a full voxel adventure (diggable world →
inventory/crafting → tick + magic → combat → adaptive music → in-world sequencer
→ co-op → ferromancy → tempestlight/weather) across nine phases, each landed as
a single squash-merged PR with a green test suite (832 tests by phase 9). They
all used the same recipe. Follow it.

The core idea: **pin every interface as an explicit contract before any builder
writes code, hand each builder a non-overlapping slice with strict file
ownership, run them in parallel, then funnel everything through one integrator
and one skeptic.** The contracts are what make parallel work composable.

## The recipe

### 1. Scout inline (verify before you promise)

Before writing contracts, confirm every engine/API assumption *headless*, fast:

- Class exists / method signature is real: `make import` then a 10-line GUT test
  or a `-s` scratch script that calls the API and prints. Never assume a Godot
  or `godot_voxel` symbol exists — verify (e.g. `VoxelTool.raycast` return type,
  `VoxelGeneratorNoise.noise`'s expected type, `AudioStreamPlayer` transport).
- Resource shape: load an existing `.tres` and read the fields you'll mirror.
- Existing seams: read `scripts/systems/world/world.gd` to see what the
  integrator already wires and what getters exist. The whole game composes here.

Scouting is cheap; a wrong contract is expensive (every builder builds against
it in parallel).

### 2. Write pinned contracts

A contract is the **exact** interface each new unit exposes — written down
before code. For every new class/file:

- `class_name`, base type, and file path (e.g.
  `scripts/systems/magic/lumen_well.gd` → `class_name LumenWell extends RefCounted`).
- Every public method signature with types and the `_init(...)` shape.
- Signal names and argument types.
- Resource fields if it's a `.tres` data type.
- How `World` (the integrator) will wire it: which getter, which container node,
  which `WorldContext` field.

Pin constants too (capacities, costs, ranges) so builders and tests agree. The
contract is the source of truth; builders implement *to* it, the integrator
wires *to* it, the skeptic checks *against* it.

### 3. Strict file ownership (this is what prevents collisions)

Assign every file to exactly one agent. **Two agents never touch the same file.**

- **`project.godot` and `scripts/systems/world/world.gd` are ALWAYS
  integrator-only.** These are the two merge magnets — input map and the
  composition root. If a builder edits them, parallel work collides on merge.
  Builders expose their unit; the integrator wires it in.
- New systems get their own subdir (`scripts/systems/<system>/`), tests
  (`tests/unit/test_<unit>.gd`), and resources (`resources/<system>/`).
- A builder that needs a new input action or a new World getter writes it into
  the **contract**, not into `project.godot`/`world.gd` — the integrator applies it.

### 4. Parallel builders (4-5, model-matched)

Spin up 4-5 builders, each owning one contract slice:

- **Opus** for novel/algorithmic work: shaders, terrain/noise, voxel sim, AI,
  the sequencer timeline math, netcode protocol.
- **Sonnet** for mechanical work: `.tres` data authoring, boilerplate services,
  test scaffolding, docs.

Each builder writes its unit **plus its GUT tests** (Hard Rule 1) and
**lint-clean** code, against the pinned contract — but does **not** wire into
World. Builders prepend the Thanx security policy to any sub-sub-agent prompts.

**Builders NEVER run the Godot binary** (no `make test` / `make import` /
scratch `-s` scripts). Parallel Godot processes contend on the shared `.godot`
import cache and corrupt it. Builders validate with gdtoolkit only
(`uvx --from "gdtoolkit==4.*" gdformat` then `gdlint` on exactly their files);
the integrator is the first agent to run the suite and owns making every
builder's tests pass (phases 8-9: expect ~2-3 small test bugs per phase to
surface there — off-by-ones, deferred `queue_free`, spy-state spill).

**Contract delivery:** write the pinned contracts to an absolute path readable
by every agent (e.g. `/tmp/phase<N>_contracts.md`) and reference that path in
each builder prompt — don't paste the whole contract into every prompt.

### 5. Opus integrator (one agent, owns the seams)

The integrator owns `world.gd` + `project.godot`, pulls in every builder's unit,
wires getters/containers/`WorldContext` fields/input actions, and runs the full
loop until green:

```bash
make import        # refresh asset cache (.tres / wav added by builders)
make test          # full GUT suite — must be 100% green
make lint          # gdlint scripts tests
make format-check  # CI-safe format check
```

Then a **windowed live pass** (see `.claude/skills/verify-live/SKILL.md`) to
confirm the feature actually works in the running game, not just in tests.

### 6. Opus skeptic reviewer (re-runs everything, hunts drift)

A second Opus agent that *re-runs* import/test/lint/windowed from scratch and
reads the diff against the contracts looking for: silent contract drift (a method
renamed, a signal arg dropped), tests that assert wiring but not behavior, direct
world mutations bypassing the command bus (Hard Rule 4), game data smuggled into
code (Hard Rule 5), un-seeded RNG (Hard Rule 6), and anything touching
`addons/`. The skeptic has veto.

### 7. Verify + media + PR

- Live screenshots via `verify-live`, saved under `docs/media/` and registered
  as artifacts.
- Update docs: `docs/ARCHITECTURE.md` per-phase subsection, the relevant
  per-system doc under `docs/systems/`, `README.md` status/gallery, and the
  CLAUDE.md cookbook/gotchas if the phase added a content type or a new trap.
- PR with **SHA-pinned image embeds** (reference the committed blob SHA so the
  image renders in the PR even before merge), then **squash-merge** onto
  `master` (Hard Rule 8).

### Orchestrating with the Workflow tool (how phases 8-9 ran)

Phases 8-9 ran this recipe as a single background Workflow per phase with four
sequential stages — `Build` (4-5 builders via `parallel()`, model-matched),
`Integrate` (one Opus agent receiving all builder reports), `Docs` (one Sonnet
agent receiving the integrator report), `Skeptic` (one Opus agent with veto) —
while the orchestrator did the scouting, contract authoring, git/PR work, and
artifact registration outside the workflow. A dedicated docs stage between
integrator and skeptic works better than folding docs into the integrator: the
skeptic then cross-checks docs numbers against `.tres` ground truth as part of
its sweep.

### world.gd size budget (gdlintrc ceiling + the rig pattern)

A repo-root `gdlintrc` caps `max-file-lines` at 1200 and `world.gd` lives near
it. **Do not raise the ceiling.** Each new phase extracts its wiring into a
dedicated integrator-owned rig — `scripts/systems/world/<phase>_rig.gd`
(precedent: `FerromancyRig`, `TempestRig`) — that builds/wires the phase's
nodes, owns its tick handlers and ability-effect callables, and publishes onto
the `WorldContext`. World stays the thin composition root with **zero new
public methods** (it is at the 20-method gdlint cap; tests reach non-getter
systems via named child nodes or `world.get("_field")`).

## Failure modes seen across phases 1-9 (check for these)

- **int64 literals.** Seeds like `20260610` are fine, but bit-twiddling /
  hashing that overflows 32-bit wraps silently. Keep seed math inside
  `WorldSeed` streams (`derive(...)`), never hand-rolled.
- **`ZN_FastNoiseLite` type trap.** `godot_voxel` ships its own
  `ZN_FastNoiseLite`, but `VoxelGeneratorNoise.noise` is typed to Godot's
  **built-in** `FastNoiseLite` — assigning the `ZN_` variant fails. Use built-in
  `FastNoiseLite` with `frequency` directly (see `voxel_world.gd`).
- **Callable GC.** A lambda passed as a seam (e.g. the clock-tick `Callable` into
  `MagicSystem`, or the terrain `voxel_tool` provider) is collected if nothing
  holds a reference. Store the owning object, not just the `Callable`.
- **gdlint ceilings.** `gdlint` caps public methods per class and other metrics.
  World hit the public-method cap in Phase 7 — that's why `SimulationClock` has
  no getter and is fetched via `get_node("SimulationClock")`. Don't add gratuitous
  public getters; gate new introspection behind named nodes when near the cap.
- **`.tres` typed-array syntax.** Typed arrays in resources need the explicit
  form: `drops = Array[ExtResource("2")]([SubResource("drop_1")])` — not a bare
  `[...]`. Sub-resources are declared with `[sub_resource ...]` blocks. Copy an
  existing `.tres` (e.g. `resources/creatures/voidmoth.tres`,
  `resources/recipes/bloom_brick.tres`) exactly.
- **Parallel-agent file collisions.** The single biggest source of merge pain —
  prevented entirely by strict file ownership and keeping `project.godot` /
  `world.gd` integrator-only (step 3).
- **Parallel Godot runs corrupt `.godot`.** Builders running `make import`/
  `make test` concurrently in the shared worktree race on the import cache.
  Builders lint-only; integrator runs the suite (step 4).
- **Alphabetical hotbar reshuffle.** `AbilityRegistry.abilities()` sorts by id,
  so adding an ability re-orders every cast slot. Pin the new full slot order
  in the contract, extend `cast_N` input actions + the player's hotkey loop,
  and update GAMEPLAY.md's table — registry-count test assertions break too.
- **Stat-modifier overwrites.** Two statuses both setting `player.speed_scale`
  directly corrupt each other on expiry. Route all multipliers through
  `world.gd`'s `_speed_mods` product table (phase 9 precedent) — never set the
  player field from an effect callable.
- **`height_at` returns NAN.** Terrain streams asynchronously; position-dependent
  logic must gate on `not is_nan(...)`. Bit the player-placement code until World
  learned to park at a safe altitude and poll.
- **`connected_to_server` deferral.** On a joining client, RPCs sent before the
  ENet handshake are silently dropped. `NetworkSession` defers
  `session_started(false)` until `connected_to_server` fires — never RPC the host
  the instant after `join()`.
- **Forgot `--import` / wrong HOME.** Always `make import` after adding assets,
  always prefix `HOME=/tmp/anthesis-home` on raw binary invocations.

## Related

- `CLAUDE.md` — Hard Rules, directory layout, content cookbook, gotchas.
- `docs/ARCHITECTURE.md` — the layer model every phase respects.
- `docs/COMMANDS.md` — the command bus all world mutations route through.
- `.claude/skills/verify-live/SKILL.md` — the live verification step.
