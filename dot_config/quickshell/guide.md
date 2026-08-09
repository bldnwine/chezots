# Quickshell coding guide (for agents)

## Run / reload / errors
- Entry: `desktop/shell.qml`. Launch: `qs -n -d -c desktop`.
- Saves hot-reload automatically. After edits: `qs log -c desktop` — `WARN scene: @<file>[line]` is the error surface.

## Lint
- `cd ~/.config/quickshell/desktop && qmllint *.qml omni/*.qml` (exit 0 = clean)

## Test popups headlessly
- `qs -c desktop ipc call <target> toggle|open|close` (targets live in Navbar.qml's `IpcHandler` blocks)

## QML gotchas
1. New popups MUST be Loader-instantiated in Navbar.qml (a direct type ref fails: `Type X unavailable`); clear the source with a 250ms Timer after hide.
2. Use `Connections { target }` for popup signal wiring — manual `signal.connect(fn)` fires into the destroyed instance (TypeError on the root id).
3. `readonly property var` has no `onXChanged` handler — use a writable bound `property var`.
4. CardWindow steals focus on reveal; after a TextInput steals it, restore with `refocus()`.
5. Wifi = iwd (`iwctl`), BT = `bluetoothctl`/`bt-device`. No nmcli.
