# Commands: the world-mutation layer

## Why everything is a command

Anthesis mutates authoritative world state in exactly one way: by submitting a
`WorldCommand` to the `CommandBus`. Nothing else — not input handlers, not the
player controller, not presentation nodes — touches world state directly.

This indirection buys us:

- **A single audit point.** Every mutation flows through `CommandBus.execute`,
  so validation, logging, undo, and metrics have one place to live.
- **A path to an authoritative server.** Commands are plain, serializable
  intent objects. A future networked build can validate, order, and replay them
  server-side without rewriting gameplay code.
- **Testability.** Commands carry their parameters and act through a
  `WorldContext`, so they can be unit-tested against stub services with no scene
  tree, no terrain, and no rendering.

## The pieces

- **`WorldCommand`** — abstract base. `apply(ctx)` performs the mutation.
- **`WorldContext`** — the dependency bundle handed to every command. Today it
  exposes `terrain_edit: TerrainEditService`; add new mutable services here.
- **`TerrainEditService`** — wraps a `VoxelTool` provider and performs the
  actual `dig_sphere` / `place_sphere` voxel edits.
- **`CommandBus`** — `execute(cmd)` applies the command against the context and
  emits `command_executed(cmd)`.
- **`DigCommand` / `PlaceCommand`** — concrete commands routing to the terrain
  edit service.

## Flow

```
input/signal -> build WorldCommand -> CommandBus.execute(cmd)
                                          -> cmd.apply(ctx)
                                          -> ctx.terrain_edit.dig_sphere(...)
                                          -> emit command_executed(cmd)
```

## Adding a new command

1. Create `scripts/core/commands/<name>_command.gd`:

   ```gdscript
   class_name GrowFloraCommand
   extends WorldCommand

   var _pos: Vector3

   func _init(pos: Vector3) -> void:
       _pos = pos

   func apply(ctx: WorldContext) -> void:
       ctx.flora_edit.grow_at(_pos)
   ```

2. If the command needs a service the context does not yet expose, add a field
   to `WorldContext` (e.g. `var flora_edit: FloraEditService`) and have the
   integrator assign it.

3. Add a unit test in `tests/unit/` that applies the command against a stub
   service and asserts it routed correctly. Stub services subclass the real
   service and record calls — see `tests/unit/test_commands.gd`.

4. Submit it through the bus from gameplay code: `bus.execute(GrowFloraCommand.new(pos))`.

Never call a service directly from gameplay code — always go through the bus.
