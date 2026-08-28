# Quickshell coding guide (for agents)

## Run / reload / errors
- Entry: `desktop/shell.qml`. Launch: `qs -n -d -c desktop`.
- Saves hot-reload automatically. After edits: `qs log -c desktop` — `WARN scene: @<file>[line]` is the error surface.

## Lint
- `cd ~/.config/quickshell/desktop && qmllint *.qml omni/*.qml` (exit 0 = clean)

## Test popups and surfaces headlessly
- `qs -c desktop ipc call <target> toggle|open|close` (targets live in Navbar.qml's `IpcHandler` blocks)
- Background: `qs -c desktop ipc call background set <path>` or `refresh`
- Polkit agent: `pkexec whoami` (triggers native overlay authentication card)

## Core state pipelines
- **Theme**: `aether` -> `~/.config/aether/theme/colors.toml` -> `aether-push-theme.sh` -> `qs -c desktop ipc call theme apply` -> `Theme.qml` (0 reload).
- **Wallpaper**: `omarchy-theme-bg-set <path>` -> `~/.config/omarchy/current/background` -> `qs -c desktop ipc call background set <path>` -> `Background.qml` GPU wipe. (No `swaybg`).
- **Calendar**: Cache at `~/.local/state/omarchy/calendar-events.json`. 5m user timer (`omarchy-calendar-sync`) + `scripts/calendar-sync/action.py (create|delete|edit)` for Google Calendar CRUD with 0ms optimistic UI.

## QML gotchas
1. New popups MUST be Loader-instantiated in Navbar.qml (a direct type ref fails: `Type X unavailable`); clear the source with a 250ms Timer after hide.
2. Use `Connections { target }` for popup signal wiring — manual `signal.connect(fn)` fires into the destroyed instance (TypeError on the root id).
3. `readonly property var` has no `onXChanged` handler — use a writable bound `property var`.
4. CardWindow steals focus on reveal; after a TextInput steals it, restore with `refocus()`.
5. Wifi = iwd (`iwctl`), BT = `bluetoothctl`/`bt-device`. No nmcli.
6. Child `MouseArea`s steal parent hover: use `readonly property bool isHovered: rowMouse.containsMouse || btnMouse.containsMouse`.
7. Prevent hover jitter: anchor text labels to fixed right margins instead of dynamic button widths.
