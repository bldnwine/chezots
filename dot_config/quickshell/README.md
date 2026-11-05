# Quickshell Architecture & Agent Guide

> **Primary Audience**: AI Coding Assistants & System Developers  
> **Location**: `~/.config/quickshell/`  
> **Entry Point**: `desktop/shell.qml`  
> **Daemon Invocation**: `qs -n -d -c desktop` (launched via `exec-once` in `~/.config/hypr/hyprland.lua`)

**Default scope for agents:** Ignore the Whiterose and Hacker bars (`BarWhiterose.qml`, `BarHacker.qml`) and Quick menu/body components unless the user explicitly requests work on them. Focus bar work on the active Zen bar (`Bar.qml`).

---

## 1. System Overview

This configuration runs a complete, unified desktop shell environment inside a **single Quickshell (Qt 6 / QML) daemon process**. All surfaces—the top navigation bar, the Locus full-screen command palette, system popups, the animated background layer, the OSD, and the PolicyKit authentication agent—run in the same process space and share a single reactive `Theme` instance.

### Key Architectural Tenets
1. **In-Process Communication**: Surfaces interact directly in memory. For example, `Navbar.qml` directly triggers `locus.toggle()`, and `Locus.qml` directly invokes `root.summonPopup(target)` without subprocess spawns or socket overhead.
2. **Wayland Global Shortcuts First (<10ms)**: 22 native Wayland global shortcuts are registered under `appid: "quickshell"`. Hyprland binds them using `hl.dsp.global("quickshell:<name>")`. External IPC via `qs -c desktop ipc call ...` serves as a headless/scripting fallback.
3. **Lazy Popup Lifecycle**: Overlay popups are lazily instantiated in `Navbar.qml` using `Loader` components. Most intentionally remain resident after first use. Network and Bluetooth unload after 250ms; wallpaper and selected other panels unload after 400ms, with shared service state retained.
4. **Reactive Theming**: Theme changes in `aether` propagate atomically to all open surfaces in zero-reload time via Aether’s dedicated `~/.config/aether/theme/quickshell.json` palette.

---

## 2. Directory & Component Map

