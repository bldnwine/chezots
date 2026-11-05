import QtQuick
import Quickshell
import Quickshell.Io
import "Palette.js" as Palette

// `seal` rides `driftAmount` (200ms rise, 2.8s taper) so each theme swap
// reads as a breath rather than a hard cut. The 1.55s lead-in lets
// theme-wash's animation exit first.
Item {
    id: theme

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property string colorsPath: configHome + "/aether/theme/quickshell.json"
    readonly property string legacyColorsPath: configHome + "/aether/theme/colors.toml"
    property var settings: null
    property bool dedicatedPresent: true
    property string paletteError: ""
    property string paletteRevision: ""
    property string paletteSignature: ""
    property var appliedPalette: ({paper:"#181616", ink:"#c5c9c5", inkDeep:"#c8c093", sumi:"#a6a69c",
        indigo:"#658594", green:"#a9b665", sealRaw:"#c4746e"})
    property var previewColors: null
    readonly property var renderedPalette: Palette.complete(previewColors || appliedPalette)
    signal paletteCommitted()

    function previewPalette(colors) {
        for (const key of Palette.ROLES) if (!Palette.validColor(colors[key])) return;
        previewColors = Palette.complete(colors);
    }
    function cancelPreview() { previewColors = null; }
    function acceptPalette(colors, revision) {
        const next = Palette.complete(Object.assign({}, appliedPalette, colors));
        const nextRevision = revision === undefined ? paletteRevision : String(revision);
        const signature = nextRevision + JSON.stringify(next);
        if (signature === paletteSignature) return;
        appliedPalette = next;
        paletteRevision = nextRevision;
        paletteSignature = signature;
        previewColors = null;
        paletteError = "";
        paletteCommitted();
    }
    function reloadPalette() { paletteFile.reload(); }

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

    readonly property color paper:   Palette.qmlColor(renderedPalette.paper)
    readonly property color ink:     Palette.qmlColor(renderedPalette.ink)
    readonly property color inkDeep: Palette.qmlColor(renderedPalette.inkDeep)
    readonly property color sumi:    Palette.qmlColor(renderedPalette.sumi)
    readonly property color indigo:  Palette.qmlColor(renderedPalette.indigo)
    readonly property color green:   Palette.qmlColor(renderedPalette.green)
    readonly property color sealRaw: Palette.qmlColor(renderedPalette.sealRaw)
    property real  driftAmount: 0

    readonly property color seal: Qt.hsva(
        sealRaw.hsvHue,
        Math.min(1, sealRaw.hsvSaturation + driftAmount * 0.05),
        sealRaw.hsvValue,
        sealRaw.a
    )

    readonly property string serif: "serif"
    readonly property string mono:  "Google Sans Flex"

    readonly property color bg:     Palette.qmlColor(renderedPalette.bg)
    readonly property color fg:     ink
    readonly property color muted:  sumi
    readonly property color accent: seal
    readonly property color warn:   Palette.qmlColor(renderedPalette.warn)
    readonly property color sep:    Palette.qmlColor(renderedPalette.sep)
    readonly property color rowHi:  Palette.qmlColor(renderedPalette.rowHi)
    readonly property color rowSel: Palette.qmlColor(renderedPalette.rowSel)

    // Name of the last theme applied via IPC. Used to suppress the drift
    // animation when the hook pushes the same theme twice or races the
    // startup FileView read.
    property string lastAppliedName: ""

    // File notifications and explicit push hooks share one validated resolver.
    FileView {
        id: paletteFile
        path: theme.colorsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            theme.dedicatedPresent = true;
            try {
                const document = Palette.decode(text());
                theme.acceptPalette(document.colors, document.revision);
            } catch (error) { theme.paletteError = String(error); console.warn(theme.paletteError); }
        }
        onLoadFailed: function(error) {
            theme.dedicatedPresent = error !== FileViewError.FileNotFound;
            if (!theme.dedicatedPresent) legacyFile.reload();
            else theme.paletteError = "Could not read the Quickshell palette; keeping the last valid colors";
        }
    }
    FileView {
        id: legacyFile
        path: theme.legacyColorsPath
        printErrors: false
        onLoaded: {
            if (theme.dedicatedPresent) return;
            const parsed = Palette.parse(text());
            if (Object.keys(parsed).length) theme.acceptPalette(Palette.complete(parsed), "legacy");
        }
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
        function set(mode: string) { theme.setCorners(mode); }
        function round()  { theme.setCorners("round"); }
        function sharp()  { theme.setCorners("sharp"); }
        function toggle() { theme.toggleCorners(); }
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
        function apply(payload: string) {
            let p;
            try { p = JSON.parse(payload); }
            catch (e) { console.warn("theme.apply: bad payload —", e); return; }
            if (!p || !p.colors) return;
            if (theme.dedicatedPresent) theme.reloadPalette();
            else if (p.version === 1) {
                try { const document = Palette.decode(payload); theme.acceptPalette(document.colors, document.revision); }
                catch (error) { console.warn(String(error)); return; }
            } else theme.acceptPalette(Palette.complete(Palette.mapKeys(p.colors)), "legacy");
            if (p.name && p.name !== theme.lastAppliedName) {
                theme.lastAppliedName = p.name;
                driftDelay.restart();
            }
        }
        function reload() {
            theme.reloadPalette();
            driftDelay.restart();
        }
    }
}

