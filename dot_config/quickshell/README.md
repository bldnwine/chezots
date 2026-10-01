# Quickshell Architecture & Agent Guide

> **Primary Audience**: AI Coding Assistants & System Developers  
> **Location**: `~/.config/quickshell/`  
> **Entry Point**: `desktop/shell.qml`  
> **Daemon Invocation**: `qs -n -d -c desktop` (launched via `exec-once` in `~/.config/hypr/hyprland.lua`)

---

## 1. System Overview

This configuration runs a complete, unified desktop shell environment inside a **single Quickshell (Qt 6 / QML) daemon process**. All surfaces—the top navigation bar, the Locus full-screen command palette, system popups, the animated background layer, the OSD, and the PolicyKit authentication agent—run in the same process space and share a single reactive `Theme` instance.

### Key Architectural Tenets
1. **In-Process Communication**: Surfaces interact directly in memory. For example, `Navbar.qml` directly triggers `locus.toggle()`, and `Locus.qml` directly invokes `root.summonPopup(target)` without subprocess spawns or socket overhead.
2. **Wayland Global Shortcuts First (<10ms)**: 22 native Wayland global shortcuts are registered under `appid: "quickshell"`. Hyprland binds them using `hl.dsp.global("quickshell:<name>")`. External IPC via `qs -c desktop ipc call ...` serves as a headless/scripting fallback.
3. **Lazy Popup Lifecycle**: All overlay popups are lazily instantiated in `Navbar.qml` using `Loader` components and unloaded after a 250ms hide transition to conserve memory and avoid startup penalties.
4. **Reactive Theming**: Theme changes in `aether` propagate atomically to all open surfaces in zero-reload time via `~/.config/aether/theme/colors.toml`.

---

## 2. Directory & Component Map

```
~/.config/quickshell/
├── README.md                  # This master architecture guide for agents
├── guide.md                   # Concise coding gotchas cheatsheet (do not edit)
└── desktop/                   # Quickshell desktop config root (loaded with -c desktop)
    ├── shell.qml              # Root ShellRoot entry point; binds Theme, Background, PolkitAgent, Navbar, Locus
    ├── Theme.qml              # Live color theme manager and drift saturation animation
    ├── Palette.js             # Parses colors.toml and maps semantic roles (paper, ink, etc.)
    ├── Background.qml         # Multi-monitor layer-shell wallpaper with GPU diagonal wipe reveal
    ├── PolkitAgent.qml        # Native PolicyKit authentication dialog overlay (pkexec)
    ├── CardWindow.qml         # Base floating layer-shell window container for all popups
    ├── Navbar.qml             # Primary bar coordinator, popup Loader host, hardware stepping engines, 22 GlobalShortcuts
    ├── Bar.qml                # Default horizontal bar module layout (kanji workspaces, clock, telemetry)
    ├── BarHacker.qml          # Alternate hacker-style bar layout
    ├── BarWhiterose.qml       # Alternate minimal whiterose bar layout
    ├── Locus.qml              # Full-screen search palette, fuzzy search scorer, Quick tile grid controller
    ├── Data.js                # Search items database, category hierarchy, file extension icon mappings
    ├── omni/                  # Modular visual components of the Locus command palette
    │   ├── HeaderBar.qml      # Breadcrumb navigation, title, query stats
    │   ├── SearchInput.qml    # Interactive query input with blinking caret
    │   ├── ResultList.qml     # Filtered and scored result rows list
    │   ├── QuickContainer.qml # Samsung-style 4x3 Quick tile grid and expanded detail switcher
    │   ├── PreviewPane.qml    # Rich preview panel (files, GitHub repos, process kill, tldr, Ollama chat)
    │   ├── Footer.qml         # Selected item shell command display
    │   ├── Tiles.js           # Quick tile definitions and navbar telemetry bindings
    │   └── Format.js          # Markdown formatters for tldr and local AI chat
    ├── *Popup.qml             # Standalone popup panels loaded on-demand by Navbar.qml
    │   ├── AudioPopup.qml     # Volume sliders and sink switcher (pavucontrol launcher)
    │   ├── BluetoothPopup.qml # Bluetooth device pairing and connection manager
    │   ├── CalendarPopup.qml  # Monthly calendar, event dots, and Google Calendar meeting joiner
    │   ├── ClipboardPopup.qml # Clipboard history browser (persisted to clipboard-history.json)
    │   ├── DisplayPopup.qml   # Display brightness, color temperature (hyprsunset), and gamma
    │   ├── NetworkPopup.qml   # Wi-Fi network scanner and connection dialog (iwd / iwctl)
    │   ├── NotificationPopup.qml # Notification history center
    │   ├── SystemPopup.qml    # CPU, memory, and top process monitor
    │   ├── WallpaperPopup.qml # Wallpaper thumbnail browser and selector
    │   ├── WarpPopup.qml      # Cloudflare Warp toggle and status
    │   ├── WeatherPopup.qml   # Weather forecast card (wttr.in integration)
    │   └── WireprotonPopup.qml# WireGuard / Proton VPN manager
    └── scripts/               # Helper daemon and theme push scripts
        ├── aether-push-theme.sh # Pushes parsed colors.toml to Quickshell via IPC
        └── calendar-sync/     # Google Calendar sync scripts and systemd integration
```

