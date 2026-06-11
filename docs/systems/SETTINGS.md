# Settings & Pause Menu System

Escape opens a pause menu over the game: Resume / Quit, live settings controls
(mouse sensitivity, master volume, fullscreen), and a key bindings list
generated from the live `InputMap`. Settings are a pure data model persisted to
`user://settings.cfg`; a separate applier maps each value onto the engine, and
World owns pausing and quitting. Opening the menu pauses the `SceneTree` only
when offline — in a live co-op session the shared world keeps running under the
overlay.

## Key Files

| File | Role |
|---|---|
| `scripts/systems/settings/game_settings.gd` | `GameSettings` — pure model + ConfigFile persistence |
| `scripts/systems/settings/settings_applier.gd` | `SettingsApplier` — maps each setting onto the engine |
| `scripts/ui/pause_menu.gd` | `PauseMenu` — menu UI, bindings list, intent signals |
| `scenes/ui/pause_menu.tscn` | Menu scene (lives in the HUD `CanvasLayer`) |
| `scripts/systems/world/world.gd` | `_build_pause_menu()` — wiring, pause/quit ownership |
| `scripts/tools/verify/pause_menu.gd` | Live SceneTree verification harness (windowed) |
| `tests/unit/test_game_settings.gd` | Model defaults / clamping / persistence tests |
| `tests/unit/test_settings_applier.gd` | Engine-application tests |
| `tests/unit/test_pause_menu.gd` | Menu structural + bindings-list tests |
| `tests/unit/test_pause_menu_behavior.gd` | Open/close/buttons/two-way-binding tests |

## Flow

```
Escape (toggle_menu action)
  └─ PauseMenu._unhandled_input → toggle()
       ├─ opened  ──► World._on_menu_opened   (pause tree iff session inactive)
       ├─ closed  ──► World._on_menu_closed   (unpause)
       └─ quit_requested ──► World._on_quit_requested (get_tree().quit())

Slider / checkbox change
  └─ PauseMenu handler → GameSettings setter (clamps, no-ops on equal value)
       └─ changed(key, value) ──► World._on_setting_changed
            ├─ SettingsApplier.apply(key, settings)
            │    ├─ mouse_sensitivity → Player.sensitivity_scale
            │    ├─ master_volume     → AudioServer bus 0 (linear_to_db, floored)
            │    └─ fullscreen        → DisplayServer window mode (headless no-op)
            └─ GameSettings.save_to_file()   (user://settings.cfg)
```

The menu never touches the engine or World directly — it edits the bound
`GameSettings` and emits intent signals, mirroring how `SessionPanel` and the
HUD stay presentation-only. World loads the file once in `_build_pause_menu()`
and applies everything via `SettingsApplier.apply_all`, so persisted values
take effect on boot.

## Settings Surface

| Key | Type / range | Applied to |
|---|---|---|
| `mouse_sensitivity` | float, clamped 0.2–3.0 (1.0 default) | `Player.sensitivity_scale` multiplier on `MOUSE_SENSITIVITY` |
| `master_volume` | float, clamped 0–1 (1.0 default) | Master audio bus dB (floored at ~-80 dB so it never hits -inf) |
| `fullscreen` | bool (false default) | `DisplayServer.window_set_mode` (guarded no-op headless) |

## Key Bindings List

`PauseMenu.BINDINGS` is the display spec: an ordered `[action, label]` array.
Key names resolve at runtime via `PauseMenu.binding_text(action)`, which reads
`InputMap.action_get_events` and renders the first key (`OS.get_keycode_string`
on the physical keycode) or mouse button ("Left Mouse" / "Right Mouse"). The
list therefore always matches `project.godot` — rebinding an action in the
input map updates the menu with no code change.

The Escape action is `toggle_menu` (renamed from the pre-menu
`toggle_mouse_capture`; the player controller no longer handles Escape —
clicking recaptures the mouse as before).

## How to Extend

**Add a setting:**
1. Add the var + clamped setter to `GameSettings` (emit `changed` with a new key).
2. Persist it in `save_to_file` / `load_from_file`.
3. Map the key in `SettingsApplier.apply` and add it to `apply_all`'s key list.
4. Add a control to `pause_menu.tscn` (`unique_name_in_owner`), wire it in
   `PauseMenu._ready` / `_refresh_controls` like the existing sliders.
5. Copy a case in `test_game_settings.gd`, `test_settings_applier.gd`, and
   `test_pause_menu_behavior.gd`.

**Add a key binding row:** append `[action, label]` to `PauseMenu.BINDINGS`
(the action must exist in `project.godot`'s `[input]` section —
`test_every_listed_binding_resolves` enforces it).

## Gotchas

- **`process_mode = ALWAYS`** on the menu root is load-bearing: the tree is
  paused while the menu is open offline, and a pausable node would never see
  the second Escape.
- **Slider echo loops:** `_refresh_controls` writes slider values, which
  re-enter the change handlers and write back to settings. `GameSettings`
  setters no-op on equal values, which is what breaks the cycle — keep that
  guard if you touch the setters.
- **Pause is World's call, not the menu's.** The menu can't know whether a
  co-op session is live; only `World._on_menu_opened` checks
  `NetworkSession.is_active()`.
- **Don't add a public `settings()` getter to World** — World sits at the
  gdlint public-method cap. Integration tests read `world.get("_settings")`.
