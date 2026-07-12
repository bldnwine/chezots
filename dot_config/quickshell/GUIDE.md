Quickshell configurations require strict adherence to native Qt 6 QML structural properties, layout scoping axioms, and custom window wrapper APIs to prevent $0\times0$ pixel rendering errors and compilation failures.

```markdown
# Quickshell v0.3.0 Reference Manual & LLM Knowledge Base

## 1. Directory Structure & Entrypoint Initialization

* **Default Path:** Entrypoint logic must reside within `~/.config/quickshell/shell.qml`.
* **Root Primitive Constraint:** The configuration entrypoint file must declare exactly one top-level component of type `ShellRoot`. No other visual or programmatic block can encapsulate the configuration.

### Compilation Pragmas
Pragmas must precede all `import` keywords at the absolute top of the entrypoint file:
* `//@ pragma UseQApplication`: Replaces the default `QGuiApplication` with a full `QApplication` context, required for complex text widgets, platform theme plugins, or advanced icon rendering styling.
* `//@ pragma Env KEY=VALUE`: Sets background environment variables inside the engine context prior to compilation (e.g., `//@ pragma Env QS_NO_RELOAD_POPUP=1`).

---

## 2. Window Primitive Types & Positioning Mechanics

Quickshell replaces default Qt `Window` primitives with layer-surface abstractions designed for Wayland environments.

### PanelWindow (Bars, Status Overlays, Docks)
* **`anchors` Property:** Controlled via explicit boolean flags rather than bitmasks. Attach windows to display boundaries using directional flags:
  ```qml
  anchors { top: true; left: true; right: true } // Pin to the top edge across the span

```

* **`exclusionMode` Property:** Controls how the surface restricts desktop workspace layout regions for standard application windows:
* `ExclusionMode.Auto`: Default. Dynamically computes reserved zones based on component margins and window dimensions.
* `ExclusionMode.Normal`: Manually forces a defined exclusion box via the `exclusiveZone` integer field.
* `ExclusionMode.Ignore`: Surface overlaps with standard windows without reserving grid space.



### FloatingWindow & PopupWindow

* **`FloatingWindow`:** Instantiates a decorationless application surface that is unanchored to global monitor grid restrictions.
* **`PopupWindow`:** Instantiates transient context views (menus, tooltips) that reposition dynamically via `popupAdjustment` masks to counter screen viewport overflows.

---

## 3. Multi-Monitor Replication & Scoping

Do not hardcode pixel layouts or screen metrics. Multi-monitor setups must be generated dynamically using the `Quickshell.screens` reactive model tracking hotplug states.

### Canonically Replicating Screens with Variants

The `Variants` type automatically replicates a window configuration context for every display tracked by the system engine.

```qml
import QtQuick
import Quickshell

ShellRoot {
    Variants {
        model: Quickshell.screens
        
        delegate: PanelWindow {
            // Context mapping constraint
            property var modelData
            screen: modelData
            
            anchors { top: true; left: true; right: true }
            implicitHeight: 30
            color: "#11111b"

            Text {
                anchors.centerIn: parent
                text: "Monitor Index: " + parent.screen.name
                color: "#cdd6f4"
            }
        }
    }
}

```

---

## 4. Layout & Geometry Constraints

Mixing incompatible layout constraints breaks spatial layouts, rendering items at zero dimensions ($0\times0$ px).

* **Axis Conflict Rule:** Do not declare explicit dimensions (`width`, `height`), fixed coordinates (`x`, `y`), and relational properties (`anchors.fill: parent`) simultaneously over a common spatial vector.
* **Positioner Bounds Rule:** Children instantiated inside structural flow positioners (`Row`, `Column`) must define an explicit manual metric (`width`/`height`) or return a computed fallback metric (`implicitWidth`/`implicitHeight`). Do not use `anchors.fill: parent` inside items assigned to a flow positioner. Use `Layout.fillWidth: true` from `QtQuick.Layouts` if flexible distribution is required.
* **Structural Hygiene:** Do not declare an empty `Rectangle` component solely to frame child coordinates; use an empty `Item` block to save thread computation cycles.

---

## 5. Built-in API & Native System Operations

Quickshell embeds a non-blocking asynchronous interaction plane to pull state parameters without causing UI thread latency.

* **`Quickshell.env(variable: string)`**: Returns environment values assigned to the execution thread; yields `null` on an invalid key lookup.
* **`Quickshell.execDetached(string_array)`**: Spawns isolated shell subprocesses asynchronously. Complex chains require an explicit shell environment invocation string wrapper:
```qml
Quickshell.execDetached(["bash", "-c", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"])

```


* **`SystemClock`**: An internally optimized timer designed for background updates. Use it instead of custom standard JavaScript `Timer` items to minimize render stalling.
```qml
SystemClock { id: globalClock; interval: 1000 }
Text { text: Qt.formatDateTime(globalClock.currentTime, "hh:mm") }

```



---

## 6. Engineering Gotchas & Anti-Patterns