```
~/.config/quickshell/
├── README.md                  # This master architecture guide for agents
├── guide.md                   # Concise coding gotchas cheatsheet (do not edit)
└── desktop/                   # Quickshell desktop config root (loaded with -c desktop)
    ├── shell.qml              # Root ShellRoot entry point; binds Theme, Background, PolkitAgent, Navbar, Locus
    ├── Theme.qml              # Dedicated QS palette, live previews, and drift animation
    ├── ShellSettings.qml      # Persistent panel/Locus layout and font settings
    ├── SettingsWindow.qml     # Movable desktop settings window
    ├── Palette.js             # Parses colors.toml and maps semantic roles (paper, ink, etc.)
    ├── Background.qml         # Multi-monitor layer-shell wallpaper with GPU diagonal wipe reveal
    ├── PolkitAgent.qml        # Native PolicyKit authentication dialog overlay (pkexec)
    ├── CardWindow.qml         # Base floating layer-shell window container for all popups
    ├── Navbar.qml             # Primary bar coordinator, popup Loader host, hardware stepping engines, 22 GlobalShortcuts
    ├── CalendarService.qml    # Persistent Calendar cache, sync, and event action lifecycle
    ├── WarpService.qml        # Persistent WARP status and action lifecycle
    ├── NetworkService.qml     # Persistent iwd actions, bounded scans, and active-route details
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
    │   ├── AudioPopup.qml     # Device controls, per-stream playback volume/mute, and equalizer
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
| `network-toggle` | `SUPER + CTRL + N` | Toggle Wi-Fi / network popup | `qs -c desktop ipc call network toggle` |
| `system-toggle` | `SUPER + CTRL + Q` | Toggle system performance popup | `qs -c desktop ipc call system toggle` |
| `audio-toggle` | `SUPER + CTRL + M` | Toggle audio mixer popup | `qs -c desktop ipc call audio toggle` |
| `bar-toggle` | `SUPER + H` | Toggle navigation bar visibility | `qs -c desktop ipc call bar toggle` |
| `wireproton-toggle` | `SUPER + K` | Toggle WireProton VPN popup | `qs -c desktop ipc call wireproton toggle` |
| `warp-toggle` | `SUPER + ALT + K` | Toggle Cloudflare Warp popup | `qs -c desktop ipc call warp toggle` |
| `hyprland-toggle` | `SUPER + G` | Toggle Hyprland cheatsheet popup | `qs -c desktop ipc call hyprland toggle` |
| `screenrecord-toggle` | `SUPER + SHIFT + K` | Stop recording if active, else toggle controls | `qs -c desktop ipc call screenrecord toggle` |
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
| **Audio** | In-shell stepping via `omarchy-cmd-audio-step.sh`, `pamixer`; native PipeWire playback controls | Instant OSD update; queries default PipeWire sink. AudioPopup provides separate 0–100% volume and mute controls for each application playback stream, hiding system sounds and internal equalizer streams. `pavucontrol` remains available for advanced mixing. |
| **Backlight** | Persistent `BrightnessService.qml` and connector-specific `brightnessctl` | Hardware-seeded 5% steps on the focused internal display; popup controls remain on their opening monitor. External displays have no brightness control; no DDC/CI commands are sent. |
| **Media** | Native QML MPRIS service integration | Tracks active media player (Spotify, browser, etc.) and routes playback commands. |
| **Wi-Fi** | **`iwd` (`iwctl`)** | **NEVER use `nmcli`**. Omarchy and this setup rely strictly on `iwd`. |
| **Bluetooth** | Native `Quickshell.Bluetooth` state and controls | Persistent service; local BlueZ `KeyboardDisplay` agent for interactive pairing, supervised `bluetoothctl` for already-paired connection. Native battery data with event-driven UPower fallback. No status polling. |
| **Battery** | Native `Quickshell.Services.UPower` | `BatteryService.qml` exposes percentage, watts, presence, and state without subprocesses. |
| **Night Light** | `hyprsunset` | Controls color temperature and gamma via DisplayPopup. |
| **Wallpaper** | `omarchy-theme-bg-set <path>` -> `Background.qml` | Updates `~/.config/omarchy/current/background`; Quickshell runs a GPU diagonal wipe. No `swaybg`. |
| **Polkit** | `PolkitAgent.qml` | Handles native PolicyKit auth popups with shake animation. Privileged operations must use `pkexec`. |
| **Terminal** | `uwsm-app -- kitty` (`SUPER + Return`) | Direct instantaneous launch (<5ms) without subshell lookups. |

Network, Bluetooth, and Audio popups have fixed preferred outer heights of 700, 540, and 760 logical pixels, respectively, capped by the available screen height. Their contents scroll without resizing the card when devices, errors, passphrase fields, or pairing prompts change. `CardWindow.bodyAvailableHeight` measures the space remaining after headers, footers, padding, and spacing. Audio's Output, Playback, and Input sections share that remaining space below the master controls; the expanded equalizer scrolls independently alongside them and retains the same outer height.

Network connection stats stay pinned above the footer while the network list scrolls independently above them, leaving spare space between the list and stats. On short screens, stats also scroll within their bottom viewport.

MediaPopup keeps player buttons in a clipped horizontal strip with wheel scrolling and a scrollbar. Changing the selected source brings its button into view while track metadata and playback controls stay stationary. Polkit command details wrap as plain text inside a scroll area capped at 180 logical pixels, with the authentication row kept below it; long multiline commands cannot overlap the password field.

The Zen bar uses bundled, theme-tinted SVG status icons fitted to 14px artwork bounds on every edge: Adwaita symbolic artwork for network, Bluetooth, audio, battery, and recording, with a lighter Adwaita-style filled-node Ethernet icon and Breeze headphones with slightly heavier strokes in the same 14px artwork frame; outlined Material Symbols Rounded for CPU, notifications, AI, and WARP. State mappings stay in presentation code, preserving the existing services, controls, colors, and app tray icons. Battery levels round to the nearest 10% with charging/full/plugged-in variants. Artwork bounds are measured offline and cached in `BarIconMetrics.js`, removing SVG padding from sizing and centering. Related state variants share a frame so signal, volume, and battery changes do not resize or shift the artwork. Icons use native `QtQuick.VectorImage` curve rendering with antialiasing, avoiding both bitmap resampling blur and nearest-pixel jagged edges. Path colors bind directly to the theme after asset loading, retaining each path’s original opacity (including the dimmed disconnected Bluetooth symbol). This uses the existing Qt 6.12 installation and requires no additional packages. Regenerate with `python3 desktop/scripts/bar-icon-metrics.py` after replacing SVGs. No icon polling runs; the existing AI working badge and network-burst animations stop when their host is hidden. Asset sources and licenses are in `desktop/icons/bar/README.md`.

The Zen bar shows plain 14px medium-weight song titles in the accent color on every edge, rotated bottom-to-top on the left and top-to-bottom on the right. Titles are capped at 140 logical pixels with right ellipsis; there is no title pill, music-note icon, or automatic scrolling. Media selection follows the player that most recently starts or resumes playback. Scrolling or selecting a popup source overrides selection until another player starts or the selected source disappears. Distinct sources are identified by D-Bus name, and `playerctld` proxies are excluded.

---

## 5. State & Configuration Locations

- **Quickshell State**: `~/.local/state/quickshell-desktop/`
  - `bar.json`: Version 1 bar settings, named templates, and selected template; old individual files are imported once and retained.
  - Bar style settings save atomically after a 250ms debounce. Visibility remains session-only.
- **Omarchy System State**: `~/.local/state/omarchy/`
  - `calendar-events.json`: Cached Google Calendar events for `CalendarService.qml` and `CalendarPopup.qml`.
  - `clipboard-history.json`: Active clipboard ring entries for `ClipboardPopup.qml`.
- **System Configs**: `~/.config/omarchy/`
  - `weather/location`: Custom location string for wttr.in (city, IATA, zip, or lat,long).
  - `current/background`: Symlink or path to active wallpaper image.
- **Theme Source**: `~/.config/aether/theme/quickshell.json`
  - Version 1 semantic palette generated by Aether, with alpha-last `#RRGGBBAA` support.
  - Startup, file notifications, push hooks, and wallpaper transitions share the same validated resolver. `colors.toml` is a migration fallback only when the dedicated palette is absent.
  - Invalid dedicated files retain the last valid palette.
