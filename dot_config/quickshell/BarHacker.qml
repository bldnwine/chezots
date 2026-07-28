import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// The "hackerman" bar face: a tactical terminal status line in the vein of
// Mr. Robot / Jack Ryan ops dashboards. Reads the exact same `root` state
// as the zen Bar — no new probes — and reframes it as labelled telemetry
// with mini gauges, a live timestamp, a `user@host:~$` prompt with a
// blinking block cursor, faint CRT scanlines, and accent corner brackets.
//
// Chrome stays palette-aware: a deep tinted black derived from `paper`, the
// theme `seal` for accents/alerts. Sharp corners by choice — a terminal is
// a slab, so cloud/round modes don't apply here.
PanelWindow {
    id: hk
    required property var root

    color: "transparent"
    anchors {
        top:    hk.root.barEdge !== "bottom"
        bottom: hk.root.barEdge !== "top"
        left:   hk.root.barEdge !== "right"
        right:  hk.root.barEdge !== "left"
    }
    implicitHeight: hk.root.isHorizontal ? hk.root.barHeight : 0
    implicitWidth:  hk.root.isHorizontal ? 0 : hk.root.barHeight
    exclusiveZone:  hk.root.barHeight

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "omarchy-menu"

    // ---------- Palette derivations ----------
    readonly property color deepBg: Qt.rgba(hk.root.paper.r * 0.30, hk.root.paper.g * 0.30, hk.root.paper.b * 0.30, 0.97)
    readonly property color dim:    Qt.rgba(hk.root.ink.r, hk.root.ink.g, hk.root.ink.b, 0.45)
    readonly property color dimmer: Qt.rgba(hk.root.ink.r, hk.root.ink.g, hk.root.ink.b, 0.22)
    readonly property color line:   Qt.rgba(hk.root.seal.r, hk.root.seal.g, hk.root.seal.b, 0.5)

    // ---------- Live clock ----------
    // Self-contained 1Hz tick so the readout shows real seconds, rather than
    // borrowing the telemetry probe's hh/mm (which lag a beat and carry no
    // seconds). Gated on `visible`, so the hidden face costs nothing.
    property string hkHH: "--"
    property string hkMM: "--"
    property string hkSS: "--"
    function _pad(n) { return String(n).padStart(2, "0"); }
    Timer {
        running: hk.visible
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const d = new Date();
            hk.hkHH = hk._pad(d.getHours());
            hk.hkMM = hk._pad(d.getMinutes());
            hk.hkSS = hk._pad(d.getSeconds());
        }
    }

    // ---------- Operator identity (one-shot) ----------
    property string sysUser: "operator"
    property string sysHost: "localhost"
    Process {
        running: true
        command: ["bash", "-lc",
            "printf '%s\\t%s' \"${USER:-operator}\" \"$(uname -n 2>/dev/null || echo localhost)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.split("\t");
                if (p.length === 2) {
                    hk.sysUser = p[0] || "operator";
                    hk.sysHost = (p[1] || "localhost").trim();
                }
            }
        }
    }

    // ---------- Alert state ----------
    // One amber-light condition that flips the trailing status word and a
    // couple of value colours: pinned CPU, or a low battery that's actually
    // draining (a low-but-charging pack isn't an alert).
    readonly property bool alert:
        hk.root.cpuVal > 80
        || (hk.root.batVal <= 10 && hk.root.batState === "Discharging")

    // ---------- Popup anchors ----------
    // Calendar/Weather popups read root.*AnchorItem at open time. Whichever
    // bar is mapped must own them, and the right item depends on orientation
    // (the off-axis face's items carry stale coordinates).
    function claimAnchors() {
        hk.root.calendarAnchorItem = hk.root.isHorizontal ? clockTag : clockTagV;
        hk.root.weatherAnchorItem  = hk.root.isHorizontal ? wxCell   : wxCellV;
    }
    onVisibleChanged: if (visible) hk.claimAnchors();
    Connections {
        target: hk.root
        function onBarEdgeChanged() { if (hk.visible) hk.claimAnchors(); }
    }

    // ---------- Background + chrome ----------
    Rectangle {
        id: bg
        anchors.fill: parent
        color: hk.deepBg

        // Idle dim, same slow 6s states/transitions as the zen bar so the
        // two faces breathe identically when the session goes quiet.
        opacity: 1.0
        states: State {
            name: "idle"
            when: hk.root.isIdle
            PropertyChanges { target: bg; opacity: 0.72 }
        }
        transitions: [
            Transition { to: "idle";   NumberAnimation { property: "opacity"; duration: 6000; easing.type: Easing.OutQuart } },
            Transition { from: "idle"; NumberAnimation { property: "opacity"; duration: 6000; easing.type: Easing.OutQuad } }
        ]

        // CRT scanlines: faint 1px rasters every 3px down the slab. Cheap
        // (~9 lines at 26px tall), clipped, barely-there opacity.
        Item {
            anchors.fill: parent
            clip: true
            opacity: 0.06
            Repeater {
                model: Math.ceil(bg.height / 3)
                delegate: Rectangle {
                    required property int index
                    width: bg.width
                    height: 1
                    y: index * 3
                    color: hk.root.ink
                }
            }
        }

        // Inner-edge hairline facing the screen, tinted with the accent so
        // the bar reads as a lit instrument edge.
        Rectangle {
            visible: hk.root.isHorizontal
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top:    hk.root.barEdge === "bottom" ? parent.top    : undefined
            anchors.bottom: hk.root.barEdge === "top"    ? parent.bottom : undefined
            height: 1
            color: hk.line
        }
        Rectangle {
            visible: !hk.root.isHorizontal
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: hk.root.barEdge === "left"  ? parent.right : undefined
            anchors.left:  hk.root.barEdge === "right" ? parent.left  : undefined
            width: 1
            color: hk.line
        }
    }

    // ======================================================================
    // HORIZONTAL FACE
    // ======================================================================
    Item {
        visible: hk.root.isHorizontal
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10

        // Centered timestamp, floating over the RowLayout's flex spacer
        // (same trick the zen bar uses for its clock). Click toggles the
        // calendar.
        Item {
            id: clockTag
            anchors.centerIn: parent
            z: 10
            width: clockRow.implicitWidth + 16
            height: parent.height

            Bloom { id: clockBloom; root: hk.root }

            Row {
                id: clockRow
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: hk.hkHH + ":" + hk.hkMM + ":" + hk.hkSS
                    color: clockMouse.containsMouse ? hk.root.seal : hk.root.ink
                    font.family: hk.root.mono
                    font.pixelSize: 12
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
            }

            MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: clockBloom.fire(mouseX, mouseY)
                onClicked: {
                    if (hk.root.calendarVisible) hk.root.calendarVisible = false;
                    else hk.root.openCalendar();
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 7

            // -------- LEFT: prompt + cursor --------
            Item {
                id: promptItem
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: hk.root.barHeight
                Layout.preferredWidth: promptRow.implicitWidth + 4

                Bloom { id: promptBloom; root: hk.root }

                Row {
                    id: promptRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -1
                    spacing: 0
                    Text {
                        text: hk.sysUser
                        color: hk.root.seal
                        font.family: hk.root.mono
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                    Text { text: "@"; color: hk.dim; font.family: hk.root.mono; font.pixelSize: 11 }
                    Text {
                        text: hk.sysHost
                        color: hk.root.ink
                        font.family: hk.root.mono
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                    Text { text: ":~$"; color: hk.dim; font.family: hk.root.mono; font.pixelSize: 11 }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onEntered: promptBloom.fire(mouseX, mouseY)
                    onClicked: (e) => {
                        if (e.button === Qt.RightButton) hk.root.run("xdg-terminal-exec");
                        else hk.root.paletteToggleRequested();
                    }
                }
            }

            // dim divider
            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 12; Layout.alignment: Qt.AlignVCenter; color: hk.dimmer }

            // -------- LEFT: workspace sectors --------
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "WS"
                color: hk.dim
                font.family: hk.root.mono
                font.pixelSize: 9
                font.letterSpacing: 1
                font.weight: Font.Medium
            }
            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 3
                Repeater {
                    model: 10
                    delegate: Item {
                        required property int index
                        readonly property int wsId: index + 1
                        readonly property bool active: hk.root.activeWs === wsId
                        readonly property bool present: hk.root.existingWs.indexOf(wsId) !== -1
                        width: tag.implicitWidth
                        height: hk.root.barHeight

                        Text {
                            id: tag
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -1
                            text: String(parent.wsId).padStart(2, "0")
                            color: parent.active ? hk.root.seal : (parent.present ? hk.root.ink : hk.dimmer)
                            opacity: parent.active ? 1.0 : (parent.present ? 0.85 : 0.5)
                            font.family: hk.root.mono
                            font.pixelSize: 11
                            font.weight: parent.active ? Font.Bold : Font.Normal
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        // Active sector gets a lit underbar.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            width: tag.implicitWidth
                            height: 2
                            radius: 1
                            color: hk.root.seal
                            visible: parent.active
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: hk.root.focusWorkspace(parent.wsId)
                        }
                    }
                }
            }

            // flex middle — the centered clock floats over this
            Item { Layout.fillWidth: true }

            // -------- RIGHT: telemetry readouts --------
            // Now playing, when present. Left toggles, right skips.
            HackerStat {
                root: hk.root
                visible: hk.root.musicTitle.length > 0
                glyph: hk.root.musicPlaying ? hk.root.icoMusic : hk.root.icoPause
                value: {
                    const t = hk.root.musicTitle;
                    return t.length > 18 ? t.slice(0, 16) + ".." : t;
                }
                valueColor: hk.root.seal
                tooltip: hk.root.musicArtist.length > 0
                         ? hk.root.musicTitle + " - " + hk.root.musicArtist
                         : hk.root.musicTitle
                onActivated: hk.root.musicToggle()
                onRightActivated: hk.root.musicNext()
            }

            HackerStat {
                root: hk.root
                label: "CPU"
                value: hk.root.cpuVal + "%"
                gauge: hk.root.cpuVal
                valueColor: hk.root.cpuVal > 80 ? hk.root.seal : hk.root.ink
                tooltip: "CPU " + Math.round(hk.root.cpuVal) + "%"
                onActivated: hk.root.run("omarchy-launch-or-focus-tui btop")
            }

            HackerStat {
                root: hk.root
                label: "MEM"
                value: hk.root.memVal + "%"
                gauge: hk.root.memVal
                valueColor: hk.root.memVal > 90 ? hk.root.seal : hk.root.ink
                tooltip: "Memory " + hk.root.memVal + "%"
                onActivated: hk.root.run("omarchy-launch-or-focus-tui btop")
            }

            HackerStat {
                root: hk.root
                glyph: hk.root.netIcon
                value: {
                    if (hk.root.netKind === "eth") return "LINK";
                    if (hk.root.netKind === "wifi") {
                        const s = hk.root.wifiSsid || "WIFI";
                        return s.length > 10 ? s.slice(0, 8) + ".." : s;
                    }
                    return "OFFLINE";
                }
                valueColor: hk.root.netKind === "none" ? hk.root.seal : hk.root.ink
                gauge: hk.root.netKind === "wifi" ? hk.root.wifiSignal : -1
                tooltip: {
                    if (hk.root.netKind === "eth") return "Ethernet";
                    if (hk.root.netKind === "wifi")
                        return "Wi-Fi · " + (hk.root.wifiSsid || "(hidden)") + " · " + hk.root.wifiSignal + "%";
                    return "Offline";
                }
                onActivated: hk.root.run("ghostty --title=impala -e impala")
            }

            HackerStat {
                root: hk.root
                glyph: hk.root.audioIcon
                value: hk.root.audioMuted ? "MUTE" : hk.root.audioVol + "%"
                gauge: hk.root.audioMuted ? -1 : hk.root.audioVol
                valueColor: hk.root.audioMuted ? hk.root.seal : hk.root.ink
                tooltip: hk.root.audioMuted
                         ? "Audio muted · " + hk.root.audioVol + "%"
                         : "Audio " + hk.root.audioVol + "%"
                onActivated: hk.root.run("pavucontrol")
                onMiddleActivated: hk.root.run("pamixer -t")
                onRightActivated: hk.root.run("~/.config/waybar/scripts/pulse_switch.sh")
            }

            HackerStat {
                root: hk.root
                glyph: hk.root.btIcon
                value: hk.root.btPowered ? (hk.root.btCount > 0 ? hk.root.btCount + "DEV" : "ON") : "OFF"
                valueColor: hk.root.btPowered ? hk.root.ink : hk.dim
                tooltip: {
                    if (!hk.root.btPowered) return "Bluetooth off";
                    return hk.root.btCount > 0
                        ? "Bluetooth · " + hk.root.btCount + " connected"
                        : "Bluetooth on";
                }
                onActivated: hk.root.run("ghostty --title='Bluetooth Manager' -e bluetui")
            }

            HackerStat {
                id: wxCell
                root: hk.root
                glyph: hk.root.weatherUnavailable ? "?"
                       : (hk.root.weatherLoaded ? hk.root.weatherIcon : "·")
                value: hk.root.weatherLoaded ? (Math.round(hk.root.weatherTempC) + "°") : ""
                valueColor: hk.root.weatherUnavailable ? hk.dim : hk.root.ink
                tooltip: hk.root.weatherUnavailable
                         ? "Weather offline"
                         : (hk.root.weatherLoaded
                            ? hk.root.weatherDesc + " · " + Math.round(hk.root.weatherTempC) + "°C"
                            : "Weather…")
                onActivated: {
                    if (hk.root.weatherVisible) hk.root.weatherVisible = false;
                    else hk.root.openWeather();
                }
                onRightActivated: hk.root.refreshWeather()
            }

            HackerStat {
                root: hk.root
                visible: hk.root.omarchyUpdateAvailable
                value: "UPD"
                valueColor: hk.root.seal
                blink: true
                tooltip: hk.root.omarchyLatestTag
                         ? "Omarchy update available · " + hk.root.omarchyLatestTag
                         : "Omarchy update available"
                onActivated: hk.root.openOmarchyUpdate()
            }

            HackerStat {
                root: hk.root
                label: "BAT"
                value: hk.root.batVal + "%"
                gauge: hk.root.batVal
                valueColor: hk.root.batVal <= 10 ? hk.root.seal
                            : hk.root.batVal <= 20 ? hk.root.indigo : hk.root.ink
                gaugeColor: hk.root.batState === "Charging" || hk.root.batState === "Full"
                            ? hk.root.indigo : (hk.root.batVal <= 20 ? hk.root.seal : hk.root.ink)
                tooltip: {
                    let s = "Battery " + hk.root.batVal + "%";
                    if (hk.root.batPower >= 0.05) {
                        const sign = hk.root.batState === "Charging" ? "+"
                                   : hk.root.batState === "Discharging" ? "-" : "";
                        s += "  " + sign + hk.root.batPower.toFixed(1) + " W";
                    }
                    return s;
                }
                onActivated: hk.root.run("omarchy-menu power")
            }

            // dim divider
            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 12; Layout.alignment: Qt.AlignVCenter; color: hk.dimmer }

            // Status word: OK in calm indigo, ALERT in seal when pinned.
            Text {
                property real alertPulse: 1.0
                Layout.alignment: Qt.AlignVCenter
                text: hk.alert ? "[ALERT]" : "[ OK ]"
                color: hk.alert ? hk.root.seal : hk.root.indigo
                font.family: hk.root.mono
                font.pixelSize: 9
                font.letterSpacing: 1
                font.weight: Font.Medium
                opacity: hk.alert ? alertPulse : 0.85
                SequentialAnimation on alertPulse {
                    running: hk.alert && hk.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 450 }
                    NumberAnimation { to: 1.0; duration: 450 }
                }
            }

            // Edge mover — same cycleBarEdge as the zen bar.
            HackerStat {
                root: hk.root
                glyph: hk.root.edgeArrow()
                tooltip: "Move bar"
                onActivated: hk.root.cycleBarEdge()
            }
        }
    }

    // ======================================================================
    // VERTICAL FACE (compact, functional — for left/right edges)
    // ======================================================================
    ColumnLayout {
        visible: !hk.root.isHorizontal
        anchors.fill: parent
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 6

        // prompt glyph -> palette
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "❯"
            color: hk.root.seal
            font.family: hk.root.mono
            font.pixelSize: 14
            font.weight: Font.Bold
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (e) => {
                    if (e.button === Qt.RightButton) hk.root.run("xdg-terminal-exec");
                    else hk.root.paletteToggleRequested();
                }
            }
        }

        Rectangle { Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 12; Layout.preferredHeight: 1; color: hk.dimmer }

        // present/active workspace numbers, stacked
        Repeater {
            model: 10
            delegate: Text {
                required property int index
                readonly property int wsId: index + 1
                readonly property bool active: hk.root.activeWs === wsId
                readonly property bool present: hk.root.existingWs.indexOf(wsId) !== -1
                visible: active || present
                Layout.alignment: Qt.AlignHCenter
                text: String(wsId).padStart(2, "0")
                color: active ? hk.root.seal : hk.root.ink
                opacity: active ? 1.0 : 0.7
                font.family: hk.root.mono
                font.pixelSize: 11
                font.weight: active ? Font.Bold : Font.Normal
                Behavior on color { ColorAnimation { duration: 140 } }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: hk.root.focusWorkspace(parent.wsId)
                }
            }
        }

        Item { Layout.fillHeight: true }

        // clock, HH over MM
        Item {
            id: clockTagV
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: hk.root.barHeight
            Layout.preferredHeight: hhTxt.implicitHeight + mmTxt.implicitHeight + 2
            Text {
                id: hhTxt
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.verticalCenter
                text: hk.hkHH
                color: clockMouseV.containsMouse ? hk.root.seal : hk.root.ink
                font.family: hk.root.mono
                font.pixelSize: 11
                font.weight: Font.Medium
                Behavior on color { ColorAnimation { duration: 180 } }
            }
            Text {
                id: mmTxt
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                text: hk.hkMM
                color: clockMouseV.containsMouse ? hk.root.seal : hk.root.ink
                font.family: hk.root.mono
                font.pixelSize: 11
                font.weight: Font.Medium
                Behavior on color { ColorAnimation { duration: 180 } }
            }
            MouseArea {
                id: clockMouseV
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (hk.root.calendarVisible) hk.root.calendarVisible = false;
                    else hk.root.openCalendar();
                }
            }
        }

        Rectangle { Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 12; Layout.preferredHeight: 1; color: hk.dimmer }

        // compact status glyphs
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: hk.root.cpuVal + ""
            color: hk.root.cpuVal > 80 ? hk.root.seal : hk.root.ink
            font.family: hk.root.mono
            font.pixelSize: 9
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                onClicked: hk.root.run("omarchy-launch-or-focus-tui btop") }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: hk.root.netIcon
            color: hk.root.netKind === "none" ? hk.root.seal : hk.root.ink
            font.family: hk.root.mono
            font.pixelSize: 12
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                onClicked: hk.root.run("ghostty --title=impala -e impala") }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: hk.root.audioIcon
            color: hk.root.audioMuted ? hk.root.seal : hk.root.ink
            font.family: hk.root.mono
            font.pixelSize: 12
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: (e) => { if (e.button === Qt.RightButton) hk.root.run("~/.config/waybar/scripts/pulse_switch.sh"); else if (e.button === Qt.MiddleButton) hk.root.run("pamixer -t"); else hk.root.run("pavucontrol"); } }
        }
        // weather glyph (anchor target in vertical mode)
        Text {
            id: wxCellV
            Layout.alignment: Qt.AlignHCenter
            text: hk.root.weatherUnavailable ? "?" : (hk.root.weatherLoaded ? hk.root.weatherIcon : "·")
            color: hk.root.weatherUnavailable ? hk.dim : hk.root.ink
            font.family: hk.root.mono
            font.pixelSize: 12
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                onClicked: { if (hk.root.weatherVisible) hk.root.weatherVisible = false; else hk.root.openWeather(); } }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: hk.root.batVal + ""
            color: hk.root.batVal <= 10 ? hk.root.seal : hk.root.batVal <= 20 ? hk.root.indigo : hk.root.ink
            font.family: hk.root.mono
            font.pixelSize: 9
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                onClicked: hk.root.run("omarchy-menu power") }
        }

        Rectangle { Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 12; Layout.preferredHeight: 1; color: hk.dimmer }

        // edge mover
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: hk.root.edgeArrow()
            color: hk.root.ink
            font.family: hk.root.mono
            font.pixelSize: 12
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                onClicked: hk.root.cycleBarEdge() }
        }
    }
}
