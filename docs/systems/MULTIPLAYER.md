# Multiplayer System

Host-authority co-op for up to 8 players (1 host + 7 clients) over ENet. All shared-world mutations flow through one `CommandRouter` that decides — based on session role — whether a command executes locally, is committed + broadcast by the host, or is requested from the host by a client. Client-local state (inventory, magic, combat, crafting) stays on the originating peer in v0.

## Key Files

| File | Role |
|---|---|
| `scripts/systems/net/network_session.gd` | `NetworkSession` — ENet lifecycle, authority model |
| `scripts/systems/net/command_router.gd` | `CommandRouter` — authority-aware routing seam |
| `scripts/core/net/command_codec.gd` | `CommandCodec` — stateless encode/decode |
| `scripts/core/net/command_log.gd` | `CommandLog` — bounded ordered replication log |
| `scripts/systems/net/player_sync.gd` | `PlayerSync` — position broadcast at 10 Hz |
| `scripts/systems/net/remote_player.gd` | `RemotePlayer` — procedural avatar with lerp/snap |
| `scripts/ui/session_panel.gd` | `SessionPanel` — host/join/leave UI (press M) |
| `scripts/tools/net_smoke/host_test.gd` | Two-instance live smoke test — host side |
| `scripts/tools/net_smoke/client_test.gd` | Two-instance live smoke test — client side |
| `tests/unit/test_command_codec.gd` | Codec encode/decode unit tests |
| `tests/unit/test_command_log.gd` | Log bounds + ordering tests |
| `tests/unit/test_command_router.gd` | Router authority routing tests |
| `tests/unit/test_network_session.gd` | Session state machine tests |
| `tests/unit/test_player_sync.gd` | PlayerSync broadcast + avatar tests |
| `tests/unit/test_remote_player.gd` | RemotePlayer lerp/snap tests |
| `tests/integration/test_world_net.gd` | Full-world net integration tests |

## Authority Model and v0 Trust Scope

The host is always **peer 1** under Godot's high-level multiplayer. The host is the single authority for all shared-world mutations.

| Role | `has_authority()` | Behaviour |
|---|---|---|
| Offline (solo) | true | Runs the same code path as host; nothing leaves the machine |
| Online host (peer 1) | true | Commits, executes, logs, broadcasts |
| Online client (peer N) | false | Requests replicable commands from host; executes local-only commands locally |

**Offline = solo host.** `NetworkSession.has_authority()` returns true when not active, so the entire offline path exercises exactly the same logic as the online host path. No special-casing needed.

**v0 trust:** the host validates numeric ranges on inbound client commands (`CommandCodec` range gates) but does not authenticate intent. Designed for cooperative friends, not adversarial users.

**Client-local commands** (never leave the peer): `CastCommand`, `DamageCommand`, `CraftCommand`. Inventory and magic state are not replicated in v0. Each peer runs its own local combat.

## CommandCodec Wire Format

`CommandCodec` (`RefCounted`) is stateless and side-effect free. `encode(cmd, world)` returns a `Dictionary`; `decode(data, world)` returns a `WorldCommand` or `null`.

| Command | Wire tag `t` | Fields |
|---|---|---|
| `DigCommand` | `"dig"` | `c: [x,y,z]`, `r: radius` |
| `PlaceCommand` | `"place"` | `c: [x,y,z]`, `r: radius` |
| `PlaceBlockCommand` | `"pblock"` | `item: "note_block"` or `"sequencer_core"`, `c: [x,y,z]` |
| `RemoveBlockCommand` | `"rblock"` | `path: "Block_3"` (node name under blocks_container) |
| `CycleNoteCommand` | `"cycle"` | `path: "Block_3"` |
| `HarvestCommand` | `"harvest"` | `idx: 2` (flora child index), `drops: [["seed",1],...]` |
| `CastCommand`, `DamageCommand`, `CraftCommand` | (none — `{}`) | client-local, not replicated |

**Range gates (host-side validation):**
- Coordinates: `|x|, |y|, |z| <= MAX_COORD` (100000.0)
- Radius: `MIN_RADIUS` (0.1) to `MAX_RADIUS` (10.0)

**Target resolution:** `rblock` and `cycle` paths resolve `path` against `world.blocks_container().get_node_or_null(path)`. `harvest` resolves `idx` against `world.flora().get_children()[idx]`. When the target has despawned, `decode` returns `null` — the caller drops the stale command.