---

## 3. Input & Dispatch Architecture

### Dual-Path Dispatch Model
1. **Wayland Global Shortcuts (Zero-Latency Primary)**:
   Registered natively in `Navbar.qml` via `GlobalShortcut { appid: "quickshell"; name: "..." }`.
   Bound in `~/.config/hypr/hyprland.lua` via `hl.dsp.global("quickshell:<name>")`.
2. **IPC Handlers (CLI & Scripting Fallback)**:
   Exposed across `Navbar.qml`, `Locus.qml`, `Theme.qml`, and `Background.qml` via `IpcHandler`.
   Triggerable from scripts via `qs -c desktop ipc call <target> <action> [args]`.

### Complete Shortcuts & Dispatch Table

| Global Shortcut Name (`quickshell:...`) | Hyprland Keybinding | Target / Action | External IPC Equivalent |
|---|---|---|---|
| `locus-toggle` | `SUPER + Space` | Toggle Locus search palette | `qs -c desktop ipc call locus toggle` |
| `locus-quick` | `ALT + Space` | Open Locus pivoted to Quick grid | `qs -c desktop ipc call locus openCategory Quick` |
| `clipboard-toggle` | `SUPER + A` | Toggle clipboard history | `qs -c desktop ipc call clipboard toggle` |
| `wallpapers-toggle` | `SUPER + ALT + A` | Toggle wallpaper selector | `qs -c desktop ipc call wallpapers toggle` |
| `bluetooth-toggle` | `SUPER + CTRL + B` | Toggle Bluetooth manager | `qs -c desktop ipc call bluetooth toggle` |
| `network-toggle` | `SUPER + CTRL + N` | Toggle Wi-Fi / network popup | `qs -c desktop ipc call wifi toggle` |
| `system-toggle` | `SUPER + CTRL + Q` | Toggle system performance popup | `qs -c desktop ipc call system toggle` |
| `audio-toggle` | `SUPER + CTRL + M` | Toggle audio mixer popup | `qs -c desktop ipc call audio toggle` |
| `bar-toggle` | `SUPER + H` | Toggle navigation bar visibility | `qs -c desktop ipc call bar toggle` |
| `wireproton-toggle` | `SUPER + K` | Toggle WireProton VPN popup | `qs -c desktop ipc call wireproton toggle` |
| `warp-toggle` | `SUPER + ALT + K` | Toggle Cloudflare Warp popup | `qs -c desktop ipc call warp toggle` |
| `hyprland-toggle` | `SUPER + G` | Toggle Hyprland cheatsheet popup | `qs -c desktop ipc call hyprland toggle` |
| `screenrecord-toggle` | `SUPER + SHIFT + K` | Toggle screen recording controls | `qs -c desktop ipc call screenrecord toggle` |
| `locusfavs-toggle` | `SUPER + ALT + Space` | Toggle directory bookmarks | `qs -c desktop ipc call locusfavs toggle` |
| `audio-vol-up` | `XF86AudioRaiseVolume` / `SUPER + CTRL + Up` | Volume +5% + instant OSD | In-shell hardware controller |
| `audio-vol-down` | `XF86AudioLowerVolume` / `SUPER + CTRL + Down` | Volume -5% + instant OSD | In-shell hardware controller |
| `audio-vol-mute` | `XF86AudioMute` | Toggle audio mute + instant OSD | In-shell hardware controller |
| `brightness-up` | `XF86MonBrightnessUp` | Backlight +5% + instant OSD | In-shell hardware controller |
| `brightness-down` | `XF86MonBrightnessDown` | Backlight -5% + instant OSD | In-shell hardware controller |
| `media-play-pause` | `XF86AudioPlay` / `SUPER + CTRL + 5` | Play / Pause MPRIS player | In-shell MPRIS controller |
| `media-next` | `XF86AudioNext` / `SUPER + CTRL + 6` | Next track MPRIS player | In-shell MPRIS controller |
| `media-prev` | `XF86AudioPrev` / `SUPER + CTRL + 4` | Previous track MPRIS player | In-shell MPRIS controller |

---