* **Wayland Clipboard Boundary:** Accessing string sequences via `Quickshell.clipboardText` evaluates as empty under Wayland security protocols *unless* a Quickshell-owned surface actively holds keyboard focus.
* **Duplicate Object IDs:** Never use hardcoded string `id` attributes inside components nested within `Variants` or `ObjectRepeater` delegates. This triggers runtime scope inheritance collisons across screens. Map lookups relatively via properties like `parent` or context indices.
* **Process Scraping Loop Stalls:** Do not query system configurations dynamically by invoking continuous background bash loops inside `Timer` structures. Use native programmatic layers, such as `Quickshell.Services.Pipewire` for audio structures, `Quickshell.Hyprland` for window hooks, and `Quickshell.Services.Notifications` for system banner events.

```

---

## 7. Additional Info

### 7a. Process + StdioCollector (background probes)

The most common pattern for polling system state. `Process` runs a command and feeds stdout into a collector. An attached `Timer` re-triggers it on an interval.

```qml
Process {
    id: myProbe
    running: false
    command: ["bash", "-lc", "your-shell-command"]   // array, not a string
    stdout: StdioCollector {
        onStreamFinished: {
            // this.text = full stdout after process exits
            doSomething(this.text.trim());
        }
    }
    // Alternative: SplitParser for streaming per-line
    stdout: SplitParser {
        splitMarker: "\n"
        onRead: (data) => { parseLine(data.trim()) }
    }
}
// Timer to re-fire the probe:
Timer {
    interval: 5000; running: true; repeat: true
    triggeredOnStart: true
    onTriggered: { myProbe.running = false; myProbe.running = true }
}
```

Key rules:
* `command` is a string **array** — no shell expansion. Use `["bash", "-lc", cmd]` for pipes, redirects, `$()`.
* Trigger by toggling `running = false` then `running = true`.
* `StdioCollector.onStreamFinished` fires once when the process exits. `this.text` has the full output.
* `SplitParser` fires `onRead(data)` per chunk delimited by `splitMarker`. Trailing newlines become part of the data — call `.trim()`.

### 7b. CardWindow overlay popup

A reusable centered popup window used by every overlay (aether, display, weather, screenshots). It renders as a full-screen transparent `PanelWindow` + `WlrLayershell` (Overlay layer, Exclusive keyboard focus) with a centered card that scales in/out.

```qml
CardWindow {
    theme: root       // provides .bg .sep .ink .inkDeep .seal .mono .cornerRadius
    revealed: root.someVisibility
    cardWidth: 460
    title: "TITLE"                    // rendered in mono caps
    subtitle: { /* dynamic string */ }
    footer: "KEYBOARD SHORTCUT HINTS" // shown at the bottom
    onDismiss: { root.someVisible = false }   // ESC or click-outside
    onKeyPressed: function(event) {
        // Handle keyboard navigation inside the popup
        // ESC is handled by CardWindow itself before this fires
    }
    // Body goes as the default child:
    Column { ... }
}
```

Dismiss triggers: click the transparent overlay outside the card, or press ESC. Keyboard focus is exclusive while revealed — keystrokes don't leak to other windows.

### 7c. Theme / root re-export pattern

A central `Item` (typically named `nav` in `Navbar.qml`) re-exports theme colors and holds all shared state. Children receive it via `required property var root`.

```qml
// Navbar.qml
Item {
    required property var theme
    readonly property color ink: theme.ink
    readonly property color seal: theme.seal
    readonly property color inkDeep: theme.inkDeep
    // ... shared functions, IPC handlers, popup instances
    SomePopup { root: nav }
}
// SomePopup.qml
Item {
    required property var root
    color: root.bg
    Text { color: root.ink }
    MouseArea { onClicked: root.someFunction() }
}
```

### 7d. Inter-process communication (IPC)

Quickshell instances can talk to each other via `IpcHandler`. Useful for toggling popups from external keybinds without spawning a new process.

```qml
IpcHandler {
    target: "my-thing"
    function toggle(): void { /* show/hide */ }
    function open(): void    { /* show */ }
    function close(): void   { /* hide */ }
}
```

From the shell: `qs ipc call my-thing toggle`. This sends the call to the running instance and exits — zero new memory.

### 7e. CLI flags for config selection

```
qs                                # ~/.config/quickshell/shell.qml
qs -c myconfig                    # ~/.config/quickshell/myconfig/shell.qml
qs -p path/to/file.qml            # arbitrary QML file
qs -p file.qml --no-duplicate     # exit immediately if already running
```

`--no-duplicate` is critical for keybinds that fire multiple times — the second press is a no-op instead of spawning another process.

### 7f. Component registration via qmldir

A `qmldir` file in the config directory registers QML files as importable components:

```
MyWidget 1.0 MyWidget.qml
CardWindow 1.0 CardWindow.qml
```

Then `MyWidget { }` works anywhere in the same config. Without `qmldir`, the file is still resolvable if it lives in the same directory as the importing file — but explicit registration is preferred for reuse across subdirectories.

### 7g. Image memory: always set `sourceSize`

Without `sourceSize`, Qt decodes the full source file dimensions into memory even when the rendered size is tiny. A 1920×1080 wallpaper decoded for a 48×27 thumbnail wastes ~6 MB per image.

```qml
Image {
    source: "file://" + path
    sourceSize.width: 64   // decode at ~64 px wide
    sourceSize.height: 36
    asynchronous: true     // don't block the UI thread
    cache: true            // reuse the decoded texture
    fillMode: Image.PreserveAspectCrop
}
```

Always set `sourceSize` to roughly 2× the rendered size — enough for sharpness on HiDPI, zero waste on memory.