## CommandRouter: The Seam

`CommandRouter` (`Node`) is the single `submit(cmd)` entry point for all player intent. All player-input handlers in `World` call `router().submit(cmd)` rather than `bus.execute(cmd)`.

**Routing decision in `submit(cmd)`:**

```
if not active session:
    bus.execute(cmd)                          # offline / solo
elif has_authority and replicable:
    _commit(encode(cmd))                      # host: validate, exec, log, broadcast
elif has_authority and not replicable:
    bus.execute(cmd)                          # host, local-only
elif not has_authority and replicable:
    rpc_id(1, request_command, encode(cmd))   # client: ask host
elif not has_authority and not replicable:
    bus.execute(cmd)                          # client, local-only
```

**RPC surface (4 methods, each is a thin unpacker):**

| RPC | Direction | Mode | Body |
|---|---|---|---|
| `request_command(data)` | client → host | `any_peer`, reliable | `_handle_request(data, sender_id)` |
| `commit_command(data)` | host → clients | `authority`, reliable | `_handle_commit(data)` |
| `request_state()` | client → host | `any_peer`, reliable | `_send(&"receive_state", [_build_state()], sender)` |
| `receive_state(state)` | host → client | `authority`, reliable | `_handle_state(state)` |

**`_commit(data)`** (host path): decode → execute on bus → append to log → broadcast `commit_command` to all peers (peer 0 = broadcast).

**`_send(method, args, peer=0)`** is the sole point where traffic leaves the node. Test doubles override `_send` to capture instead of transmit (see `FakeRouter` in `test_command_router.gd`).

## Late-Join: Seed Handshake + Log Replay

When a client connects and `session_started(hosting=false)` fires, `World._on_session_started` immediately calls:
```gdscript
_router.request_state.rpc_id(NetworkSession.HOST_PEER_ID)
```

The host builds a snapshot:
```gdscript
{"seed": world.seed_value(), "log": _log.entries()}
```

The client receives it via `receive_state` → `state_received` signal → `World._on_state_received` → `World.rebuild_for_session(new_seed, log_entries)`.

**`rebuild_for_session(new_seed, log_entries)`:**
1. Sets `seed_value` and rebuilds `WorldSeed`.
2. Frees and rebuilds the `VoxelWorld` with the new seed.
3. Clears flora, blocks, blooms, and Umbrals.
4. Re-parks the player at `PLAYER_SAFE_ALTITUDE` and re-enables `_process` so terrain polling resumes.
5. Calls `_replay_log(log_entries)`: decodes each entry via `CommandCodec.decode(entry, self)` and executes it through the bus (not the router — replayed commands are not re-broadcast).

**`connected_to_server` deferral:** `NetworkSession.join()` does not emit `session_started` immediately — it defers until `multiplayer.connected_to_server` fires (after the ENet handshake completes). RPCs sent before the handshake are silently dropped by ENet.

**Unstreamed-chunk caveat:** voxel terrain streams in asynchronously. Dig/place commands in the log that reference unstreamed chunks will silently no-op in the voxel tool. Block and flora commands replay correctly because they don't depend on streaming state.

**CommandLog bounds:** `MAX_ENTRIES = 5000`. Past that, oldest entries are evicted and `CommandLog.dropped()` increments. A late joiner arriving after a drop gets a partial world; this is an accepted v0 trade-off. Surface `command_log().dropped() > 0` in the session panel if needed.

## PlayerSync and RemotePlayer

`PlayerSync` (`Node`) broadcasts the local player's position and yaw to peers at `BROADCAST_INTERVAL` (0.1 s = 10 Hz) via an internal `Timer`.

**`sync_state(pos, yaw)`** — the only `@rpc` method (`any_peer`, unreliable). On receipt, `_apply_remote_state(sender, pos, yaw)` spawns a `RemotePlayer` avatar on demand (first packet creates it) and calls `avatar.update_state(pos, yaw)`.

`RemotePlayer` (`Node3D`) lerps toward `_target_pos` / `_target_yaw` each `_process` frame at `LERP_SPEED` (12.0). If the gap exceeds `SNAP_DISTANCE` (8.0 m) — e.g. after late-join replay — it snaps instantly. The avatar is a procedural capsule (CapsuleMesh, radius 0.35, height 1.7) with an emissive indigo material, an `OmniLight3D` halo, and a billboard `Label3D` showing `"peer N"`.