## 4. Hardware & Subsystem Integrations

| Subsystem | Tool / Implementation | Notes for Agents |
|---|---|---|
| **Audio** | In-shell stepping via `omarchy-cmd-audio-step.sh`, `pamixer`, `pavucontrol` | Instant OSD update; queries default PipeWire sink. |
| **Backlight** | In-shell stepping via `brightnessctl` | Steps in 5% increments with clamp; shows OSD bar. |
| **Media** | Native QML MPRIS service integration | Tracks active media player (Spotify, browser, etc.) and routes playback commands. |
| **Wi-Fi** | **`iwd` (`iwctl`)** | **NEVER use `nmcli`**. Omarchy and this setup rely strictly on `iwd`. |
| **Bluetooth** | `bluetoothctl` and `bt-device` | Powers on/off, scans devices, and connects via BlueZ CLI. |
| **Night Light** | `hyprsunset` | Controls color temperature and gamma via DisplayPopup. |
| **Wallpaper** | `omarchy-theme-bg-set <path>` -> `Background.qml` | Updates `~/.config/omarchy/current/background`; Quickshell runs a GPU diagonal wipe. No `swaybg`. |
| **Polkit** | `PolkitAgent.qml` | Handles native PolicyKit auth popups with shake animation. Privileged operations must use `pkexec`. |
| **Terminal** | `uwsm-app -- kitty` (`SUPER + Return`) | Direct instantaneous launch (<5ms) without subshell lookups. |

---

## 5. State & Configuration Locations

- **Quickshell State**: `~/.local/state/quickshell-desktop/`
  - `bar-templates.json`: Stored templates for bar heights, air, margins, and styles.
  - Setting overrides: Bar opacity, edge, and visibility state.
- **Omarchy System State**: `~/.local/state/omarchy/`
  - `calendar-events.json`: Cached Google Calendar and local events for `CalendarPopup.qml`.
  - `clipboard-history.json`: Active clipboard ring entries for `ClipboardPopup.qml`.
- **System Configs**: `~/.config/omarchy/`
  - `weather/location`: Custom location string for wttr.in (city, IATA, zip, or lat,long).
  - `current/background`: Symlink or path to active wallpaper image.
- **Theme Source**: `~/.config/aether/theme/colors.toml`
  - Canonical palette generated by Aether. Synced to `Theme.qml` via `aether-push-theme.sh`.

---

## 6. Critical QML Coding Rules for Agents

When editing or creating QML files in this repository, strictly adhere to these rules:

1. **Lazy Loading Required for Popups**:
   Never declare a popup as a direct type instance in `Navbar.qml`. Always wrap it in a `Loader`:
   ```qml
   Loader {
       id: myPopupLoader
       active: false
       sourceComponent: myPopupComponent
   }
   ```
   Reset `sourceComponent = undefined` after a 250ms hide timer to free resources.
2. **Declarative Connections**:
   Do NOT call `signal.connect(handler)` imperatively in JS. When the popup loader unloads, manual connections crash with `TypeError`. Always use:
   ```qml
   Connections {
       target: popupLoader.item
       function onDismissed() { /* cleanup */ }
   }
   ```
3. **No `: void` Annotations in Functions**:
   Qt 6 QML parser rejects `: void` return type annotations (e.g. `function hide(): void` fails `qmllint` with syntax errors). Use plain `function hide()`.
4. **CardWindow Focus Stealing**:
   `CardWindow.qml` grabs focus upon opening. If a subcomponent (like a `TextInput`) loses focus, restore it using `refocus()`.
5. **MouseArea Event Bubbling**:
   Child `MouseArea`s suppress parent hover events. Use compound checks:
   ```qml
   readonly property bool isHovered: rowMouse.containsMouse || btnMouse.containsMouse
   ```
6. **Privilege Escalation**:
   Always use `pkexec` when running commands requiring administrative privileges. **NEVER use `sudo`**.

---

## 7. Verification & Diagnostic Commands

Agents must run these checks before concluding tasks:

```sh
# 1. Lint all QML files (MUST exit code 0 clean)
cd ~/.config/quickshell/desktop && qmllint *.qml omni/*.qml

# 2. Check live Quickshell logs for QML runtime errors / warnings
qs log -c desktop

# 3. Verify all 22 global shortcuts are registered with the compositor
hyprctl globalshortcuts

# 4. Test a global shortcut through Hyprland
hyprctl dispatch global quickshell:locus-toggle

# 5. Headlessly test IPC surfaces
qs -c desktop ipc call locus toggle
qs -c desktop ipc call audio toggle
qs -c desktop ipc call background refresh

# 6. Verify Quickshell daemon process status
pgrep -a quickshell
```
