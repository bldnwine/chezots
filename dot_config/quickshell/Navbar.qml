import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

Item {
	id: nav
	required property var theme

	// ===== THEME RE-EXPORTS =====
	readonly property color paper: theme.paper
	readonly property color ink: theme.ink
	readonly property color seal: theme.seal
	readonly property color bg: theme.bg
	readonly property color fg: theme.fg
	readonly property color accent: theme.accent
	readonly property color sep: theme.sep
	readonly property string mono: theme.mono
	readonly property color inkDeep: theme.inkDeep
	readonly property int cornerRadius: theme.cornerRadius

	// ===== RUN HELPER =====
	readonly property string aetherBin: "/home/bldnwine/aethergo/build/bin/aether"
	Process { id: runner; running: false }
	function run(cmd) { runner.command = ["bash", "-lc", cmd]; runner.running = false; runner.running = true }

	// ===== ICONS =====
	readonly property string icoPlug: String.fromCodePoint(0xf06a5)
	readonly property string icoVol1: String.fromCodePoint(0xf026)
	readonly property string icoVol2: String.fromCodePoint(0xf027)
	readonly property string icoVol3: String.fromCodePoint(0xf028)
	readonly property string icoMute: String.fromCodePoint(0xeee8)

	// ===== CLOCK =====
	property string hh: ""; property string mm: ""
	property string dow: ""; property string dd: ""; property string mon: ""

	// ===== SYSTEM STATS =====
	property real cpuVal: 0; property real memVal: 0

	// ===== RECORDING =====
	property bool recordingActive: false

	// ===== KEYBOARD =====
	property bool capsOn: false; property bool numOn: false

	// ===== NETWORK =====
	property int netKind: 0
	property int wifiSignal: 0
	property string netIcon: "󰤮"
	readonly property var _wifiRamp: ["󰤯","󰤟","󰤢","󰤥","󰤨"]
	function wifiBarsGlyph(pct) {
		const idx = pct >= 80 ? 4 : pct >= 60 ? 3 : pct >= 40 ? 2 : pct >= 20 ? 1 : 0;
		return _wifiRamp[idx];
	}

	// ===== WORKSPACES (polled 2 Hz) =====
	property int activeWs: 1
	property var existingWs: [1, 2, 3, 4, 5]
	property int lastDirection: 0

	// ===== AUDIO (polled 2 s, falls back when Pipewire bindings don't fire) =====
	readonly property var activeSink: Pipewire.defaultAudioSink
	property int audioVol: 0
	property bool audioMuted: false
	property string audioIcon: ""
	function _updateAudioIcon() {
		if (nav.audioMuted) { nav.audioIcon = nav.icoMute; return; }
		var v = nav.audioVol;
		if (v <= 0) nav.audioIcon = nav.icoVol1;
		else if (v < 50) nav.audioIcon = nav.icoVol2;
		else nav.audioIcon = nav.icoVol3;
	}

	// ===== PROTON VPN =====
	property bool protonConnected: false

	// ===== BATTERY =====
	property int batVal: 0
	property string batState: ""
	function batteryIcon() {
		if (batVal <= 0 && batState.length === 0) return ""
		if (batState === "Charging" || batState === "Full" || batState === "Not charging") return icoPlug;
		var r = ["󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"];
		return r[Math.min(9, Math.floor(batVal / 10))];
	}

	// ===== MPRIS =====
	property var mprisPlayer: null
	property string musicTitle: ""; property string musicArtist: ""

	// ===== DND =====
	property bool dnd: false

	// ===== AETHER =====
	property bool aetherVisible: false
	property var  aetherBlueprints: []
	property int  selectedAether: -1
	property bool aetherLoading: false
	property string aetherQuery: ""

	readonly property var aetherFiltered: {
		const q = nav.aetherQuery.toLowerCase();
		if (q === "") return nav.aetherBlueprints;
		return nav.aetherBlueprints.filter(b =>
			String(b.name || "").toLowerCase().indexOf(q) !== -1
		);
	}

	function openAether() {
		nav.aetherQuery = "";
		nav.selectedAether = 0;
		nav.refreshAetherBlueprints();
		nav.aetherVisible = true;
	}
	function refreshAetherBlueprints() {
		nav.aetherLoading = true;
		aetherProbe.running = false;
		aetherProbe.running = true;
	}
	function moveAetherSelection(delta, wrap) {
		const n = nav.aetherFiltered.length;
		if (n === 0) { nav.selectedAether = -1; return; }
		const cur = nav.selectedAether < 0 ? 0 : nav.selectedAether;
		let next = cur + delta;
		if (wrap) {
			next = ((next % n) + n) % n;
		} else {
			if (next < 0) next = 0;
			else if (next >= n) next = n - 1;
		}
		nav.selectedAether = next;
	}
	function applyAetherBlueprint(name) {
		if (!name) return;
		nav.run(nav.aetherBin + " --apply-blueprint " + JSON.stringify(name));
		nav.aetherVisible = false;
	}
	onAetherQueryChanged: {
		nav.selectedAether = nav.aetherFiltered.length > 0 ? 0 : -1;
	}

	// ===== TOOLTIP =====
	property string tooltipText: ""
	property real tooltipBarX: 0; property real tooltipBarY: 0
	property bool tooltipShown: false
	property int barHeight: 28
	function showTooltip(text, x, y) { tooltipText = text; tooltipBarX = x; tooltipBarY = y; tooltipShown = true }
	function hideTooltip(text) { if (!text || tooltipText === text) tooltipShown = false }

	Component.onCompleted: nav._updateAudioIcon()

	// ===== SURFACE =====
	Bar { root: nav }

	// ===== TOOLTIP =====
	TooltipOverlay { root: nav }

	// ===== CLOCK TIMER =====
	Timer {
		interval: 1000; running: true; repeat: true; triggeredOnStart: true
		onTriggered: {
			var d = new Date()
			hh = d.getHours().toString().padStart(2, "0")
			mm = d.getMinutes().toString().padStart(2, "0")
			dow = d.toLocaleString(Qt.locale(), "ddd")
			dd = d.getDate().toString().padStart(2, "0")
			mon = d.toLocaleString(Qt.locale(), "MMM")
		}
	}

	// ===== CPU PROBE =====
	Process {
		id: cpuProc; running: false
		command: ["bash", "-lc",
			"read _ a b c d _ < <(grep '^cpu ' /proc/stat); "
			+ "sleep 0.15; "
			+ "read _ e f g h _ < <(grep '^cpu ' /proc/stat); "
			+ "du=$(( (e+f+g) - (a+b+c) )); dt=$(( (e+f+g+h) - (a+b+c+d) )); "
			+ "cpu=$(( dt>0 ? du*100/dt : 0 )); "
			+ "printf '%d' \"$cpu\""]
		stdout: SplitParser { splitMarker: "\n"; onRead: (d) => { var v = parseInt(d.trim()); if (!isNaN(v)) nav.cpuVal = v } }
	}
	Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: cpuProc.running = true }

	// ===== MEMORY PROBE =====
	Process {
		id: memProc; running: false
		command: ["bash", "-lc", "awk '/MemTotal/{t=$2}/MemAvailable/{m=$2}END{printf \"%d\",(t-m)*100/t}' /proc/meminfo"]
		stdout: SplitParser { splitMarker: "\n"; onRead: (d) => { var v = parseInt(d.trim()); if (!isNaN(v)) nav.memVal = v } }
	}
	Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: memProc.running = true }

	// ===== RECORDING PROBE =====
	Process {
		id: recProc; running: false
		command: ["bash", "/home/bldnwine/.config/hypr/scripts/recording-indicator.sh"]
		stdout: SplitParser { splitMarker: "\n"; onRead: (d) => { try { var o = JSON.parse(d.trim()); nav.recordingActive = o.class === "recording" } catch(e) {} } }
	}
	Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: recProc.running = true }

	// ===== KEYBOARD LED PROBE =====
	Process {
		id: kbProc; running: false
		command: ["bash", "-c",
			"c=0; n=0; "
			+ "for f in /sys/class/leds/*capslock*/brightness; do [ -f \"$f\" ] && c=$(cat \"$f\"); done; "
			+ "for f in /sys/class/leds/*numlock*/brightness; do [ -f \"$f\" ] && n=$(cat \"$f\"); done; "
			+ "echo \"$c$n\""]
		stdout: SplitParser { splitMarker: "\n"; onRead: (d) => { var s = d.trim(); if (s.length >= 2) { nav.capsOn = s[0] === "1"; nav.numOn = s[1] === "1" } } }
	}
	Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: kbProc.running = true }

	// ===== PROTON VPN PROBE =====
	Process {
		id: protonProc; running: false
		command: ["bash", "-c", "ls /sys/class/net/ 2>/dev/null | grep -q '^proton' && echo connected"]
		stdout: SplitParser { splitMarker: "\n"; onRead: (d) => { nav.protonConnected = d.trim().length > 0 } }
	}
	Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: protonProc.running = true }

	// ===== NETWORK PROBE =====
	Process {
		id: netProbe; running: false
		command: ["bash", "-lc",
			"type=none; "
			+ "for w in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do "
			+ "  link=$(iw dev \"$w\" link 2>/dev/null); "
			+ "  dbm=$(printf '%s\\n' \"$link\" | awk '/signal:/{print $2}'); "
			+ "  if [ -n \"$dbm\" ]; then "
			+ "    pct=$((2 * (dbm + 100))); "
			+ "    [ $pct -lt 0 ] && pct=0; "
			+ "    [ $pct -gt 100 ] && pct=100; "
			+ "    type=\"wifi:$pct\"; break; "
			+ "  fi; "
			+ "done; "
			+ "printf '%s' \"$type\""]
		stdout: StdioCollector { onStreamFinished: { var t = this.text.trim(); if (t.startsWith("wifi:")) { var sig = parseInt(t.slice(5)) || 0; nav.netIcon = nav.wifiBarsGlyph(sig); nav.netKind = 1; nav.wifiSignal = sig } else { nav.netIcon = "󰤮"; nav.netKind = 0; nav.wifiSignal = 0 } } }
	}
	Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: netProbe.running = true }

	// ===== BATTERY PROBE =====
	Process {
		id: batProc; running: false
		command: ["bash", "-c",
			"for f in /sys/class/power_supply/BAT*/uevent; do "
			+ "  [ -f \"$f\" ] || continue; "
			+ "  . \"$f\"; "
			+ "  echo \"${POWER_SUPPLY_CAPACITY:-0} ${POWER_SUPPLY_STATUS:-Unknown}\"; "
			+ "done"]
		stdout: SplitParser { splitMarker: "\n"; onRead: (d) => { var s = d.trim().split(" "); if (s.length >= 2) { nav.batVal = parseInt(s[0]) || 0; nav.batState = s[1] } } }
	}
	Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: batProc.running = true }

	// ===== WORKSPACE PROBE (2 Hz) =====
	Process {
		id: wsProbe; running: false
		command: ["bash", "-lc",
			"act=$(hyprctl activeworkspace -j 2>/dev/null | sed -n 's/.*\"id\": *\\([0-9]*\\).*/\\1/p' | head -1); "
			+ "ids=$(hyprctl workspaces -j 2>/dev/null | tr ',' '\\n' | sed -n 's/.*\"id\": *\\([0-9]*\\).*/\\1/p' | sort -nu | paste -sd,); "
			+ "printf '%s|%s' \"${act:-1}\" \"${ids:-1}\""]
		stdout: StdioCollector {
			onStreamFinished: {
				const p = this.text.split("|");
				if (p.length !== 2) return;
				const next = parseInt(p[0]) || 1;
				if (next > nav.activeWs) nav.lastDirection = 1;
				else if (next < nav.activeWs) nav.lastDirection = -1;
				nav.activeWs = next;
				const have = p[1].split(",").map(s => parseInt(s)).filter(n => !isNaN(n));
				nav.existingWs = [...new Set([...have, 1, 2, 3, 4, 5])].sort((a,b) => a-b).slice(0, 9);
			}
		}
	}
	Timer { interval: 500; running: true; repeat: true; triggeredOnStart: true; onTriggered: wsProbe.running = true }

	// ===== AUDIO PROBE (2 s) =====
	Process {
		id: audioProbe; running: false
		command: ["bash", "-lc",
			"v=$(pamixer --get-volume 2>/dev/null || echo 0); "
			+ "m=$(pamixer --get-mute 2>/dev/null || echo false); "
			+ "printf '%s|%s' \"$v\" \"$m\""]
		stdout: StdioCollector {
			onStreamFinished: {
				const p = this.text.split("|");
				if (p.length !== 2) return;
				nav.audioVol = parseInt(p[0]) || 0;
				nav.audioMuted = p[1].trim() === "true";
				nav._updateAudioIcon();
			}
		}
	}
	Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: audioProbe.running = true }

	// ===== BLUEPRINT PROBE =====
	Process {
		id: aetherProbe
		running: false
		command: [nav.aetherBin, "--list-blueprints", "--json"]
		stdout: StdioCollector {
			onStreamFinished: {
				let arr = [];
				try {
					const obj = JSON.parse(this.text);
					arr = (obj.blueprints || []).slice();
				} catch (_) { arr = []; }
				arr.sort((a, b) => (Number(b.timestamp) || 0) - (Number(a.timestamp) || 0));
				nav.aetherBlueprints = arr;
				nav.aetherLoading = false;
				nav.selectedAether = arr.length > 0 ? 0 : -1;
			}
		}
	}

	// ===== MPRIS TRACKING =====
	Timer {
		interval: 1000; running: true; repeat: true; triggeredOnStart: true
		onTriggered: {
			var ps = Mpris.players, found = null
			for (var i = 0; i < ps.length; i++) { if (ps[i].isPlaying) { found = ps[i]; break } }
			if (!found && ps.length > 0) found = ps[0]
			nav.mprisPlayer = found
			musicTitle = found ? found.trackTitle || "" : ""
			musicArtist = found ? found.trackArtist || "" : ""
		}
	}

	// ===== BLUEPRINTS POPUP =====
	BlueprintsPopup { root: nav }

	// ===== IPC =====
	IpcHandler {
		target: "aether"
		function toggle(): void {
			if (nav.aetherVisible) nav.aetherVisible = false;
			else nav.openAether();
		}
		function open(): void  { nav.openAether(); }
		function close(): void { nav.aetherVisible = false; }
	}
}