Avatars are freed immediately on `peer_left`. All avatars are cleared on `session_ended`.

## net_smoke Harness

Two scripts that test the real replication path without GUT:

```bash
export HOME=/tmp/anthesis-home
GODOT="tools/godot/macos_editor.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . -s res://scripts/tools/net_smoke/host_test.gd &
sleep 1
"$GODOT" --headless --path . -s res://scripts/tools/net_smoke/client_test.gd
```

**Success criteria:**
- Host prints `HOST_OK <N>` where N >= 1 (the DigCommand landed in the log).
- Client prints `CLIENT_GOT_DIG` (the broadcast `commit_command` was decoded and executed, evidenced by `CommandBus.command_executed`).

The DigCommand's voxel edit may no-op headless (chunks unstreamed) — the test validates the replication path, not the terrain mutation.

Port: **24571** (distinct from the default play port 24565 to avoid conflicts).

## SessionPanel

`SessionPanel` (`Control`) lives under the HUD CanvasLayer. Toggle with **M** (`toggle_session` input action). Shows status (Offline / Hosting on :24565 — N peers / Connected to address). Emits only signals; never calls `NetworkSession` directly. `World` owns the session lifecycle and wires the panel's signals:

- `host_requested` → `_session.host()`
- `join_requested(address)` → `_session.join(address)`
- `leave_requested` → `_session.leave()`

## Extending: Replication Checklist

When adding a new command that mutates shared world state:

1. **Add a wire branch to `CommandCodec.encode`:** return a `Dictionary` with a unique `"t"` tag and any scalar/array fields (no Node references).
2. **Add a decode branch to `CommandCodec.decode`:** validate all fields, resolve scene targets via `world.blocks_container()` or `world.flora()`, return `null` on failure.
3. **Range-gate any numeric inputs** against `MAX_COORD` or custom bounds. The host decodes before committing — malformed data returns `null` and is silently dropped.
4. **Confirm `is_replicable` returns true** for your command (it just checks `encode(...) != {}`).
5. **Test round-trip:** `test_command_codec.gd` pattern — encode, assert non-empty; decode the result, assert the command fields match.
6. **Test stale target:** assert `decode` returns `null` when the scene target has been freed.

Commands that should remain client-local (inventory, combat, magic, crafting): leave them unenumerated in `CommandCodec` — they naturally encode to `{}` and the router will execute them locally.

## Testing Notes

- `test_command_router.gd`: uses `FakeRouter` (captures `_send`), `FakeSession` (forces posture), `FakeCodec`, `FakeLog`. Covers all four routing branches, `_handle_request` authority guard, `_handle_commit`, `_build_state` seed extraction, `_handle_state` signal.
- `test_command_codec.gd`: all six replicable commands round-trip, client-local commands encode to `{}`, malformed fields (wrong type, out-of-range, missing) decode to `null`, stale targets decode to `null`.
- `test_network_session.gd`: host/join/leave state transitions, `has_authority` offline and host postures.
- `test_player_sync.gd`: `_apply_remote_state` spawns avatar on first packet, updates position, frees on `peer_left`, clears on `session_ended`.
- `test_world_net.gd` (integration): session OFFLINE by default, router and log present, remote players container present, player intents route through the router, offline submit raises intensity, `rebuild_for_session` reseeds and rebuilds terrain cleanly.

## Gotchas

- `session_started(false)` fires when `connected_to_server` fires (after the ENet handshake) — not when `join()` is called. Do not send RPCs to the host before `session_started`.
- `request_state` is called with `rpc_id(HOST_PEER_ID)` not `rpc()` — broadcast is wrong here; only the host has the snapshot.
- Replay routes through the bus (`_command_bus.execute(cmd)`) not the router — this prevents re-broadcasting the replayed history to peers that already have it.
- Block node names (`Block_0`, `Block_1`, ...) are resolved by `CommandCodec` for `rblock` and `cycle` commands. Renaming blocks after placement (e.g. by modifying `BlockPlacementService._spawn_counter` out of order) will break wire decoding.
- Voxel terrain streaming is async. A client rebuilding from a log with dig/place commands will replay them correctly in terms of the command sequence, but the actual terrain deformation depends on when chunks stream in. This is a known v0 limitation.
- The test suite does not open sockets. The `net_smoke` scripts are the only live-network validation.