- **Shell Appearance**: `~/.local/state/quickshell-desktop/settings.json`
  - Panel/Locus layout and text scales, independent background opacity and blur, normal/preview Locus widths, shared height, and Settings window dimensions. Sizing is machine-wide; colors belong to the active Aether theme/blueprint.

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
   Preserve intentional resident popups. For panels that unload, clear the Loader source after the hide transition and keep ongoing jobs/cache state in their persistent service.
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
   Interactive panels use fixed `OnDemand` keyboard interactivity with `PopupFocusGrab.qml`, releasing focus by unmapping. `PopupFocusStack.js` gives input to the most recently mapped panel and suspends popup grabs during authentication. Switching to `None` before unmapping or using exclusive layer focus can make Hyprland restore a window on an old workspace.
5. **MouseArea Event Bubbling**:
   Child `MouseArea`s suppress parent hover events. Use compound checks:
   ```qml
   readonly property bool isHovered: rowMouse.containsMouse || btnMouse.containsMouse
   ```
6. **Privilege Escalation**:
   Use `pkexec` for privileged commands. WARP daemon start/stop is the narrow exception: it uses the existing passwordless sudoers allowlist for the exact `sudo -n /usr/bin/systemctl start|stop warp-svc` commands.

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
hyprctl dispatch 'hl.dsp.global("quickshell:locus-toggle")'

# 5. Headlessly test IPC surfaces
qs -c desktop ipc call locus toggle
qs -c desktop ipc call audio toggle
qs -c desktop ipc call background refresh

