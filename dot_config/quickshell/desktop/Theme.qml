import QtQuick
import Quickshell
import Quickshell.Io
import "Palette.js" as Palette

// `seal` rides `driftAmount` (200ms rise, 2.8s taper) so each theme swap
// reads as a breath rather than a hard cut. The 1.55s lead-in lets
// theme-wash's animation exit first.
Item {
    id: theme

    readonly property string colorsPath: Quickshell.env("HOME") + "/.config/aether/theme/colors.toml"

    // Our own persisted round/sharp toggle. Flipped from the omni menu
    // (or any client) via the `corners` IpcHandler below. We don't read
    // omarchy's walker.css because that file is rewritten by a buggy
    // script and would drift out of sync with what we actually rendered.
    readonly property string cornerStatePath: Quickshell.env("HOME") + "/.local/state/quickshell-desktop/corners"
    property int cornerRadius: 0
    readonly property bool round: cornerRadius > 0

    function setCorners(mode) {
        const want = (mode === "round" || mode === true || mode === 6) ? 6 : 0;
        theme.cornerRadius = want;
        cornerWriter.command = ["bash", "-c",
            "mkdir -p " + JSON.stringify(theme.cornerStatePath.replace(/\/[^/]+$/, ""))
            + " && printf '%s' " + JSON.stringify(want === 6 ? "round" : "sharp")
            + " > " + JSON.stringify(theme.cornerStatePath)];
        cornerWriter.running = false;
        cornerWriter.running = true;
    }
    function toggleCorners() { theme.setCorners(theme.round ? "sharp" : "round"); }

    property color paper:   "#181616"
    property color ink:     "#c5c9c5"
    property color inkDeep: "#c8c093"
    property color sumi:    "#a6a69c"
    property color indigo:  "#658594"
    property color green:   "#a9b665"
    property color sealRaw: "#c4746e"
    property real  driftAmount: 0

    readonly property color seal: Qt.hsva(
        sealRaw.hsvHue,
        Math.min(1, sealRaw.hsvSaturation + driftAmount * 0.05),
        sealRaw.hsvValue,
        sealRaw.a
    )

    readonly property string serif: "serif"
    readonly property string mono:  "JetBrainsMono Nerd Font"

    readonly property color bg:     Qt.rgba(paper.r, paper.g, paper.b, 0.94)
    readonly property color fg:     ink
    readonly property color muted:  sumi
    readonly property color accent: seal
    readonly property color warn:   seal
    readonly property color sep:    Qt.rgba(ink.r, ink.g, ink.b, 0.18)
    readonly property color rowHi:  Qt.rgba(ink.r, ink.g, ink.b, 0.06)
    readonly property color rowSel: Qt.rgba(seal.r, seal.g, seal.b, 0.18)

    // Name of the last theme applied via IPC. Used to suppress the drift
    // animation when the hook pushes the same theme twice or races the
    // startup FileView read.
    property string lastAppliedName: ""

    // watchChanges: false — `omarchy theme set` does an atomic rm+mv on
    // the theme dir, which would race an inotify watch. The hook tells us
    // when to reload instead.
    FileView {
        id: paletteFile
        path: theme.colorsPath
        watchChanges: true
        onLoaded: Palette.apply(theme, Palette.parse(paletteFile.text()))
    }

    // Local persistence: one-line file containing "round" or "sharp".
    // Read at startup so the toggle survives across logins. We read via a
    // Process (not FileView) because FileView's initial load races with
    // property assignment in some Quickshell builds, leaving cornerRadius
    // at its default of 0 even when the file says "round".
    Process { id: cornerWriter; running: false }
    Process {
        id: cornerReader
        running: true
        command: ["cat", theme.cornerStatePath]
        stdout: StdioCollector {
            onStreamFinished: {
                theme.cornerRadius = this.text.trim() === "round" ? 6 : 0;
            }
        }
        onExited: function(code) {
            // Missing file -> default sharp.
            if (code !== 0) theme.cornerRadius = 0;
        }
    }

    IpcHandler {
        target: "corners"
        function set(mode: string): void { theme.setCorners(mode); }
        function round(): void  { theme.setCorners("round"); }
        function sharp(): void  { theme.setCorners("sharp"); }
        function toggle(): void { theme.toggleCorners(); }
    }

    Timer {
        id: driftDelay
        interval: 1550
        repeat: false
        onTriggered: driftAnim.restart()
    }

    SequentialAnimation {
        id: driftAnim
        NumberAnimation {
            target: theme; property: "driftAmount"
            from: 0; to: 1
            duration: 200
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: theme; property: "driftAmount"
            to: 0
            duration: 2800
            easing.type: Easing.OutCubic
        }
    }

    IpcHandler {
        target: "theme"
        function apply(payload: string): void {
            let p;
            try { p = JSON.parse(payload); }
            catch (e) { console.warn("theme.apply: bad payload —", e); return; }
            if (!p || !p.colors) return;
            Palette.apply(theme, Palette.mapKeys(p.colors));
            if (p.name && p.name !== theme.lastAppliedName) {
                theme.lastAppliedName = p.name;
                driftDelay.restart();
            }
        }
        function reload(): void {
            paletteFile.reload();
            driftDelay.restart();
        }
    }
}
