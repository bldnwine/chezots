import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Hyprland

// Omarchy top bar. Owns the per-bar state, probes, and IPC; per-feature
// surfaces (Bar, *Popup, TooltipOverlay) and widgets (Module, Workspace,
// Bloom, …) read from `root` via `root: root` injection. Palette comes
// from the shared Theme; colours are re-exposed on root so sibling files
// keep their `root.paper` bindings.
Item {
    id: root

    required property var theme

    readonly property color paper:   theme.paper
    readonly property color ink:     theme.ink
    readonly property color inkDeep: theme.inkDeep
    readonly property color sumi:    theme.inkDeep
    readonly property color indigo:  theme.indigo
    readonly property color green:   theme.green
    readonly property color seal:    theme.seal
    readonly property color bg:      theme.bg
    readonly property color fg:      theme.fg
    readonly property color muted:   theme.muted
    readonly property color accent:  theme.accent
    readonly property color warn:    theme.warn
    readonly property color sep:     theme.sep

    readonly property string serif: theme.serif
    readonly property string mono:  theme.mono

    readonly property int  cornerRadius: theme.cornerRadius
    readonly property bool round:        theme.round

    // Wired in desktop/shell.qml to the sibling OmniMenu's toggle().
    signal paletteToggleRequested()

    // Kanji numerals 〇 一 二 ... 十.
    readonly property var kanjiNum: ["〇","一","二","三","四","五","六","七","八","九","十"]
    function indexKanji(n) { return n >= 0 && n <= 10 ? kanjiNum[n] : String(n); }

    // BMP Private Use Area icons; written via fromCodePoint so the source
    // stays ASCII-safe.
    readonly property string icoOmarchy: String.fromCodePoint(0xe900)
    readonly property string icoBtOn:    String.fromCodePoint(0xf294)
    readonly property string icoVol1:    String.fromCodePoint(0xf026)
    readonly property string icoVol2:    String.fromCodePoint(0xf027)
    readonly property string icoVol3:    String.fromCodePoint(0xf028)

    readonly property string icoMute:    String.fromCodePoint(0xeee8)
    readonly property string icoCamera:  String.fromCodePoint(0xf0100)
    readonly property string icoRefresh: String.fromCodePoint(0xf0450)
    readonly property string icoDisplay: String.fromCodePoint(0xf0379)
    readonly property string icoPower:   String.fromCodePoint(0xf0425)
    readonly property string icoAether:  String.fromCodePoint(0xf03d8)
    readonly property string icoFilm:    String.fromCodePoint(0xf0231)
    readonly property string icoSearch:  String.fromCodePoint(0xf0349)
    readonly property string icoUpdate:  String.fromCodePoint(0xf021)
    readonly property string icoPlug:    String.fromCodePoint(0xf06a5)
    readonly property string icoMusic:     String.fromCodePoint(0xf001)
    readonly property string icoPause:     String.fromCodePoint(0xf04c)
    readonly property string icoHeadphone: String.fromCodePoint(0xf025)

    readonly property int barHeight: 26
    readonly property string aetherBin: "/home/bldnwine/aethergo/build/bin/aether"
    readonly property string pushThemeScript: Quickshell.env("HOME") + "/.config/quickshell/scripts/aether-push-theme.sh"

    // ---------- Edge ----------
    // Drives bar anchors, internal Row/Column flow, and where the toggle
    // arrow points.
    property string barEdge: "top"
    readonly property bool isHorizontal: barEdge === "top" || barEdge === "bottom"

    function cycleBarEdge() {
        const edges = ["top", "right", "bottom", "left"];
        root.barEdge = edges[(edges.indexOf(root.barEdge) + 1) % 4];
    }

    function edgeArrow() {
        return ({top: "↑", right: "→", bottom: "↓", left: "←"})[root.barEdge] || "?";
    }

    // ---------- Bar variant ----------
    // Which bar face is rendered. "zen" is the original 静 minimalist bar;
    // "hackerman" is the tactical/terminal readout; "whiterose" is a plain
    // black-and-white editorial bar. All surfaces are always instantiated below and gate on this
    // string via `visible`; an unmapped layer-surface reserves no exclusive
    // zone, so exactly one bar owns the edge at a time.
    //
    // Persisted to its own one-line state file (same scheme as Theme's
    // corner toggle) so the choice survives a relogin. Read once at startup
    // via cat — a FileView's initial load races property assignment in some
    // Quickshell builds and can clobber the value back to the default.
    readonly property var barVariants: ["zen", "hackerman", "whiterose"]
    readonly property string barVariantStatePath:
        Quickshell.env("HOME") + "/.local/state/quickshell-desktop/bar-variant"
    property string barVariant: "zen"

    function setBarVariant(name) {
        const want = root.barVariants.indexOf(name) !== -1 ? name : "zen";
        root.barVariant = want;
        barVariantWriter.command = ["bash", "-lc",
            "mkdir -p " + JSON.stringify(root.barVariantStatePath.replace(/\/[^/]+$/, ""))
            + " && printf '%s' " + JSON.stringify(want)
            + " > " + JSON.stringify(root.barVariantStatePath)];
        barVariantWriter.running = false;
        barVariantWriter.running = true;
    }
    function cycleBarVariant() {
        const i = root.barVariants.indexOf(root.barVariant);
        root.setBarVariant(root.barVariants[(i + 1) % root.barVariants.length]);
    }

    Process { id: barVariantWriter; running: false }
    Process {
        id: barVariantReader
        running: true
        command: ["cat", root.barVariantStatePath]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = this.text.trim();
                if (root.barVariants.indexOf(v) !== -1) root.barVariant = v;
            }
        }
        // Missing file -> keep the "zen" default.
        onExited: function(code) { if (code !== 0) root.barVariant = "zen"; }
    }

    // ---------- Tooltips ----------
    // A single overlay panel reads these and renders the label near the
    // hovered icon. Positions are bar-window-local; the overlay translates
    // them into its own (full-screen) coordinate space based on barEdge.
    property string tooltipText: ""
    property real   tooltipBarX: 0
    property real   tooltipBarY: 0
    property bool   tooltipShown: false

    function showTooltip(text, x, y) {
        if (!text) return;
        root.tooltipText  = text;
        root.tooltipBarX  = x;
        root.tooltipBarY  = y;
        root.tooltipShown = true;
    }

    function hideTooltip(text) {
        root.tooltipShown = false;
    }

    // ---------- Popup anchor ----------
    // Bar-window-local coordinates, the same coordinate space the tooltip
    // overlay consumes — both surfaces are full-edge PanelWindows so the
    // bar-local point translates 1:1.
    property real popupAnchorX: 0
    property real popupAnchorY: 0

    // Bar registers its trigger Items here so openCalendar/Weather/Display
    // can re-anchor on every open — including IPC opens from OmniMenu that
    // don't go through a click handler.
    property Item calendarAnchorItem: null
    property Item weatherAnchorItem:  null
    property Item displayAnchorItem:  null
    property Item systemAnchorItem:   null

    function anchorPopupTo(item) {
        const p = item.mapToItem(null, item.width / 2, item.height / 2);
        root.popupAnchorX = p.x;
        root.popupAnchorY = p.y;
    }

    // ---------- State ----------
    property int activeWs: 1
    property var existingWs: {
        const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        const wsIds = new Set();
        for (const t of toplevels) {
            if (t && t.workspace && t.workspace.id !== undefined) {
                const id = t.workspace.id;
                if (id > 0 && id <= 10) wsIds.add(id);
            }
        }
        return [...wsIds].sort((a, b) => a - b);
    }
    // +1 = user navigated to a higher-numbered workspace (rightward along
    // the bar), -1 = lower-numbered (leftward), 0 = no recent travel. The
    // active Workspace cell reads this to bias its kanji's entry offset.
    property int lastDirection: 0

    // ---------- Workspace state (reactive via Hyprland IPC) ----------
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            if (!Hyprland.focusedWorkspace) return;
            const next = Hyprland.focusedWorkspace.id;
            if (next > root.activeWs) root.lastDirection = 1;
            else if (next < root.activeWs) root.lastDirection = -1;
            root.activeWs = next;
        }
    }

    property int cpuVal: 0
    property int memVal: 0
    property int batVal: 0
    property string batState: "Unknown"
    // Instantaneous power draw in watts; magnitude only — direction is in batState.
    property real batPower: 0
    property bool batPresent: false

    property string netIcon: "󰤯"
    property string netKind: "none"   // "eth" | "wifi" | "none"
    property string wifiSsid: ""
    property int    wifiSignal: 0

    // Wi-Fi scan state for the Quick panel. `wifiNetworks` is a list of
    // {ssid, signal, security, inUse} sorted desc by signal. Driven by
    // nmcli; populated on demand by refreshWifi().
    property var    wifiNetworks: []
    property bool   wifiRadioOn: true
    property bool   wifiScanning: false
    property string _wifiNetworksSer: ""

    // iwd-based: omarchy uses iwctl, not nmcli. The probe detects the
    // first station-mode device dynamically so multi-radio laptops work.
    function refreshWifi() {
        if (wifiScanProbe.running) return;
        root.wifiScanning = true;
        wifiScanProbe.running = false;
        wifiScanProbe.running = true;
    }
    function connectWifi(ssid) {
        if (!ssid) return;
        // Saved networks reconnect silently. New networks need a passphrase
        // which we can't prompt for inside Quickshell — for those, the user
        // has to run `iwctl` once manually. After a successful connect the
        // post-action timer re-probes so the inUse flag flips.
        root.run("DEV=$(iwctl --dont-ask device list 2>/dev/null"
                 + " | sed 's/\\x1b\\[[0-9;]*m//g'"
                 + " | awk '/station/{print $1; exit}');"
                 + " [ -n \"$DEV\" ] && iwctl --dont-ask station \"$DEV\" connect "
                 + JSON.stringify(ssid));
        wifiPostConnectTimer.restart();
    }
    function disconnectWifi() {
        root.run("DEV=$(iwctl --dont-ask device list 2>/dev/null"
                 + " | sed 's/\\x1b\\[[0-9;]*m//g'"
                 + " | awk '/station/{print $1; exit}');"
                 + " [ -n \"$DEV\" ] && iwctl --dont-ask station \"$DEV\" disconnect");
        wifiPostConnectTimer.restart();
    }
    function toggleWifiRadio() {
        const target = root.wifiRadioOn ? "off" : "on";
        root.wifiRadioOn = !root.wifiRadioOn;
        root.run("DEV=$(iwctl --dont-ask device list 2>/dev/null"
                 + " | sed 's/\\x1b\\[[0-9;]*m//g'"
                 + " | awk '/^[[:space:]]+[a-z][a-z0-9]+/{print $1; exit}');"
                 + " [ -n \"$DEV\" ] && iwctl --dont-ask device \"$DEV\" set-property Powered " + target);
        wifiPostConnectTimer.restart();
    }
    Timer {
        id: wifiPostConnectTimer
        interval: 800
        repeat: false
        onTriggered: root.refreshWifi()
    }
    property string btIcon:  String.fromCodePoint(0xf294)
    property bool   btPowered: false
    property int    btCount: 0
    // Bluetooth device list for the Quick panel. Each entry:
    // { mac, name, connected, paired, trusted }.
    property var    btDevices: []
    property bool   btScanning: false
    property string _btDevicesSer: ""

    function refreshBluetooth() {
        if (btDevicesProbe.running) return;
        btDevicesProbe.running = false;
        btDevicesProbe.running = true;
    }
    // bluez-tools path (omarchy ships bt-adapter / bt-device, not the
    // bluetoothctl utility). Same semantics as before, different CLI.
    function btConnect(mac) {
        if (!mac) return;
        root.run("bt-device --connect " + mac);
        btPostActionTimer.restart();
    }
    function btDisconnect(mac) {
        if (!mac) return;
        root.run("bt-device --disconnect " + mac);
        btPostActionTimer.restart();
    }
    function btTogglePower() {
        root.btPowered = !root.btPowered;
        root.run("bt-adapter -s Powered " + (root.btPowered ? 1 : 0));
        btPostActionTimer.restart();
    }
    function btToggleScan() {
        root.btScanning = !root.btScanning;
        // `bt-adapter -d --timeout N` blocks for N seconds while
        // discovering, so fork it off and let the refresh probe pick up
        // any new devices it surfaces.
        if (root.btScanning) {
            root.run("setsid -f bt-adapter -d --timeout 15 >/dev/null 2>&1");
            btScanStopTimer.restart();
        }
        btPostActionTimer.restart();
    }
    Timer {
        id: btPostActionTimer
        interval: 600
        repeat: false
        onTriggered: root.refreshBluetooth()
    }
    Timer {
        // Clear the "scanning" flag once the bluetoothctl --timeout expires.
        id: btScanStopTimer
        interval: 15000
        repeat: false
        onTriggered: root.btScanning = false
    }
    property string audioIcon: ""
    property string audioDevType: "spk"
    property string audioSinkDesc: ""
    property int    audioVol: 0
    property bool   audioMuted: false
    // List of PipeWire/Pulse output sinks with the current default flagged.
    // Each entry: { id, name, description, isDefault }. Populated by the
    // audioSinks probe on demand (refreshed when the Audio quick panel opens).
    property var    audioSinks: []
    property string audioDefaultSink: ""
    property string _audioSinksSer: ""

    function setDefaultSink(id) {
        if (!id) return;
        root.audioDefaultSink = id;
        root.run("wpctl set-default " + id);
        // Re-probe so the badge re-evaluates after wpctl applies.
        audioSinksProbe.running = false;
        audioSinksProbe.running = true;
    }
    function refreshAudioSinks() {
        audioSinksProbe.running = false;
        audioSinksProbe.running = true;
    }

    // power-profiles-daemon's current profile, if available. Empty when
    // powerprofilesctl isn't installed or no profile is set — keeps the
    // Quick detail panel's selector hidden in that case.
    property string powerProfile: ""
    property var    powerProfiles: []  // list of available profiles

    function setPowerProfile(name) {
        if (!name) return;
        root.powerProfile = name;
        root.run("powerprofilesctl set " + name);
        // Re-probe so the chip reflects the daemon's actual state in
        // case it rejected the request (e.g. on AC-only machines).
        powerProfileRefreshTimer.restart();
    }
    Timer {
        id: powerProfileRefreshTimer
        interval: 400
        repeat: false
        onTriggered: root.refreshPowerProfile()
    }

    // omarchy-update-available exits 0 when the local omarchy clone is
    // behind the latest tag. The bar surfaces a small refresh glyph next
    // to the battery for as long as that's the case; click → launch the
    // floating update terminal.
    property bool   omarchyUpdateAvailable: false
    property string omarchyLatestTag: ""

    function openOmarchyUpdate() {
        root.run("omarchy-launch-floating-terminal-with-presentation omarchy-update");
    }
    function refreshOmarchyUpdateCheck() {
        omarchyUpdateProbe.running = false;
        omarchyUpdateProbe.running = true;
    }

    property string hh: "--"
    property string mm: "--"
    property string dd: "--"
    property string mon: "---"
    property string dow: "--"

    // ---------- Screenshots popup state ----------
    property bool screenshotsVisible: false
    property int screenshotPage: 0
    readonly property int screenshotsPerPage: 12
    property var screenshotFiles: []
    property int selectedScreenshot: -1

    function openScreenshots() {
        root.screenshotPage = 0;
        root.selectedScreenshot = 0;
        screenshotProbe.running = false;
        screenshotProbe.running = true;
        root.screenshotsVisible = true;
    }

    function refreshScreenshots() {
        screenshotProbe.running = false;
        screenshotProbe.running = true;
    }

    // Move selection by `delta` thumbs along the grid's reading order;
    // wraps across pages when stepping off either edge.
    function moveScreenshotSelection(delta) {
        if (root.screenshotFiles.length === 0) return;
        const visible = root.visibleScreenshots;
        const next = root.selectedScreenshot + delta;
        if (next < 0 && root.screenshotPage > 0) {
            root.screenshotPage--;
            root.selectedScreenshot = Math.min(
                root.screenshotsPerPage - 1,
                root.screenshotFiles.length - root.screenshotPage * root.screenshotsPerPage - 1
            );
        } else if (next >= visible.length && root.screenshotPage < root.screenshotPageCount - 1) {
            root.screenshotPage++;
            root.selectedScreenshot = 0;
        } else if (next >= 0 && next < visible.length) {
            root.selectedScreenshot = next;
        }
    }

    // Row step (±4). Stays within the current page.
    function moveScreenshotRow(delta) {
        const visible = root.visibleScreenshots;
        const next = root.selectedScreenshot + delta * 4;
        if (next >= 0 && next < visible.length) root.selectedScreenshot = next;
    }

    function pageScreenshots(delta) {
        const next = root.screenshotPage + delta;
        if (next >= 0 && next < root.screenshotPageCount) {
            root.screenshotPage = next;
            root.selectedScreenshot = 0;
        }
    }

    function formatScreenshotLabel(path) {
        const m = String(path).match(/screenshot-(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-\d{2}\.[A-Za-z0-9]+$/);
        if (m) return m[1] + " " + m[2] + ":" + m[3];
        const parts = String(path).split("/");
        return parts[parts.length - 1];
    }

    // Empty slice while the popup is hidden so the Repeater delegates'
    // Image bindings drop their sources and stop holding decoded thumbs.
    readonly property var visibleScreenshots: {
        if (!root.screenshotsVisible) return [];
        const start = root.screenshotPage * root.screenshotsPerPage;
        return root.screenshotFiles.slice(start, start + root.screenshotsPerPage);
    }

    readonly property var selectedScreenshotEntry:
        root.selectedScreenshot >= 0 ? (root.visibleScreenshots[root.selectedScreenshot] || null) : null

    readonly property int screenshotPageCount: {
        if (root.screenshotFiles.length === 0) return 1;
        return Math.ceil(root.screenshotFiles.length / root.screenshotsPerPage);
    }

    // ---------- Videos popup state ----------
    property bool videosVisible: false
    property int videoPage: 0
    readonly property int videosPerPage: 12
    property var videoFiles: []
    property int selectedVideo: -1

    function openVideos() {
        root.videoPage = 0;
        root.selectedVideo = 0;
        videoProbe.running = false;
        videoProbe.running = true;
        root.videosVisible = true;
    }

    function refreshVideos() {
        videoProbe.running = false;
        videoProbe.running = true;
    }

    function moveVideoSelection(delta) {
        if (root.videoFiles.length === 0) return;
        const visible = root.visibleVideos;
        const next = root.selectedVideo + delta;
        if (next < 0 && root.videoPage > 0) {
            root.videoPage--;
            root.selectedVideo = Math.min(
                root.videosPerPage - 1,
                root.videoFiles.length - root.videoPage * root.videosPerPage - 1
            );
        } else if (next >= visible.length && root.videoPage < root.videoPageCount - 1) {
            root.videoPage++;
            root.selectedVideo = 0;
        } else if (next >= 0 && next < visible.length) {
            root.selectedVideo = next;
        }
    }

    function moveVideoRow(delta) {
        const visible = root.visibleVideos;
        const next = root.selectedVideo + delta * 4;
        if (next >= 0 && next < visible.length) root.selectedVideo = next;
    }

    function pageVideos(delta) {
        const next = root.videoPage + delta;
        if (next >= 0 && next < root.videoPageCount) {
            root.videoPage = next;
            root.selectedVideo = 0;
        }
    }

    function formatVideoLabel(path) {
        const parts = String(path).split("/");
        return parts[parts.length - 1];
    }

    function formatVideoDuration(secs) {
        const s = Math.max(0, Math.floor(Number(secs) || 0));
        if (s <= 0) return "";
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const ss = s % 60;
        const pad = (n) => String(n).padStart(2, "0");
        return h > 0 ? (h + ":" + pad(m) + ":" + pad(ss))
                     : (m + ":" + pad(ss));
    }

    function formatVideoSize(bytes) {
        const b = Number(bytes) || 0;
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB";
        if (b >= 1048576)    return (b / 1048576).toFixed(0) + " MB";
        if (b >= 1024)       return (b / 1024).toFixed(0) + " KB";
        return b + " B";
    }

    function formatVideoMtime(secs) {
        if (!secs) return "";
        return Qt.formatDateTime(new Date(Number(secs) * 1000), "yyyy-MM-dd hh:mm");
    }

    readonly property var visibleVideos: {
        if (!root.videosVisible) return [];
        const start = root.videoPage * root.videosPerPage;
        return root.videoFiles.slice(start, start + root.videosPerPage);
    }

    readonly property var selectedVideoEntry:
        root.selectedVideo >= 0 ? (root.visibleVideos[root.selectedVideo] || null) : null

    readonly property int videoPageCount: {
        if (root.videoFiles.length === 0) return 1;
        return Math.ceil(root.videoFiles.length / root.videosPerPage);
    }

    // ---------- Aether popup state ----------
    // Lightweight quick-handle: a list of saved Aether blueprints with
    // colour-swatch previews. Click applies via `aether --apply-blueprint`,
    // so the heavy GUI only opens when explicitly requested.
    property bool aetherVisible: false
    property var  aetherBlueprints: []
    property int  selectedAether: -1
    property bool aetherLoading: false
    property string aetherQuery: ""

    // Case-insensitive substring filter on blueprint name. With 100+ saved
    // themes a small inline search is the only way to land on one in a
    // single keystroke or two.
    readonly property var aetherFiltered: {
        const q = root.aetherQuery.toLowerCase();
        if (q === "") return root.aetherBlueprints;
        return root.aetherBlueprints.filter(b =>
            String(b.name || "").toLowerCase().indexOf(q) !== -1
        );
    }

    function openAether() {
        root.aetherQuery = "";
        root.selectedAether = 0;
        refreshAetherBlueprints();
        root.aetherVisible = true;
    }
    // Re-runs the blueprints probe without surfacing the standalone
    // popup, so embedded views (Quick panel) can hydrate their cache
    // without doubling up the UI.
    function refreshAetherBlueprints() {
        root.aetherLoading = true;
        aetherProbe.running = false;
        aetherProbe.running = true;
    }

    function moveAetherSelection(delta, wrap) {
        const n = root.aetherFiltered.length;
        if (n === 0) { root.selectedAether = -1; return; }
        const cur = root.selectedAether < 0 ? 0 : root.selectedAether;
        let next = cur + delta;
        if (wrap) {
            next = ((next % n) + n) % n;
        } else {
            if (next < 0) next = 0;
            else if (next >= n) next = n - 1;
        }
        root.selectedAether = next;
    }

    function applyAetherBlueprint(name) {
        if (!name) return;
        themeApplier.command = ["bash", "-lc",
            root.aetherBin + " --apply-blueprint " + JSON.stringify(name)
            + " && " + root.pushThemeScript];
        themeApplier.running = false;
        themeApplier.running = true;
    }

    // Snap selection back to the top whenever the filter changes, so the
    // first match is always primed for Enter without a fresh j-press.
    onAetherQueryChanged: {
        root.selectedAether = root.aetherFiltered.length > 0 ? 0 : -1;
    }

    // ---------- Calendar popup state ----------
    property bool calendarVisible: false
    property int calendarMonthOffset: 0
    // Bumped on each open so the cells/title bindings below re-evaluate
    // (new Date() is opaque to QML's dependency tracker — touching this
    // int forces a recompute even when calendarMonthOffset is unchanged).
    property int calendarTick: 0

    // Easter Sunday for any Gregorian year via Butcher's anonymous algorithm.
    // Pure arithmetic, no loops; returns a Date in local time.
    function easterDate(year) {
        const a = year % 19;
        const b = Math.floor(year / 100);
        const c = year % 100;
        const d = Math.floor(b / 4);
        const e = b % 4;
        const f = Math.floor((b + 8) / 25);
        const g = Math.floor((b - f + 1) / 3);
        const h = (19 * a + b - d - g + 15) % 30;
        const i = Math.floor(c / 4);
        const k = c % 4;
        const l = (32 + 2 * e + 2 * i - h - k) % 7;
        const mm = Math.floor((a + 11 * h + 22 * l) / 451);
        const month = Math.floor((h + l - 7 * mm + 114) / 31);   // 3=Mar, 4=Apr
        const day = ((h + l - 7 * mm + 114) % 31) + 1;
        return new Date(year, month - 1, day);
    }

    // Norwegian red days. Caller passes precomputed `easter` (Date) so the
    // outer loop in calendarCells doesn't recompute it per day.
    function norwegianHoliday(year, month, day, easter) {
        if (month === 0  && day === 1)  return "Nyttårsdag";
        if (month === 4  && day === 1)  return "Arbeidernes dag";
        if (month === 4  && day === 17) return "Grunnlovsdagen";
        if (month === 11 && day === 25) return "Første juledag";
        if (month === 11 && day === 26) return "Andre juledag";

        const target = new Date(year, month, day);
        const offset = Math.round((target.getTime() - easter.getTime()) / 86400000);

        if (offset === -3) return "Skjærtorsdag";
        if (offset === -2) return "Langfredag";
        if (offset === 0)  return "Første påskedag";
        if (offset === 1)  return "Andre påskedag";
        if (offset === 39) return "Kristi himmelfartsdag";
        if (offset === 49) return "Første pinsedag";
        if (offset === 50) return "Andre pinsedag";

        return "";
    }

    readonly property var calendarCells: {
        root.calendarTick;  // forces recompute on same-month re-open
        const now = new Date();
        const first = new Date(now.getFullYear(), now.getMonth() + root.calendarMonthOffset, 1);
        const year = first.getFullYear();
        const month = first.getMonth();
        const lastDay = new Date(year, month + 1, 0).getDate();
        // Monday-first week: shift Sunday (0) to slot 6.
        const startDay = (first.getDay() + 6) % 7;
        const today = new Date();
        const isCurrentMonth = year === today.getFullYear() && month === today.getMonth();
        const easter = root.easterDate(year);
        const cells = [];
        for (let i = 0; i < startDay; i++) cells.push({day: 0, today: false, holiday: ""});
        for (let d = 1; d <= lastDay; d++) {
            cells.push({
                day: d,
                today: isCurrentMonth && d === today.getDate(),
                holiday: root.norwegianHoliday(year, month, d, easter)
            });
        }
        while (cells.length < 42) cells.push({day: 0, today: false, holiday: ""});
        return cells;
    }

    readonly property string calendarMonthName: {
        const months = ["JANUARY","FEBRUARY","MARCH","APRIL","MAY","JUNE",
                        "JULY","AUGUST","SEPTEMBER","OCTOBER","NOVEMBER","DECEMBER"];
        const now = new Date();
        return months[(now.getMonth() + root.calendarMonthOffset + 12000) % 12];
    }

    readonly property string calendarYear: {
        const now = new Date();
        const d = new Date(now.getFullYear(), now.getMonth() + root.calendarMonthOffset, 1);
        return String(d.getFullYear());
    }

    // Selected day-of-month within the displayed month; 0 = none. Reset
    // on month nav since the selection only makes sense within the
    // visible month.
    property int selectedDay: 0

    readonly property string selectedDayDetail: {
        if (root.selectedDay <= 0) return "";
        const days   = ["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"];
        const months = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"];
        const now = new Date();
        const d = new Date(now.getFullYear(), now.getMonth() + root.calendarMonthOffset, root.selectedDay);
        return days[d.getDay()] + " · " + root.selectedDay + " " + months[d.getMonth()] + " " + d.getFullYear();
    }

    readonly property string selectedDayHoliday: {
        if (root.selectedDay <= 0) return "";
        const cells = root.calendarCells;
        for (let i = 0; i < cells.length; i++) {
            if (cells[i].day === root.selectedDay) return cells[i].holiday;
        }
        return "";
    }

    function openCalendar() {
        if (root.calendarAnchorItem) root.anchorPopupTo(root.calendarAnchorItem);
        root.calendarMonthOffset = 0;
        root.calendarTick++;
        root.selectedDay = (new Date()).getDate();
        root.calendarVisible = true;
    }

    // ---------- Display popup state ----------
    // Held locally because hyprsunset has no `get` verb — we mirror values
    // so the slider tracks reflect what was last set, even across daemon
    // restarts.
    property bool  displayVisible: false
    property real  warmthK: 6500
    property int   brightnessPct: 100
    property real  gammaPct: 100
    property string monitorName: "eDP-1"
    property string monitorRes:  "2880x1800"
    property real  monitorRate:  60.0
    property real  monitorScale: 2.0
    readonly property var displayPresets: [
        { label: "DAY",     warmth: 6500, gamma: 100, bright: 100 },
        { label: "READING", warmth: 4500, gamma: 95,  bright: 60  },
        { label: "NIGHT",   warmth: 3000, gamma: 85,  bright: 30  },
        { label: "CANDLE",  warmth: 2000, gamma: 80,  bright: 15  }
    ]
    property int  selectedPreset: 0
    // ↑/↓ moves; ←/→ nudges sliders (0..2) or cycles the preset row (3).
    // Rows 4..6 are EDIT / BLANK / RESET — Enter activates.
    property int  displayRow: 0

    // First hyprsunset call spawns the daemon and waits for its socket; on
    // every later call the prelude collapses to a single pgrep test. Track
    // success so we can skip even that after one confirmed reply.
    property bool sunsetReady: false
    readonly property string ensureSunset:
        "pgrep -x hyprsunset >/dev/null"
        + " || { uwsm app -- hyprsunset --gamma_max 200 >/dev/null 2>&1 &"
        + "      for i in 1 2 3 4 5 6 7 8; do"
        + "        hyprctl hyprsunset identity >/dev/null 2>&1 && break;"
        + "        sleep 0.08;"
        + "      done; }; "

    function openDisplay() {
        if (root.displayAnchorItem) root.anchorPopupTo(root.displayAnchorItem);
        displayProbe.running = true;
        root.displayRow = 0;
        root.displayVisible = true;
    }

    // ---------- System popup state ----------
    property bool systemVisible: false
    function openSystem() {
        if (root.systemAnchorItem) root.anchorPopupTo(root.systemAnchorItem);
        refreshSystemStats();
        root.systemVisible = true;
    }

    function refreshSystemStats() {
        if (systemProbe.running) return;
        systemProbe.running = false;
        systemProbe.running = true;
    }

    function runSunset(verb) {
        const cmd = "hyprctl hyprsunset " + verb;
        if (root.sunsetReady) root.run(cmd);
        else { root.run(root.ensureSunset + cmd); root.sunsetReady = true; }
    }

    function setWarmth(k) {
        k = Math.max(1000, Math.min(6500, Math.round(k / 50) * 50));
        root.warmthK = k;
        // identity skips the GPU matrix entirely at full daylight.
        root.runSunset(k >= 6500 ? "identity" : "temperature " + k);
    }
    function setBrightness(pct) {
        pct = Math.max(1, Math.min(100, Math.round(pct)));
        root.brightnessPct = pct;
        root.run("brightnessctl set " + pct + "%");
    }
    function setVolume(pct) {
        pct = Math.max(0, Math.min(150, Math.round(pct)));
        root.audioVol = pct;
        // --allow-boost lets values above 100 land; pamixer caps at 150
        // anyway, matching the visible range on most distros.
        root.run("pamixer --allow-boost --set-volume " + pct);
    }
    function toggleMute() {
        root.audioMuted = !root.audioMuted;
        root.run("pamixer -t");
    }
    function setGamma(pct) {
        pct = Math.max(50, Math.min(150, Math.round(pct)));
        root.gammaPct = pct;
        root.runSunset("gamma " + pct);
    }
    function applyPreset(p) {
        root.warmthK = p.warmth;
        root.gammaPct = p.gamma;
        root.brightnessPct = p.bright;
        const w = (p.warmth >= 6500) ? "identity" : "temperature " + p.warmth;
        const prelude = root.sunsetReady ? "" : root.ensureSunset;
        root.run(prelude
                 + "hyprctl hyprsunset " + w
                 + " && hyprctl hyprsunset gamma " + p.gamma
                 + " && brightnessctl set " + p.bright + "%");
        root.sunsetReady = true;
    }
    function blankScreen() {
        // Wait out the close animation before the panel blanks, or the
        // reveal-out visibly stutters.
        root.run("sleep 0.25 && hyprctl dispatch dpms off");
        root.displayVisible = false;
    }
    function resetDisplay() {
        root.warmthK = 6500;
        root.gammaPct = 100;
        root.brightnessPct = 100;
        const prelude = root.sunsetReady ? "" : root.ensureSunset;
        root.run(prelude
                 + "hyprctl hyprsunset identity"
                 + " && hyprctl hyprsunset gamma 100"
                 + " && brightnessctl set 100%");
        root.sunsetReady = true;
    }

    // ---------- Display probe ----------
    Process {
        id: displayProbe
        running: false
        command: ["bash", "-lc",
            "m=$(hyprctl monitors -j 2>/dev/null"
            + " | jq -r '.[0] | [.name,(\"\\(.width)x\\(.height)\"),(.refreshRate|tostring),(.scale|tostring)] | join(\"|\")' 2>/dev/null);"
            + " b=$(brightnessctl get 2>/dev/null);"
            + " mb=$(brightnessctl max 2>/dev/null);"
            + " pct=100;"
            + " if [ -n \"$b\" ] && [ -n \"$mb\" ] && [ \"$mb\" -gt 0 ]; then pct=$(( b * 100 / mb )); fi;"
            + " printf '%s|%d' \"$m\" \"$pct\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim().split("|");
                if (p.length < 5) return;
                root.monitorName   = p[0] || "eDP-1";
                root.monitorRes    = p[1] || "2880x1800";
                root.monitorRate   = parseFloat(p[2]) || 60.0;
                root.monitorScale  = parseFloat(p[3]) || 1.0;
                root.brightnessPct = parseInt(p[4]) || 100;
            }
        }
    }

    // ---------- Weather state ----------
    // Single curl to wttr.in?format=j1 backs both the bar glyph and the
    // popup. Refreshed every 30 minutes; right-click the bar icon to
    // force-refresh. The location is read from
    //   ~/.config/omarchy/weather/location
    // (a single line, e.g. "Oslo" or "lat,lon"). Empty file / missing
    // file means wttr.in falls back to IP geolocation. Click the place
    // name in the popup to open that file in the editor.
    readonly property string weatherLocationPath: Quickshell.env("HOME") + "/.config/omarchy/weather/location"
    property string weatherLocation: ""
    property bool   weatherVisible: false
    property bool   weatherLoaded: false
    property bool   weatherUnavailable: false
    property string weatherPlace: ""
    property real   weatherTempC: 0
    property real   weatherFeelsC: 0
    property int    weatherWindKmh: 0
    property string weatherWindDir: ""
    property int    weatherHumidity: 0
    property int    weatherUv: 0
    property string weatherDesc: ""
    property int    weatherCode: 0
    property string weatherSunrise: ""
    property string weatherSunset: ""
    property real   weatherHighC: 0
    property real   weatherLowC: 0
    property var    weatherForecast: []
    property string weatherUpdatedAt: ""

    // Mirrors omarchy-weather-icon's case statement so the bar glyph stays
    // honest when a manual location overrides IP geolocation. `night`
    // swaps the variants for codes that have one.
    function weatherGlyph(code, night) {
        const n = parseInt(code) || 0;
        if (n === 113) return String.fromCodePoint(night ? 0xe32b : 0xe30d);
        if (n === 116) return String.fromCodePoint(night ? 0xe32e : 0xe302);
        if (n === 119 || n === 122) return String.fromCodePoint(0xe33d);
        if (n === 143 || n === 248 || n === 260) return String.fromCodePoint(0xe313);
        if (n === 176 || n === 263 || n === 353) return String.fromCodePoint(night ? 0xe333 : 0xe308);
        if ([179,227,230,323,326,368].indexOf(n) !== -1) return String.fromCodePoint(night ? 0xe327 : 0xe30a);
        if ([182,185,281,284,311,314,317,320,350,362,365,374,377].indexOf(n) !== -1) return String.fromCodePoint(0xe3ad);
        if ([200,386,389,392,395].indexOf(n) !== -1) return String.fromCodePoint(0xe31d);
        if ([266,293,296,299,302,305,308,356,359].indexOf(n) !== -1) return String.fromCodePoint(0xe318);
        if ([329,332,335,338,371].indexOf(n) !== -1) return String.fromCodePoint(0xe31a);
        return String.fromCodePoint(0xe33d);
    }

    function parseClock(s) {
        const m = String(s).match(/^(\d{1,2}):(\d{2})\s*(AM|PM)?\s*$/i);
        if (!m) return -1;
        let h = parseInt(m[1]);
        const min = parseInt(m[2]);
        if (m[3]) {
            const pm = m[3].toUpperCase() === "PM";
            if (h === 12) h = pm ? 12 : 0;
            else if (pm) h += 12;
        }
        return h * 60 + min;
    }

    // Touching root.mm — the minute string from the 1Hz telemetry tick —
    // forces this binding to recompute when the clock rolls a minute, so
    // dusk flips the glyph without a fresh wttr fetch.
    readonly property bool weatherIsNight: {
        root.mm;
        const sr = root.parseClock(root.weatherSunrise);
        const ss = root.parseClock(root.weatherSunset);
        if (sr < 0 || ss < 0) return false;
        const now = new Date();
        const cur = now.getHours() * 60 + now.getMinutes();
        return cur < sr || cur >= ss;
    }
    readonly property string weatherIcon: root.weatherLoaded
        ? root.weatherGlyph(root.weatherCode, root.weatherIsNight)
        : ""

    function fmtTemp(c) {
        const v = Math.round(c);
        return (v > 0 ? "+" : "") + v + "°";
    }

    // Wi-Fi signal-bars glyph from a 0-100% strength reading. Same ramp
    // the netProbe uses to drive the bar icon — shared so the Quick
    // panel rows render identical iconography.
    readonly property var _wifiBarsRamp: ["󰤯","󰤟","󰤢","󰤥","󰤨"]
    function wifiBarsGlyph(pct) {
        const idx = pct >= 80 ? 4 : pct >= 60 ? 3 : pct >= 40 ? 2 : pct >= 20 ? 1 : 0;
        return _wifiBarsRamp[idx];
    }

    function openWeather() {
        if (root.weatherAnchorItem) root.anchorPopupTo(root.weatherAnchorItem);
        root.weatherVisible = true;
    }
    function refreshWeather() { weatherProbe.running = false; weatherProbe.running = true; }
    function editWeatherLocation() {
        root.run("mkdir -p \"$(dirname " + JSON.stringify(root.weatherLocationPath) + ")\""
                 + " && touch " + JSON.stringify(root.weatherLocationPath)
                 + " && ${EDITOR:-nvim} " + JSON.stringify(root.weatherLocationPath));
        root.weatherVisible = false;
    }

    // ---------- Weather location file ----------
    FileView {
        id: weatherLocFile
        path: root.weatherLocationPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.weatherLocation = weatherLocFile.text().trim();
            // false→true edge so an in-flight probe doesn't swallow the
            // new URL on a runtime location edit.
            weatherProbe.running = false;
            weatherProbe.running = true;
        }
    }

    // ---------- Weather probe ----------
    // wttr.in rate-limits; we cap at one fetch per 30 minutes plus
    // refresh-on-demand. The location segment is empty for auto-geo and
    // a URL-encoded city otherwise. encodeURIComponent keeps spaces and
    // diacritics safe so "São Paulo" or "New York" work without escaping
    // by hand.
    readonly property string weatherUrl: {
        const loc = root.weatherLocation;
        return "https://wttr.in/" + (loc ? encodeURIComponent(loc) : "") + "?format=j1";
    }
    Process {
        id: weatherProbe
        running: false
        command: ["bash", "-lc",
            "URL=" + JSON.stringify(root.weatherUrl) + ";"
            + " j=$(curl -fsS --max-time 5 \"$URL\" 2>/dev/null);"
            + " if [ -z \"$j\" ]; then printf 'ERR'; exit 0; fi;"
            + " data=$(printf '%s' \"$j\" | jq -r '"
            + "  .current_condition[0] as $c"
            + "  | .weather as $w"
            + "  | .nearest_area[0] as $a"
            + "  | [$a.areaName[0].value, $c.temp_C, $c.FeelsLikeC,"
            + "     $c.windspeedKmph, $c.winddir16Point, $c.humidity, $c.uvIndex,"
            + "     $c.weatherDesc[0].value, $c.weatherCode,"
            + "     $w[0].astronomy[0].sunrise, $w[0].astronomy[0].sunset,"
            + "     $w[0].maxtempC, $w[0].mintempC,"
            + "     $w[1].date, $w[1].maxtempC, $w[1].mintempC, $w[1].hourly[4].weatherCode,"
            + "     $w[2].date, $w[2].maxtempC, $w[2].mintempC, $w[2].hourly[4].weatherCode]"
            + "  | map(tostring) | join(\"|\")');"
            + " printf 'OK|%s' \"$data\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const txt = this.text.trim();
                if (!txt.startsWith("OK|")) {
                    root.weatherUnavailable = true;
                    return;
                }
                const p = txt.substring(3).split("|");
                if (p.length < 21) {
                    root.weatherUnavailable = true;
                    return;
                }
                root.weatherPlace    = p[0];
                root.weatherTempC    = parseFloat(p[1]);
                root.weatherFeelsC   = parseFloat(p[2]);
                root.weatherWindKmh  = parseInt(p[3]);
                root.weatherWindDir  = p[4];
                root.weatherHumidity = parseInt(p[5]);
                root.weatherUv       = parseInt(p[6]);
                root.weatherDesc     = p[7];
                root.weatherCode     = parseInt(p[8]);
                root.weatherSunrise  = p[9];
                root.weatherSunset   = p[10];
                root.weatherHighC    = parseFloat(p[11]);
                root.weatherLowC     = parseFloat(p[12]);
                const days = [];
                for (let i = 0; i < 2; i++) {
                    const off = 13 + i * 4;
                    days.push({
                        day:  Qt.formatDate(new Date(p[off]), "ddd").toUpperCase(),
                        high: parseFloat(p[off + 1]),
                        low:  parseFloat(p[off + 2]),
                        code: parseInt(p[off + 3])
                    });
                }
                root.weatherForecast = days;
                const now = new Date();
                root.weatherUpdatedAt = String(now.getHours()).padStart(2,"0")
                                        + ":" + String(now.getMinutes()).padStart(2,"0");
                root.weatherLoaded = true;
                root.weatherUnavailable = false;
            }
        }
    }

    // Initial fetch is driven by weatherLocFile.onLoaded — this timer only
    // handles the half-hourly refresh once the bar is settled.
    Timer {
        interval: 1800000
        running: true
        repeat: true
        onTriggered: { weatherProbe.running = false; weatherProbe.running = true; }
    }

    // ---------- Generic launcher ----------
    Process { id: runner; running: false
        stderr: StdioCollector { onStreamFinished: if (this.text) console.log("[RUN-DIAG stderr] " + this.text) }
    }
    Process { id: themeApplier; running: false }
    function run(cmd) {
        console.log("[RUN-DIAG] " + cmd);
        runner.command = ["bash", "-lc", cmd];
        runner.running = false;
        runner.running = true;
    }

    function focusWorkspace(id) {
        Hyprland.dispatch('hl.dsp.focus({ workspace = "' + id + '" })');
    }

    // ---------- System stats (on demand) ----------
    Process {
        id: systemProbe
        running: false
        command: ["bash", "-lc",
            "read _ a b c d _ < <(grep '^cpu ' /proc/stat); "
            + "sleep 0.15; "
            + "read _ e f g h _ < <(grep '^cpu ' /proc/stat); "
            + "du=$(( (e+f+g) - (a+b+c) )); dt=$(( (e+f+g+h) - (a+b+c+d) )); "
            + "cpu=$(( dt>0 ? du*100/dt : 0 )); "
            + "mem=$(awk '/MemTotal/{t=$2}/MemAvailable/{m=$2}END{printf \"%d\",(t-m)*100/t}' /proc/meminfo); "
            + "printf '%d|%d' \"$cpu\" \"$mem\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.split("|");
                if (p.length === 2) {
                    root.cpuVal = parseInt(p[0]) || 0;
                    root.memVal = parseInt(p[1]) || 0;
                }
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { systemProbe.running = false; systemProbe.running = true; } }

    // ---------- Telemetry (1 Hz) ----------
    Process {
        id: tel
        running: false
        command: ["bash", "-lc",
            "bat=0; bst=Unknown; pwr=0; batFound=0; "
            + "if [ -d /sys/class/power_supply/BAT0 ]; then "
            + "  bat=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 0); "
            + "  bst=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo Unknown); "
            + "  pwr=$(cat /sys/class/power_supply/BAT0/power_now 2>/dev/null || echo 0); "
            + "  batFound=1; "
            + "elif [ -d /sys/class/power_supply/BAT1 ]; then "
            + "  bat=$(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null || echo 0); "
            + "  bst=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null || echo Unknown); "
            + "  pwr=$(cat /sys/class/power_supply/BAT1/power_now 2>/dev/null || echo 0); "
            + "  batFound=1; "
            + "fi; "
            + "pwr=${pwr#-}; "  // some kernels prefix '-' on discharge; magnitude is enough, sign comes from $bst
            + "printf '%d|%s|%s|%s|%s|%s|%s|%d|%d' "
            + "  \"$bat\" \"$bst\" "
            + "  \"$(date +%H)\" \"$(date +%M)\" \"$(date +%d)\" \"$(date +%a)\" \"$(date +%b | tr a-z A-Z)\" \"$pwr\" \"$batFound\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.split("|");
                if (p.length === 9) {
                    root.batVal = parseInt(p[0]) || 0;
                    root.batState = p[1] || "Unknown";
                    root.hh = p[2]; root.mm = p[3];
                    root.dd = p[4]; root.dow = p[5];
                    root.mon = p[6];
                    root.batPower = (parseInt(p[7]) || 0) / 1e6;
                    root.batPresent = p[8] === "1";
                }
            }
        }
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { tel.running = false; tel.running = true; } }

    // ---------- Network status ----------
    Process {
        id: netProbe
        running: false
        command: ["bash", "-lc",
            "type=none; "
            + "if ip -o addr show | grep -qE '^[0-9]+: (en|eth)[^ ]*.*inet '; then type=eth; fi; "
            + "if [ \"$type\" = none ]; then "
            + "  for w in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do "
            + "    link=$(iw dev \"$w\" link 2>/dev/null); "
            + "    dbm=$(printf '%s\\n' \"$link\" | awk '/signal:/{print $2}'); "
            + "    if [ -n \"$dbm\" ]; then "
            + "      pct=$((2 * (dbm + 100))); "
            + "      [ $pct -lt 0 ] && pct=0; "
            + "      [ $pct -gt 100 ] && pct=100; "
            + "      ssid=$(printf '%s\\n' \"$link\" | sed -n 's/^[[:space:]]*SSID: //p'); "
            + "      type=\"wifi:$pct:$ssid\"; break; "
            + "    fi; "
            + "  done; "
            + "fi; printf '%s' \"$type\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim();
                if (t === "eth") {
                    root.netIcon = "󰀂"; root.netKind = "eth";
                    root.wifiSsid = ""; root.wifiSignal = 0;
                } else if (t.startsWith("wifi:")) {
                    // Split on the first two colons: signal pct, then SSID
                    // (which may itself contain colons, so a naive split
                    // would truncate networks like "Foo:Bar").
                    const rest = t.slice(5);
                    const c = rest.indexOf(":");
                    const sig = parseInt(c < 0 ? rest : rest.slice(0, c)) || 0;
                    const ssid = c < 0 ? "" : rest.slice(c + 1);
                    root.netIcon = root.wifiBarsGlyph(sig); root.netKind = "wifi";
                    root.wifiSignal = sig; root.wifiSsid = ssid;
                } else {
                    root.netIcon = "󰤮"; root.netKind = "none";
                    root.wifiSsid = ""; root.wifiSignal = 0;
                }
            }
        }
    }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { netProbe.running = false; netProbe.running = true; } }

    // ---------- Network burst detection ----------
    // Samples cumulative rx+tx bytes from /proc/net/dev once per second.
    // When the per-second delta crosses the threshold and the burst is
    // armed, emits netBurst() and disarms for `burstCooldown.interval` ms
    // so a sustained download doesn't keep retriggering — this should read
    // as a rare event, not a continuous activity light.
    signal netBurst()
    property real netPrevBytes: -1
    property bool burstArmed: false
    // First sample after startup seeds netPrevBytes; arm only after a
    // settling beat, otherwise the initial delta (counter vs 0) would
    // always fire.
    Timer { interval: 2500; running: true; repeat: false
        onTriggered: root.burstArmed = true }

    Process {
        id: netBurstProbe
        running: false
        // $2 is rx_bytes, $10 is tx_bytes per /proc/net/dev's column layout.
        // Skip loopback so localhost chatter doesn't count as "network".
        // Direct argv (no shell) — saves the per-poll login-shell startup.
        command: ["awk", "NR>2 && $1!~/^lo:/ {s+=$2+$10} END {print s+0}",
                  "/proc/net/dev"]
        stdout: StdioCollector {
            onStreamFinished: {
                const cur = parseFloat(this.text.trim());
                if (isNaN(cur)) return;
                if (root.netPrevBytes < 0) { root.netPrevBytes = cur; return; }
                const delta = cur - root.netPrevBytes;
                root.netPrevBytes = cur;
                // ~1.5 MB in a 1s sample window. Low enough that an active
                // download or stream paints the arc regularly, high enough
                // that idle browser chatter doesn't.
                if (root.burstArmed && delta > 1.5 * 1024 * 1024) {
                    root.burstArmed = false;
                    root.netBurst();
                    burstCooldown.restart();
                }
            }
        }
    }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { netBurstProbe.running = false; netBurstProbe.running = true; } }
    Timer { id: burstCooldown; interval: 2000; repeat: false
        onTriggered: root.burstArmed = true }

    // ---------- Idle dim ----------
    // Wayland ext-idle-notify-v1 via Quickshell. The compositor counts
    // pointer AND keyboard activity, so typing keeps the bar bright even
    // when the mouse hasn't moved. Once idle the rectangle eases to 0.7
    // opacity over 6s; the next input snaps it back over 60ms — slow
    // fade reads ambient, fast restore reads responsive.
    IdleMonitor {
        id: idleMonitor
        enabled: true
        timeout: 60
        respectInhibitors: true
    }
    readonly property bool isIdle: idleMonitor.isIdle

    // ---------- Bluetooth status ----------
    // bluez-tools path: bt-adapter --info for power state only — the
    // per-device connected count is updated by btDevicesProbe which
    // runs on-demand from the Quick panel. Keeping the 5s loop here
    // single-shell-out avoids N+1 forks on machines with several
    // paired devices.
    Process {
        id: btProbe
        running: false
        command: ["bash", "-lc",
            "if command -v bt-adapter >/dev/null 2>&1; then"
            + "  p=$(bt-adapter --info 2>/dev/null | awk '/Powered:/{print $2; exit}');"
            + "  [ \"$p\" = 1 ] && echo on || echo off;"
            +             "elif command -v bluetoothctl >/dev/null 2>&1; then"
            + "  echo 'show' | bluetoothctl 2>/dev/null | awk '/Powered:/{print ($2==\"yes\")?\"on\":\"off\"; exit}';"
            + "else echo off; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = this.text.trim();
                const powered = (s === "on");
                if (root.btPowered !== powered) root.btPowered = powered;
                if (!powered) {
                    if (root.btIcon !== root.icoBtOn) root.btIcon = root.icoBtOn;
                    if (root.btCount !== 0)  root.btCount = 0;
                } else {
                    if (root.btIcon !== root.icoBtOn) root.btIcon = root.icoBtOn;
                }
            }
        }
    }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { btProbe.running = false; btProbe.running = true; } }

    // ---------- Audio status ----------
    // Icon ramps with volume: muted → icoMute, 0 → off, <50 → low, ≥50 → high.
    Process {
        id: audioProbe
        running: false
        command: ["bash", "-lc",
            "v=$(pamixer --get-volume 2>/dev/null || echo 0); "
            + "m=$(pamixer --get-mute 2>/dev/null || echo false); "
            + "d=$(pactl get-default-sink 2>/dev/null); "
            +             "case \"$d\" in *bluez*|*bluetooth*) t=\"bt\" ;; *hdmi*|*dp*|*displayport*) t=\"hdmi\" ;; *headphone*|*headset*|*hp*) t=\"hp\" ;; *) t=\"spk\" ;; esac; "
            +             "desc=$(pactl list sinks 2>/dev/null | grep -A5 -F \"Name: $d\" | grep \"Description:\" | sed 's/.*Description: //'); "
            + "printf '%s|%s|%s|%s' \"$v\" \"$m\" \"$t\" \"${desc:-}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.split("|");
                if (p.length !== 4) return;
                const v = parseInt(p[0]);
                const m = p[1].trim() === "true";
                const t = p[2].trim();
                const desc = p[3].trim();
                root.audioVol = isNaN(v) ? 0 : v;
                root.audioMuted = m;
                root.audioDevType = t;
                root.audioSinkDesc = desc;
                if (m) {
                    root.audioIcon = root.icoMute;
                } else if (t === "hp" || t === "bt") {
                    root.audioIcon = root.icoHeadphone;
                } else if (t === "hdmi") {
                    root.audioIcon = root.icoDisplay;
                } else if (isNaN(v) || v <= 0) {
                    root.audioIcon = root.icoVol1;
                } else if (v < 34) {
                    root.audioIcon = root.icoVol1;
                } else if (v < 67) {
                    root.audioIcon = root.icoVol2;
                } else {
                    root.audioIcon = root.icoVol3;
                }
            }
        }
    }
    Timer { interval: 500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { audioProbe.running = false; audioProbe.running = true; } }

    // ---------- Bluetooth device probe ----------
    // Walks every paired/known device through `bt-device --info` to pull
    // its name + connected/paired/trusted flags. Cheap at the few-devices-
    // per-machine scale; the `bt-device -l` output is "Name (MAC)" lines
    // with a leading "Added devices:" header that tail strips.
    Process {
        id: btDevicesProbe
        running: false
        command: ["bash", "-lc",
            "macs=$(bt-device -l 2>/dev/null | tail -n +2 | sed -n 's/.*(\\([0-9A-F:]\\{17\\}\\))$/\\1/p');"
            + " [ -z \"$macs\" ] && macs=$(bluetoothctl devices 2>/dev/null | sed -n 's/^Device \\([0-9A-F:]\\{17\\}\\) .*/\\1/p');"
            + " for m in $macs; do"
            + "   info=$(bt-device --info \"$m\" 2>/dev/null || bluetoothctl info \"$m\" 2>/dev/null);"
            + "   [ -z \"$info\" ] && continue;"
            + "   name=$(printf '%s' \"$info\" | awk -F': ' '/^[[:space:]]*Name:/{print $2; exit}');"
            + "   [ -z \"$name\" ] && name=$(printf '%s' \"$info\" | sed -n 's/^[[:space:]]*Name: \\(.*\\)/\\1/p');"
            + "   conn=$(printf '%s' \"$info\" | awk '/^[[:space:]]*Connected: (1|yes)/{print 1; exit}');"
            + "   paired=$(printf '%s' \"$info\" | awk '/^[[:space:]]*Paired: (1|yes)/{print 1; exit}');"
            + "   trusted=$(printf '%s' \"$info\" | awk '/^[[:space:]]*Trusted: (1|yes)/{print 1; exit}');"
            + "   batt=$(printf '%s' \"$info\" | awk -F': ' '/Battery Percentage:/{if(match($2,/\\(([0-9]+)\\)/,a)) print a[1]}');"
            + "   [ -z \"$batt\" ] && batt=0;"
            + "   printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \"$m\" \"${name:-$m}\" \"${conn:-0}\" \"${paired:-0}\" \"${trusted:-0}\" \"$batt\";"
            + " done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(s => s.length > 0);
                const devs = lines.map(line => {
                    const f = line.split("\t");
                    return {
                        mac:       f[0] || "",
                        name:      (f[1] || "").trim() || (f[0] || ""),
                        connected: f[2] === "1",
                        paired:    f[3] === "1",
                        trusted:   f[4] === "1",
                        battery:   parseInt(f[5]) || 0
                    };
                });
                // Connected first, then paired, then everything else.
                devs.sort((a, b) =>
                    (b.connected - a.connected)
                    || (b.paired - a.paired)
                    || a.name.localeCompare(b.name));
                // Equality guard so the Quick panel's Repeater doesn't
                // re-evaluate every refresh when nothing has changed.
                const serialised = JSON.stringify(devs);
                if (serialised === root._btDevicesSer) return;
                root._btDevicesSer = serialised;
                root.btDevices = devs;
                const connCount = devs.filter(d => d.connected).length;
                if (root.btCount !== connCount) root.btCount = connCount;
            }
        }
    }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { btDevicesProbe.running = false; btDevicesProbe.running = true; } }

    // ---------- Wi-Fi scan probe ----------
    // iwctl path (omarchy ships iwd, not NetworkManager): detect the
    // station device, check Powered state, kick a non-blocking scan,
    // then parse human-formatted get-networks output. Signal is reported
    // in tenths of dBm (e.g. -6400 = -64 dBm); convert to a 0-100% bar
    // on the QML side. ANSI codes are stripped before parsing.
    Process {
        id: wifiScanProbe
        running: false
        command: ["bash", "-lc",
            "DEV=$(iwctl --dont-ask device list 2>/dev/null"
            + "   | sed 's/\\x1b\\[[0-9;]*m//g'"
            + "   | awk '/station/{print $1; exit}');"
            + " if [ -z \"$DEV\" ]; then echo 'RADIO|off'; exit 0; fi;"
            + " powered=$(iwctl --dont-ask device \"$DEV\" show 2>/dev/null"
            + "   | sed 's/\\x1b\\[[0-9;]*m//g'"
            + "   | awk '/Powered/{print $NF; exit}');"
            + " if [ \"$powered\" != on ]; then echo 'RADIO|off'; exit 0; fi;"
            + " echo 'RADIO|on';"
            + " iwctl --dont-ask station \"$DEV\" scan >/dev/null 2>&1;"
            + " iwctl --dont-ask station \"$DEV\" get-networks rssi-dbms 2>/dev/null"
            + "   | sed 's/\\x1b\\[[0-9;]*m//g'"
            + "   | awk '"
            + "       /^-+$/ { sep++; next }"
            + "       sep < 2 || $0 ~ /^[[:space:]]*$/ { next }"
            + "       {"
            + "         line=$0;"
            + "         conn=(index(substr(line,1,4),\">\")>0)?1:0;"
            + "         sub(/^[ >]+/, \"\", line);"
            + "         sub(/[ ]+$/, \"\", line);"
            + "         if (match(line, /^(.*[^ ])  +([^ ]+)  +(-?[0-9]+)$/, m))"
            + "           printf \"%d\\t%s\\t%s\\t%s\\n\", conn, m[1], m[2], m[3];"
            + "       }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(s => s.length > 0);
                let radioOn = false;
                const networks = [];
                for (const line of lines) {
                    if (line.startsWith("RADIO|")) {
                        radioOn = line.slice(6) === "on";
                        continue;
                    }
                    const f = line.split("\t");
                    if (f.length < 4) continue;
                    // dBm tenths -> dBm -> 0-100%. -50dBm or stronger pegs at 100%.
                    const dbm = parseInt(f[3]) / 100;
                    const pct = Math.max(0, Math.min(100, Math.round(2 * (dbm + 100))));
                    networks.push({
                        inUse: f[0] === "1",
                        ssid: f[1],
                        signal: pct,
                        security: f[2]
                    });
                }
                networks.sort((a, b) => (b.inUse - a.inUse) || (b.signal - a.signal));
                if (root.wifiRadioOn !== radioOn) root.wifiRadioOn = radioOn;
                const ser = JSON.stringify(networks);
                if (ser !== root._wifiNetworksSer) {
                    root._wifiNetworksSer = ser;
                    root.wifiNetworks = networks;
                }
                root.wifiScanning = false;
            }
        }
    }

    // ---------- Audio sinks probe ----------
    // wpctl status's structured form: lines like
    //   "*    52. WH-1000XM4              [vol: 0.45]"
    // The leading "*" flags the current default; we capture id, label, and
    // default state. Skipped automatically when wireplumber isn't around.
    Process {
        id: audioSinksProbe
        running: false
        // Tracks the Audio top-level section AND the Sinks subsection
        // separately so we don't pick up Sources, Filters, or Video's
        // Sinks. Section header lines start with `├─` or `└─`; the Audio
        // section ends at the next top-level label (Video / Settings).
        command: ["bash", "-lc",
            "wpctl status 2>/dev/null | awk '"
            + "  /^Audio$/                                    {sec=\"audio\"; sub=\"\"; next}"
            + "  /^[A-Z][a-zA-Z]+$/                           {sec=\"\";      sub=\"\"; next}"
            + "  /^[[:space:]]*[├└]─[[:space:]]*Sinks:/       {sub=\"sinks\"; next}"
            + "  /^[[:space:]]*[├└]─/                          {sub=\"\";      next}"
            + "  sec==\"audio\" && sub==\"sinks\" {"
            + "    star=(index($0,\"*\")>0 && index($0,\"*\")<index($0,\".\")) ? 1 : 0;"
            + "    line=$0;"
            + "    sub(/^[ │├─└*]+/, \"\", line);"
            + "    if (match(line, /^([0-9]+)\\. (.+)\\[/, m)) {"
            + "      gsub(/[ \\t]+$/, \"\", m[2]);"
            + "      printf \"%s\\t%s\\t%d\\n\", m[1], m[2], star;"
            + "    }"
            + "  }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(s => s.length > 0);
                const sinks = lines.map(line => {
                    const f = line.split("\t");
                    return {
                        id: f[0] || "",
                        name: (f[1] || "").trim(),
                        isDefault: f[2] === "1"
                    };
                });
                const ser = JSON.stringify(sinks);
                if (ser !== root._audioSinksSer) {
                    root._audioSinksSer = ser;
                    root.audioSinks = sinks;
                }
                const def = sinks.find(s => s.isDefault);
                if (def && root.audioDefaultSink !== def.id) root.audioDefaultSink = def.id;
            }
        }
    }

    // ---------- Power-profile probe ----------
    // On-demand only: triggered once at startup so the Battery tile has
    // current state ready, and from setPowerProfile()/refreshPowerProfile()
    // afterwards. Power-profiles-daemon doesn't change behind our back at
    // any meaningful rate, so a 5s polling loop is wasted work.
    function refreshPowerProfile() {
        powerProfileProbe.running = false;
        powerProfileProbe.running = true;
    }
    Process {
        id: powerProfileProbe
        running: false
        command: ["bash", "-lc",
            "cur=$(powerprofilesctl get 2>/dev/null); "
            + "if [ -z \"$cur\" ]; then echo '|'; exit 0; fi; "
            + "list=$(powerprofilesctl list 2>/dev/null | awk -F: '/^[ *]+[a-z-]+:/{gsub(/^[ *]+|:$/,\"\",$1); print $1}' | paste -sd,); "
            + "printf '%s|%s' \"$cur\" \"$list\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim().split("|");
                if (p.length !== 2) return;
                const cur = p[0] || "";
                const list = p[1] ? p[1].split(",").filter(Boolean) : [];
                if (root.powerProfile !== cur) root.powerProfile = cur;
                if (JSON.stringify(root.powerProfiles) !== JSON.stringify(list))
                    root.powerProfiles = list;
            }
        }
    }
    Component.onCompleted: refreshPowerProfile()

    // ---------- Omarchy update probe ----------
    // Mirrors waybar's custom/update: omarchy-update-available exits 0 and
    // prints "Omarchy update available (<tag>)" when behind, exits non-zero
    // otherwise. Network-bound (ls-remote), so the cadence matches waybar
    // at 6h; refreshOmarchyUpdateCheck() retriggers on demand.
    Process {
        id: omarchyUpdateProbe
        running: false
        command: ["omarchy-update-available"]
        stdout: StdioCollector { id: omarchyUpdateOut }
        onExited: (code, status) => {
            if (code === 0) {
                const m = omarchyUpdateOut.text.match(/\(([^)]+)\)/);
                root.omarchyLatestTag = m ? m[1] : "";
                root.omarchyUpdateAvailable = true;
            } else {
                root.omarchyUpdateAvailable = false;
                root.omarchyLatestTag = "";
            }
        }
    }
    Timer { interval: 21600000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refreshOmarchyUpdateCheck() }

    // ---------- Screenshots list probe ----------
    // Cap at 60 entries (~5 pages) so a screenshot-heavy ~/Pictures
    // doesn't keep dozens of decoded thumbs hot.
    Process {
        id: screenshotProbe
        running: false
        command: ["sh", "-c",
            "ls -t " + Quickshell.env("HOME") + "/Pictures/screenshot-*.png 2>/dev/null | head -60"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(s => s.length > 0);
                root.screenshotFiles = lines.map(p => ({
                    path: p,
                    label: root.formatScreenshotLabel(p)
                }));
                if (root.screenshotPage >= root.screenshotPageCount)
                    root.screenshotPage = 0;
                root.selectedScreenshot = root.visibleScreenshots.length > 0 ? 0 : -1;
            }
        }
    }

    // copiedPath stores the path (not the index) so the ack survives
    // paging or a list refresh that lands mid-flash.
    Process { id: shotCopier; running: false }
    property string copiedPath: ""
    Timer {
        id: copiedReset
        interval: 1400
        repeat: false
        onTriggered: root.copiedPath = ""
    }
    // Hold the popup open long enough for the seal-wash flash to bloom
    // in (~80ms snap + a beat of read time) before dismissing.
    Timer {
        id: copiedDismiss
        interval: 260
        repeat: false
        onTriggered: root.screenshotsVisible = false
    }
    function copyScreenshotToClipboard(path) {
        // -t image/png so GTK/Electron paste it as an image, not a path.
        shotCopier.command = ["sh", "-c", "wl-copy -t image/png < " + JSON.stringify(path)];
        shotCopier.running = false;
        shotCopier.running = true;
        root.copiedPath = path;
        copiedReset.restart();
        if (root.screenshotsVisible) copiedDismiss.restart();
    }

    // ---------- Videos list probe ----------
    // Cache layout: ~/.cache/quickshell-desktop/video-thumbs/<md5-of-path>.{jpg,meta}
    // where .meta holds the integer duration in seconds. Both are
    // re-generated when the source is newer (`-nt`); meta is what lets warm
    // opens skip the ffprobe spawn-storm. ffmpeg/ffprobe absence is tolerated
    // (badge hides at duration 0; cell falls back to the play glyph).
    //
    // Two passes: pass 1 fans out missing thumb/meta generation in parallel
    // via xargs -P; pass 2 emits one tab-separated row per video in mtime
    // order. Cold-open of 60 fresh videos drops from minutes to seconds on
    // any multi-core box; warm-open is just 60 stat+cat round-trips.
    Process {
        id: videoProbe
        running: false
        command: ["bash", "-c",
            "CDIR=\"$HOME/.cache/quickshell-desktop/video-thumbs\"; "
          + "mkdir -p \"$CDIR\" 2>/dev/null; "
          + "PATHS=$(find \"$HOME/Videos\" -maxdepth 3 -type f "
              + "\\( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' "
              + "  -o -iname '*.mov' -o -iname '*.avi' -o -iname '*.m4v' \\) "
              + "-printf '%T@\\t%p\\n' 2>/dev/null | sort -rn | head -60 | cut -f2-); "
          + "printf '%s\\n' \"$PATHS\" | xargs -r -d '\\n' -P \"$(nproc 2>/dev/null || echo 4)\" -I{} "
              + "sh -c '"
                + "path=\"$1\"; cdir=\"$2\"; "
                + "key=$(printf %s \"$path\" | md5sum | cut -c1-32); "
                + "thumb=\"$cdir/$key.jpg\"; meta=\"$cdir/$key.meta\"; "
                + "if [ ! -f \"$thumb\" ] || [ \"$path\" -nt \"$thumb\" ]; then "
                  + "command -v ffmpeg >/dev/null 2>&1 && "
                  + "ffmpeg -y -ss 1 -i \"$path\" -frames:v 1 -vf scale=320:-1 -q:v 6 \"$thumb\" </dev/null >/dev/null 2>&1 || true; "
                + "fi; "
                + "if [ ! -f \"$meta\" ] || [ \"$path\" -nt \"$meta\" ]; then "
                  + "dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 \"$path\" 2>/dev/null | awk \"{printf \\\"%d\\\",\\$1+0}\"); "
                  + "printf %s \"${dur:-0}\" > \"$meta\"; "
                + "fi"
              + "' _ {} \"$CDIR\"; "
          + "printf '%s\\n' \"$PATHS\" | while IFS= read -r path; do "
              + "[ -z \"$path\" ] && continue; "
              + "key=$(printf %s \"$path\" | md5sum | cut -c1-32); "
              + "thumb=\"$CDIR/$key.jpg\"; "
              + "dur=$(cat \"$CDIR/$key.meta\" 2>/dev/null); "
              + "mtime=$(stat -c %Y \"$path\" 2>/dev/null); "
              + "size=$(stat -c %s \"$path\" 2>/dev/null); "
              + "printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$path\" \"$thumb\" \"${dur:-0}\" \"${mtime:-0}\" \"${size:-0}\"; "
          + "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n").filter(s => s.length > 0);
                root.videoFiles = lines.map(line => {
                    const f = line.split("\t");
                    return {
                        path: f[0] || "",
                        thumb: f[1] || "",
                        duration: parseInt(f[2] || "0", 10),
                        mtime: parseInt(f[3] || "0", 10),
                        size: parseInt(f[4] || "0", 10),
                        label: root.formatVideoLabel(f[0] || "")
                    };
                });
                if (root.videoPage >= root.videoPageCount)
                    root.videoPage = 0;
                root.selectedVideo = root.visibleVideos.length > 0 ? 0 : -1;
            }
        }
    }

    Process { id: vidCopier; running: false }

    // Blueprint list for the Aether popup. `aether --list-blueprints --json`
    // emits {blueprints: [{name, colors[16], lightMode, wallpaper, timestamp}]}.
    // Sorted newest-first so freshly-saved themes surface at the top.
    Process {
        id: aetherProbe
        running: false
        command: [root.aetherBin, "--list-blueprints", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr = [];
                try {
                    const obj = JSON.parse(this.text);
                    arr = (obj.blueprints || []).slice();
                } catch (_) { arr = []; }
                arr.sort((a, b) => (Number(b.timestamp) || 0) - (Number(a.timestamp) || 0));
                root.aetherBlueprints = arr;
                root.aetherLoading = false;
                root.selectedAether = arr.length > 0 ? 0 : -1;
            }
        }
    }
    // copiedVideo = which path is flashing on the grid; copiedVideoMode tells
    // the footer which payload landed (file URI vs raw bytes).
    property string copiedVideo: ""
    property string copiedVideoMode: ""
    Timer {
        id: copiedVideoReset
        interval: 1400
        repeat: false
        onTriggered: { root.copiedVideo = ""; root.copiedVideoMode = ""; }
    }
    Timer {
        id: copiedVideoDismiss
        interval: 260
        repeat: false
        onTriggered: root.videosVisible = false
    }

    // URI-list copy. Targets: Kdenlive (Project Bin paste), file managers,
    // GIMP, OBS, Discord/Slack/Telegram *native* (not web). wl-copy auto-
    // promotes the payload to text/plain alongside text/uri-list, so plain
    // text fields also receive the file URI in one call.
    //
    // Re-trigger vidCopier with `cmd`, then trip the cell-flash / dismiss
    // timers under the given mode. Centralised so a future third copy
    // mode can't forget a timer restart.
    function _runVideoCopy(cmd, path, mode) {
        vidCopier.command = ["sh", "-c", cmd];
        vidCopier.running = false;
        vidCopier.running = true;
        root.copiedVideo = path;
        root.copiedVideoMode = mode;
        copiedVideoReset.restart();
        if (root.videosVisible) copiedVideoDismiss.restart();
    }

    // `-n` is load-bearing: without it, wl-copy appends an LF after our CRLF,
    // and strict text/uri-list parsers (Kdenlive) read the trailing empty
    // line as a phantom second URI and reject the whole payload.
    function copyVideoUri(path) {
        const uri = "file://" + encodeURI(path);
        root._runVideoCopy(
            "printf '%s\\r\\n' " + JSON.stringify(uri) + " | wl-copy -n --type text/uri-list",
            path, "file");
    }

    // Byte copy under the auto-detected MIME (video/mp4, video/webm, …).
    // Targets: web apps that accept clipboard file paste — Discord/Slack/
    // Telegram *web*, GitHub issue editor, Notion. wl-copy holds the file
    // bytes resident until something else replaces the clipboard, so the
    // selection memory cost is the video's file size.
    function copyVideoBytes(path) {
        root._runVideoCopy("wl-copy < " + JSON.stringify(path), path, "bytes");
    }

    // ---------- Battery icon helper ----------
    // "Not charging" covers plugged-in-but-topped-up laptops; "Full" is the
    // briefly-stable Charging→Full edge. Treat all three as AC-powered and
    // swap the battery ramp for a single plug glyph — once AC is in, the
    // % digit in the tooltip is the only number worth glancing at.
    function batteryIcon() {
        if (root.batState === "Charging"
            || root.batState === "Full"
            || root.batState === "Not charging") return root.icoPlug;
        const c = root.batVal;
        const r = ["󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"];
        return r[Math.min(9, Math.floor(c / 10))];
    }

    // ---------- Surfaces ----------
    // All bar faces are instantiated; only the one matching barVariant maps
    // to the edge (the other is an unmapped, zero-exclusive-zone window).
    Bar              { root: root; visible: root.barVariant === "zen" }
    BarHacker        { root: root; visible: root.barVariant === "hackerman" }
    BarWhiterose     { root: root; visible: root.barVariant === "whiterose" }
    TooltipOverlay   { root: root }
    SystemPopup      { root: root }
    CalendarPopup    { root: root }
    ScreenshotsPopup { root: root }
    VideosPopup      { root: root }
    AetherPopup      { root: root }
    DisplayPopup     { root: root }
    WeatherPopup     { root: root }

    // ---------- IPC ----------
    // Lets external keybinds drive the screenshots popup. Wire up in
    // hyprland with e.g.:
    //   bind = SUPER, P, exec, qs ipc call screenshots toggle
    IpcHandler {
        target: "screenshots"
        function toggle(): void {
            if (root.screenshotsVisible) root.screenshotsVisible = false;
            else root.openScreenshots();
        }
        function open(): void { root.openScreenshots(); }
        function close(): void { root.screenshotsVisible = false; }
    }

    // bind = SUPER, V, exec, qs ipc call videos toggle
    IpcHandler {
        target: "videos"
        function toggle(): void {
            if (root.videosVisible) root.videosVisible = false;
            else root.openVideos();
        }
        function open(): void { root.openVideos(); }
        function close(): void { root.videosVisible = false; }
    }

    // bind = SUPER, W, exec, qs ipc call weather toggle
    IpcHandler {
        target: "weather"
        function toggle(): void {
            if (root.weatherVisible) root.weatherVisible = false;
            else root.openWeather();
        }
        function open(): void    { root.openWeather(); }
        function close(): void   { root.weatherVisible = false; }
        function refresh(): void { root.refreshWeather(); }
    }

    // bind = SUPER, A, exec, qs ipc call aether toggle
    IpcHandler {
        target: "aether"
        function toggle(): void {
            if (root.aetherVisible) root.aetherVisible = false;
            else root.openAether();
        }
        function open(): void  { root.openAether(); }
        function close(): void { root.aetherVisible = false; }
    }

    // bind = SUPER, D, exec, qs ipc call display toggle
    IpcHandler {
        target: "display"
        function toggle(): void {
            if (root.displayVisible) root.displayVisible = false;
            else root.openDisplay();
        }
        function open(): void  { root.openDisplay(); }
        function close(): void { root.displayVisible = false; }
        function reset(): void { root.resetDisplay(); }
        function blank(): void { root.blankScreen(); }
    }

    // bind = SUPER, C, exec, qs ipc call calendar toggle
    IpcHandler {
        target: "calendar"
        function toggle(): void {
            if (root.calendarVisible) root.calendarVisible = false;
            else root.openCalendar();
        }
        function open(): void  { root.openCalendar(); }
        function close(): void { root.calendarVisible = false; }
    }

    IpcHandler {
        target: "system"
        function toggle(): void {
            if (root.systemVisible) root.systemVisible = false;
            else root.openSystem();
        }
        function open(): void  { root.openSystem(); }
        function close(): void { root.systemVisible = false; }
        function btop(): void  { root.run("omarchy-launch-or-focus-tui btop"); }
    }

    // Bar face switch. Toggle from a keybind, or jump straight to one:
    //   bind = SUPER SHIFT, B, exec, qs -c desktop ipc call bar toggle
    // Also surfaced as a "Bar Style" row in the omni palette.
    IpcHandler {
        target: "bar"
        function toggle(): void    { root.cycleBarVariant(); }
        function set(name: string): void { root.setBarVariant(name); }
        function zen(): void       { root.setBarVariant("zen"); }
        function hackerman(): void { root.setBarVariant("hackerman"); }
        function whiterose(): void { root.setBarVariant("whiterose"); }
        function plain(): void     { root.setBarVariant("whiterose"); }
    }

    // ---------- MPRIS (now playing) ----------
    // Mpris.players is a live list of every player that has registered on
    // the bus. We don't bind to a single "active" one — instead the hidden
    // Repeater below subscribes to each player's signals, and on any track
    // or playback change we recompute which player to surface in the bar.
    // Preference: a playing player wins; otherwise the most-recently-seen
    // paused one with non-empty metadata; otherwise nothing.
    property MprisPlayer musicPlayer: null
    property string musicTitle: ""
    property string musicArtist: ""
    property bool   musicPlaying: false

    function refreshMusic() {
        const players = Mpris.players ? Mpris.players.values : [];
        let best = null;
        let bestRank = -1;
        for (let i = 0; i < players.length; i++) {
            const p = players[i];
            if (!p) continue;
            const hasTitle = !!(p.trackTitle && p.trackTitle.length > 0);
            // 2 = playing with title, 1 = paused with title, 0 = anything else.
            // Ties broken by list order, which roughly tracks bus registration.
            let rank = 0;
            if (hasTitle && p.isPlaying) rank = 2;
            else if (hasTitle) rank = 1;
            if (rank > bestRank) { best = p; bestRank = rank; }
        }
        root.musicPlayer  = best;
        root.musicTitle   = best ? (best.trackTitle  || "") : "";
        root.musicArtist  = best ? (best.trackArtist || "") : "";
        root.musicPlaying = best ? !!best.isPlaying : false;
    }

    function musicToggle() {
        if (root.musicPlayer && root.musicPlayer.canTogglePlaying) root.musicPlayer.togglePlaying();
    }
    function musicNext() {
        if (root.musicPlayer && root.musicPlayer.canGoNext) root.musicPlayer.next();
    }
    function musicPrev() {
        if (root.musicPlayer && root.musicPlayer.canGoPrevious) root.musicPlayer.previous();
    }

    Item {
        visible: false
        Repeater {
            model: Mpris.players
            delegate: Item {
                required property MprisPlayer modelData
                Connections {
                    target: modelData
                    function onPostTrackChanged()     { root.refreshMusic(); }
                    function onPlaybackStateChanged() { root.refreshMusic(); }
                }
                Component.onCompleted:   root.refreshMusic()
                Component.onDestruction: root.refreshMusic()
            }
        }
    }
}