# 6. Verify Quickshell daemon process status
pgrep -a -x qs
```

## 8. Performance Lifecycle & Regression Checks

- **Shell scheduling:** On this machine, Ananicy's `qs` entry in `/etc/ananicy.d/00-default/DEs-and-WMs/dank-material-shell.rules` explicitly sets CPU nice 0 and best-effort I/O priority 4, overriding the background `Service` defaults. `/etc/pacman.conf` protects this file with `NoUpgrade`; review future `.pacnew` files while preserving the `qs` correction. Duplicate rules in a separate local file do not reliably override the packaged rule with the installed Ananicy version. Restart Ananicy after editing this rule; reload retained the old effective priorities during verification.
- **Workspaces:** Navbar synchronizes the native focused workspace both at startup and on focus changes. Startup synchronization does not imply navigation direction; later switches retain directional animation. A temporarily unavailable native workspace preserves the last known selection.
- **Command independence:** App/terminal launches are detached. Control commands use persistent queues per feature, so an audio/display/Bluetooth/VPN/theme action cannot cancel another feature's job. Discrete actions remain ordered; repeated pending absolute settings coalesce without crossing discrete-action boundaries. Existing dedicated workers and service deadlines remain in place.
- **Equalizer:** One persistent service serializes live changes and preset operations across popup closure. Live changes retain only the latest pending snapshot; old state-file notifications cannot overwrite edits during a job or slider debounce. Helpers share a file lock and replace state/configuration atomically. Live updates and imports never restart PipeWire; use explicit APPLY to initialize an unavailable graph. Failed application or persistence is reported instead of showing a premature success.
- **Telemetry:** CPU/memory and network-burst counters use asynchronous `FileView` reads with no subprocesses. CPU keeps a 2s measurement window on a 5s cadence, including while the System popup is open with the bar hidden; explicit popup refreshes remain supported. Network burst sampling keeps its 1s cadence, 1.5 MiB threshold, and 2s cooldown. Hiding the bar, failed reads, and interface/counter resets reseed network baselines; cancelled system reads cannot publish stale samples. Link/address and VPN-interface changes use one resident netlink helper while their consumers are visible, with an in-process sampling fallback if netlink is unavailable. Wi-Fi signal reads use bounded `iw` calls at the existing 3s cadence; battery and Bluetooth now use native events.
- **Audio:** One persistent `pactl subscribe` connection drives debounced snapshots and device-list refreshes. Snapshots read each sink/source list once and preserve the equalizer's physical-sink routing. A 30s fallback runs only while the subscription is disconnected; reconnect attempts occur every 3s.
- **Recording:** `capture-screenrecording` already sends `screenrecord sync` at start/stop. A direct `pgrep` every 15s reconciles externally launched recordings and unexpected exits.
- **AI:** Visible active sessions update every 1.5s, but quotas refresh at most once per minute unless manually requested. Both active and inactive polling pause when the bar and AI popup are hidden. History metadata comes from one bounded tail read per scan. A request-driven Python worker reuses imports between scans, exits when consumers are hidden after any in-flight scan, and has a 15s deadline. The standalone scanner CLI remains compatible.
- **Notifications:** Archive pruning batches watcher arrivals against a fixed one-second deadline, checked between ingestions; display and archive announcements remain immediate. Retention parses the archive once per cleanup, extracts dropped screenshot candidates together, and preserves the archive inode/mtime when unchanged. The resident history popup rebuilds only while revealed and refreshes on reopening. Disk history can briefly exceed retention limits until cleanup, while live notification-object limits stay immediate. Startup, explicit remove/clear, and periodic cleanup retain their existing protections. Deduplication hashes expire after 3s. Live notification actions remain available within the archive's count/age limits, with declarative cleanup on closure. `NotificationOverlay.archiveDirectory` defaults to the production inbox and can be overridden by isolated tests.
- **Wallpaper:** The wipe mask is allocated only during the transition. The displayed image supplies the old frame unless an explicit alternate `fromPath` is provided. Final cleanup waits for every monitor to load its base image. `WallpaperService.qml` retains the browser index across popup unloads; opening reuses it immediately and refreshes when older than 30s. Ctrl+R forces refresh. Failed scans preserve the last complete index. Filtering uses a pre-sorted list; random order stays stable while typing.
- **Locus:** Closing cancels searches/previews, releases preview image sources, and unloads expanded Quick details. Result icons load asynchronously; failed lookups/loads are cached until the app index or theme changes. Theme discovery keeps the last complete list across closes and checks source metadata on entry and every 4s while the Themes view is open; unchanged inputs skip the full scan. Failed or cancelled scans preserve the cache.
- **Bloom:** Hover uses a fixed circle with scale/opacity animation over 250ms. The effect and clipping are inactive between hovers, and hiding its host item or window cancels the animation.
- **Calendar:** `CalendarService.qml` owns the cache and processes even when the popup closes. Opening a stale view starts the on-demand user service; failed syncs keep the last cache and retry with bounded backoff. Create, edit, and delete update the disk cache only after Google acknowledges the action, then request a full sync. The sync and actions share a file lock, write the cache atomically, and use bounded subprocess and service timeouts. Configure `gwsPath`, `profile`, calendar filters, and sync window in `~/.config/omarchy/calendar-sync.json`. Run `desktop/scripts/calendar-sync/login` to renew the full Calendar read/write scope. `gws auth status` does not report granted scopes; if a write gets a 403, rerun login and tick the Calendar consent checkbox. The old periodic systemd timer is retired.
- **Network:** `NetworkService.qml` survives popup unload and serializes connect, disconnect, radio, forget, and autoconnect actions. The helper receives JSON on stdin and invokes tools with argument arrays; SSIDs/passwords never enter shell code or diagnostic logs. Actions finish after close, while popup scans/details are cancelled and password input is cleared immediately. The popup unloads after 250ms and rescans on every opening. Explicit refreshes from other callers remain supported while the network popup is hidden. Failed reads retain the last successful network list. Connect has a 30s deadline; other actions/state reads 10s, scans 15s, and details 4s, followed by bounded subprocess cleanup. Details resolve the IPv4 route to `1.1.1.1`, read counters once, timestamp them before pinging, and bind the ping to that interface; gatewayless VPN routes show no gateway. Only one detail sample runs at a time, every 1.5s while open. Each sample launches the helper plus one route query and one ping, replacing the previous shell/pipeline probe and unused router ping. The network list scrolls without truncation; unknown PSK networks prompt immediately, and failed saved credentials offer an explicit password retry.
- **WARP:** Status reflects the daemon's reported connection state. Connection, mode, and daemon actions have timeouts; daemon start/stop uses the existing `sudo -n` allowlist without a password prompt. The popup expands after two valid startup status reads and confirms a brief daemon failure before collapsing again. Connectivity checks say "Verifying connectivity" instead of implying a tunnel connection. The widget does not change WARP connectivity-check settings or kill unrelated processes. Registration and settings responses are validated before replacing known state.

Additional regression checks:

```sh
python3 desktop/tests/workspace_state_test.py
python3 desktop/tests/network_helper_test.py
python3 desktop/tests/network_service_lifecycle_test.py
python3 desktop/tests/network_popup_test.py
python3 desktop/tests/audio_popup_test.py
python3 desktop/tests/media_popup_test.py
python3 desktop/tests/polkit_geometry_test.py
node desktop/tests/popup-focus.test.js
node desktop/tests/model.test.js
node desktop/tests/performance-model.test.js
node desktop/tests/telemetry-model.test.js
python3 desktop/tests/telemetry_lifecycle_test.py
python3 desktop/tests/eq_helper_test.py
python3 desktop/tests/command_isolation_test.py
python3 desktop/tests/performance_helpers_test.py
node desktop/tests/locus-icons.test.js
python3 desktop/tests/theme_cache_test.py
python3 desktop/tests/music_service_test.py
python3 desktop/tests/calendar_sync_test.py
python3 desktop/tests/service_lifecycle_test.py
# Requires a running Wayland compositor; uses a private D-Bus session and temporary archives.
python3 desktop/tests/notification_retention_test.py
```

## 9. Hyprperks-inspired native services and settings

- `BarSettings.qml` owns `~/.local/state/quickshell-desktop/bar.json`: `{version: 1, settings: {...}, templates: {...}, selectedTemplate: "zen"}`. One initial directory check precedes asynchronous FileView loading. When absent, ten legacy files are imported without deletion. Pending edits survive loading; persistence is atomic and debounced 250ms. Corrupt/unsupported JSON is retained and write-disabled, with an error in Bar Style; repair the JSON and reload to resume persistence. Existing Navbar setters and bar IPC stay compatible.
- `BluetoothService.qml` uses the default native adapter and reactive device objects. Power, trust, disconnect, forget, and discovery use native controls. Pairing uses an application-local `KeyboardDisplay` agent with PIN/passkey/confirmation prompts; paired-device connection receives argument arrays. Explicit dismissal cancels pairing; ordinary connections survive popup closure. All operations have deadlines. Discovery is cancellable and stops after 15s. Adapter replacement stops discovery owned by the old adapter. The standalone popup shows all devices in a scrolling list and unloads after 250ms; the persistent service stays alive. Quick menu bodies and Whiterose are outside this change.
- `BatteryService.qml` reads UPower's aggregate display device. Percentages convert from fractions to 0–100; `changeRate` is already watts. Only present laptop batteries count; unavailable data remains Unknown, and batteryless systems report AC. Power-profile controls are unchanged.

Regression checks:

```sh
node desktop/tests/bar-settings.test.js
python3 desktop/tests/adoption_lifecycle_test.py
```

The lifecycle suite uses private buses, temporary files, fake adapters/batteries, and a fake authorization agent; it does not modify live hardware or desktop state.


## 10. Pond implementation adaptations

- `BrightnessService.qml` is the sole owner of brightness reads and writes, including keys, standalone display controls, presets/reset, startup restore, and nightlight. It serializes operations, coalesces pending absolute settings and consecutive same-direction steps, and measures hardware before relative changes. Only a uniquely associated internal DRM backlight is supported; external displays report unavailable without DDC/CI probing or writes. A removed connector invalidates pending/stale work. The display popup pins its opening monitor and captures its baseline before allowing brightness edits. New input takes precedence over startup restoration.
- `display-state.json` retains its existing keys and adds `brightnessByOutput`, `nightlightPreviousByOutput`, and `nightlightOutput`. Legacy `bright` imports for the unique internal display. Writes are atomic and serialized. Nightlight measures its previous brightness immediately before dimming and restores the originating display, including rapid on/off sequences.
- `BluetoothService.qml` owns pairing prompts across lazy loading. Its short-lived Gio/GLib helper registers an application-local agent, validates the BlueZ sender/device and prompt IDs, and never becomes the default agent. New prompts open the standalone popup; explicit dismissal cancels pairing and clears input. Ordinary connect/disconnect operations continue after closure. BlueZ battery data takes precedence over a MAC-matched UPower fallback. Dependencies: Python `gi` with Gio/GLib (already available on this system).
- `AudioDeviceService.qml` serializes output/input switches through an argv-safe helper, preserving EQ routing and selectable ports. Errors appear in the audio popup; each completed operation refreshes device state. Master volume retains the existing backend. Per-app playback already uses native PipeWire controls.
- Media keys can target a capable, untitled paused player when no display source is selected. Existing selected-source precedence remains intact. Volume and brightness OSD cards expose accessible progress roles and labels.

Additional isolated regression checks (fake hardware and temporary state):

```sh
python3 desktop/tests/brightness_helper_test.py
python3 desktop/tests/brightness_service_test.py
node desktop/tests/brightness_integration.test.js
python3 desktop/tests/display_state_write_test.py
python3 desktop/tests/bluetooth_helper_test.py
python3 desktop/tests/bluetooth_pairing_test.py
python3 desktop/tests/audio_device_helper_test.py
python3 desktop/tests/audio_device_service_test.py
node desktop/tests/audio_device_integration.test.js
python3 desktop/tests/notification_watch_batch_test.py
python3 desktop/tests/adoption_compile_test.py
```

Bar icon regression checks (the renderer test uses an isolated offscreen window and private D-Bus session):

```sh
python3 desktop/scripts/bar-icon-metrics.py --check
node desktop/tests/bar-icons.test.js
python3 desktop/tests/bar_icon_render_test.py
```


## 11. Quickshell Settings and dedicated palettes

Open **Quickshell Settings** from Locus (search `settings`), or run
`qs -c desktop ipc call settings open`. The resizable desktop window has
Colors, Panels, and Locus pages. It has no Bar Style entry point.

Color changes preview live across the shell. **Cancel** restores the last
applied palette. **Apply** persists Quickshell colors across restarts without
changing a blueprint; the next full Aether theme apply uses that theme’s saved
overrides. **Save current** also updates the explicitly applied blueprint.
**Save as** duplicates the applied theme, leaves the original intact, and makes
the new blueprint current. When the active theme predates source tracking or
has no blueprint, Apply and Save as work; apply a saved blueprint to enable
Save current. Closing a dirty window offers Apply, Discard, or Keep editing.

Aether stores sparse `qs_*` overrides under `appOverrides.quickshell` in the
blueprint; there is no custom-mode flag. Reset removes an override and follows
the template default. Its existing per-app editor exposes the same roles.
Aether’s `applied-theme.json` records applied state, source identity, and
revisions; stale saves fail without replacing newer blueprint edits. A theme
switch cancels the old preview. Generated color files and global application
palettes stay independent.

Panel layout scales range from 0.75–1.5 and text multipliers from 0.7–2.0.
Standalone popups follow these settings, with screen-capped cards and scrollable
content. Bar geometry stays in Bar Style. Toast notifications, OSD,
authentication prompts, tray menus, alternate bars, and Quick detail bodies keep
their existing sizing. Panel and Locus settings save automatically.

Locus has separate normal/preview widths and one shared height. Resize with
its edge/corner grips or Settings controls; zero height means automatic.
Saved preferences survive smaller monitors while the rendered card fits the
current screen. Layout scale controls internal spacing independently of these
outer dimensions. Ctrl++/Ctrl+- and Ctrl+= update/reset the persisted Locus
text multiplier. `qs -c desktop ipc call locus geometry` reports rendered bounds.

Additional isolated regression checks:

```sh
node desktop/tests/shell-settings.test.js
node desktop/tests/palette.test.js
python3 desktop/tests/shell_settings_window_test.py
python3 desktop/tests/theme_palette_test.py
# Uses the rebuilt Aether CLI with private configuration:
python3 desktop/tests/aether_palette_integration_test.py
python3 desktop/tests/locus_geometry_test.py
python3 desktop/tests/wallpaper_popup_test.py
python3 desktop/tests/notification_popup_test.py
# Requires the running Wayland compositor, using private temporary state:
python3 desktop/tests/locus_resize_wayland_test.py
```

The Qt 6 lint binary is `/usr/lib/qt6/bin/qmllint` on this system; the unqualified
`qmllint` command may resolve to the older Qt 5 parser.


## 12. Surface effects and centered Locus

The Panels and Locus pages each have a **Background opacity** slider and a
**Blur background** switch. Opacity changes only the card fill, preserving text,
icons, borders, and controls. **Reset to theme** follows the current Aether
panel-background alpha again. These settings save immediately on this machine;
the color editor's Apply and blueprint Save actions do not store them.

`settings.json` retains version 1 and adds nullable `panelOpacity` /
`locusOpacity` (null follows the theme; otherwise 0–1) and boolean `panelBlur` /
`locusBlur` (default false). Older settings load these defaults. Section resets
also clear that section's effects overrides.

`SurfaceEffects.qml` resolves background alpha and supplies a rounded region
for the native `Quickshell.Wayland.BackgroundEffect` attached property. Only the
visible card requests blur, using the compositor's existing strength. The region tracks reveal scaling and translation explicitly, since the native
region item does not observe transform-only changes. Hidden, disabled, and
fully opaque surfaces remove the request. The wallpaper window
switches its region to the editor card while editing. No desktop captures,
blur shaders, polling, or global Hyprland rule changes are introduced. On a
compositor without the background-effect protocol, opacity still works.

Locus now positions itself at `(screen height - rendered card height) / 2`.
It stays centered during automatic sizing, Settings changes, and top/bottom or
corner resizing, with screen bounds retained. Vertical grips resize about the
center just like the horizontal grips.

Additional real-compositor regression check (temporary isolated surfaces):

```sh
python3 desktop/tests/surface_effects_wayland_test.py
```

Performance audit regression checks (private state and D-Bus sessions where needed):

```sh
python3 desktop/tests/notification_prune_test.py
python3 desktop/tests/notification_watch_batch_test.py
python3 desktop/tests/network_status_test.py
python3 desktop/tests/network_status_lifecycle_test.py
python3 desktop/tests/ai_worker_test.py
python3 desktop/tests/ai_service_test.py
python3 desktop/tests/wallpaper_service_test.py
```
