import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Plain White Rose bar face. It reuses the main bar's actions and state,
// but renders them as editorial rows: rectangular cells, icons, and borders
// for emphasis while still following the live omarchy theme palette.
PanelWindow {
    id: wr

    required property var root

    readonly property color bg: root.bg
    readonly property color text: root.ink
    readonly property color muted: root.inkDeep
    readonly property color faint: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.45)
    readonly property color line: root.sep
    readonly property color lineStrong: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.52)
    readonly property color surface: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)

    readonly property string logoSource:
        "file://" + Quickshell.env("HOME") + "/Code/whiterose/site/assets/logo.svg"

    function trunc(s, n) {
        if (!s) return "";
        return s.length > n ? s.slice(0, n - 2) + ".." : s;
    }

    function batteryTip() {
        let s = "Battery " + wr.root.batVal + "%";
        if (wr.root.batPower >= 0.05) {
            const sign = wr.root.batState === "Charging" ? "+"
                       : wr.root.batState === "Discharging" ? "-" : "";
            s += "  " + sign + wr.root.batPower.toFixed(1) + " W";
        }
        return s;
    }

    function claimAnchors() {
        const horiz = wr.root.isHorizontal;
        wr.root.calendarAnchorItem = horiz ? clockItem : clockItemV;
        wr.root.displayAnchorItem = horiz ? clockItem : clockItemV;
        wr.root.systemAnchorItem = horiz ? systemMod : systemModV;
        wr.root.aiAnchorItem = horiz ? aiMod : aiModV;
        wr.root.notificationAnchorItem = horiz ? notifMod : notifModV;
        wr.root.btAnchorItem = horiz ? btMod : btModV;
        wr.root.networkAnchorItem = horiz ? netMod : netModV;
        wr.root.warpAnchorItem = horiz ? warpMod : warpModV;
        wr.root.audioAnchorItem = horiz ? audioMod : audioModV;
    }

    color: "transparent"
    anchors {
        top:    wr.root.barEdge !== "bottom"
        bottom: wr.root.barEdge !== "top"
        left:   wr.root.barEdge !== "right"
        right:  wr.root.barEdge !== "left"
    }
    implicitHeight: wr.root.isHorizontal ? wr.root.barHeight : 0
    implicitWidth:  wr.root.isHorizontal ? 0 : wr.root.barHeight
    exclusiveZone:  wr.root.barHeight

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "omarchy-menu"

    onVisibleChanged: if (visible) wr.claimAnchors()
    Connections {
        target: wr.root
        function onBarEdgeChanged() { if (wr.visible) wr.claimAnchors(); }
    }

    Rectangle {
        id: backplate
        anchors.fill: parent
        color: wr.root.barTransparent ? "transparent" : Qt.rgba(wr.bg.r, wr.bg.g, wr.bg.b, wr.root.barOpacity)

        Rectangle {
            visible: wr.root.isHorizontal
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top:    wr.root.barEdge === "bottom" ? parent.top    : undefined
            anchors.bottom: wr.root.barEdge === "top"    ? parent.bottom : undefined
            height: 1
            color: wr.line
        }
        Rectangle {
            visible: !wr.root.isHorizontal
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: wr.root.barEdge === "left"  ? parent.right : undefined
            anchors.left:  wr.root.barEdge === "right" ? parent.left  : undefined
            width: 1
            color: wr.line
        }
    }

    Item {
        visible: wr.root.isHorizontal
        anchors.fill: parent

        Item {
            id: clockItem
            anchors.centerIn: parent
            width: clockText.implicitWidth + 18
            height: parent.height
            z: 10

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                color: "transparent"
                border.width: 0
                border.color: wr.lineStrong
            }
            Text {
                id: clockText
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                text: wr.root.dow + " " + wr.root.dd + " - " + wr.root.hh + ":" + wr.root.mm
                color: wr.text
                font.family: wr.root.mono
                font.pixelSize: 12
                font.letterSpacing: 2
                font.weight: Font.Medium
            }
            Timer {
                id: clockTipDelay
                interval: 180
                onTriggered: {
                    const p = clockItem.mapToItem(null, clockItem.width / 2, clockItem.height / 2);
                    wr.root.showTooltip("Calendar", p.x, p.y);
                }
            }
            MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onEntered: clockTipDelay.restart()
                onExited: { clockTipDelay.stop(); wr.root.hideTooltip("Calendar"); }
                onClicked: function(mouse) {
                    clockTipDelay.stop();
                    wr.root.hideTooltip("Calendar");
                    if (mouse.button === Qt.RightButton) {
                        wr.root.paletteToggleRequested();
                    } else {
                        if (wr.root.calendarVisible) wr.root.calendarVisible = false;
                        else wr.root.openCalendar();
                    }
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 4

            WhiteRoseCell {
                root: wr.root
                imageSource: wr.logoSource
                tooltip: "Menu"
                borderless: true
                minWidth: 28
                maxWidth: 28
                iconSize: 14
                onActivated: wr.root.paletteToggleRequested()
                onRightActivated: wr.root.run("xdg-terminal-exec")
            }

            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 14; Layout.alignment: Qt.AlignVCenter; color: wr.line }

            Repeater {
                model: 10
                delegate: Workspace {
                    required property int index
                    root: wr.root
                    wsId: index + 1
                    label: wr.root.indexKanji(index + 1)
                    active: wr.root.activeWs === (index + 1)
                    present: wr.root.existingWs.indexOf(index + 1) !== -1
                    onActivated: wr.root.focusWorkspace(index + 1)
                }
            }

            Item { Layout.fillWidth: true }

            Item {
                id: musicItem
                readonly property bool present: wr.root.musicTitle.length > 0
                readonly property real contentW: musicRow.width + 12
                property real openW: present ? contentW + 8 : 0
                Behavior on openW { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                Component.onCompleted: wr.root.musicAnchorItem = musicItem

                visible: present || openW > 0.5
                Layout.preferredWidth: openW
                Layout.preferredHeight: 16
                Layout.alignment: Qt.AlignVCenter

                readonly property string tipText: wr.root.musicArtist.length > 0
                                                  ? wr.root.musicTitle + " - " + wr.root.musicArtist
                                                  : wr.root.musicTitle

                Rectangle {
                    id: musicPill
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - 8)
                    height: parent.height
                    radius: height / 2
                    color: wr.root.accent
                    clip: true
                    opacity: musicMouse.containsMouse ? 1.0 : 0.9
                    Behavior on opacity { NumberAnimation { duration: 90 } }

                    Row {
                        id: musicRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            id: musicIcon
                            anchors.verticalCenter: parent.verticalCenter
                            text: wr.root.icoMusic
                            color: wr.root.paper
                            font.family: wr.root.mono
                            font.pixelSize: 9
                        }

                        Text {
                            id: musicLabel
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property int maxChars:
                                Math.max(2, Math.floor(140 / chMetric.advanceWidth))
                            readonly property bool truncated:
                                wr.root.musicTitle.length > maxChars
                            text: truncated
                                  ? wr.root.musicTitle.slice(0, maxChars - 2) + ".."
                                  : wr.root.musicTitle
                            color: wr.root.paper
                            font.family: wr.root.mono
                            font.pixelSize: 10
                            font.weight: Font.Medium

                            TextMetrics {
                                id: chMetric
                                font: musicLabel.font
                                text: "0"
                            }
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        width: 40
                        radius: parent.radius
                        visible: musicLabel.truncated
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(wr.root.accent.r, wr.root.accent.g, wr.root.accent.b, 0) }
                            GradientStop { position: 0.6; color: wr.root.accent }
                            GradientStop { position: 1.0; color: wr.root.accent }
                        }
                    }
                }

                Timer {
                    id: musicTipDelay
                    interval: 180
                    onTriggered: {
                        const p = musicItem.mapToItem(null, musicItem.width / 2, musicItem.height / 2);
                        wr.root.showTooltip(musicItem.tipText, p.x, p.y);
                    }
                }

                MouseArea {
                    id: musicMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton | Qt.XButton1 | Qt.XButton2
                    cursorShape: Qt.PointingHandCursor
                    onEntered: musicTipDelay.restart()
                    onExited:  { musicTipDelay.stop(); wr.root.hideTooltip(musicItem.tipText); }
                    onClicked: (e) => {
                        musicTipDelay.stop();
                        wr.root.hideTooltip(musicItem.tipText);
                        if (e.button === Qt.RightButton)       wr.root.musicNext();
                        else if (e.button === Qt.MiddleButton) wr.root.openMedia();
                        else if (e.button === Qt.XButton1)     wr.root.musicPrev();
                        else if (e.button === Qt.XButton2)     wr.root.musicNext();
                        else                                    wr.root.musicToggle();
                    }
                    onWheel: (wheel) => {
                        if (wheel.angleDelta.y > 0) wr.root.musicNextSource();
                        else if (wheel.angleDelta.y < 0) wr.root.musicPrevSource();
                    }
                }
            }

            Separator { root: wr.root }

            Tray { root: wr.root }

            // Right-side indicators read (left-to-right)
            //   cpu · ai · notifications · bluetooth · network · warp ·
            //   audio · battery · recording
            // matching Bar.qml's order and actions.
            WhiteRoseCell {
                id: systemMod
                root: wr.root
                glyph: "󰍛"
                tooltip: "CPU " + Math.round(wr.root.cpuVal) + "% · MEM " + Math.round(wr.root.memVal) + "%"
                strong: wr.root.cpuVal > 80
                borderless: true
                minWidth: 28
                maxWidth: 28
                fontSize: 13
                onActivated: {
                    if (wr.root.systemVisible) wr.root.systemVisible = false;
                    else wr.root.openSystem();
                }
                onRightActivated: wr.root.openDisplay()
            }

            Item {
                id: aiMod
                readonly property var ai: wr.root.aiService
                visible: wr.root.aiVisible || (aiMod.ai && aiMod.ai.agentRunning)
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: visible ? 28 : 0
                Layout.preferredHeight: wr.root.barHeight

                AiIcon {
                    anchors.centerIn: parent
                    iconSize: 13
                    fontFamily: wr.root.mono
                    glyphYOffset: -1
                    color: aiMod.ai && aiMod.ai.agentState === "working" ? wr.root.accent : wr.text
                    badgeColor: aiMod.ai && aiMod.ai.agentState === "action_needed" ? wr.root.warn : wr.root.seal
                    successColor: wr.root.accent
                    state: aiMod.ai ? aiMod.ai.agentState : "idle"
                }

                readonly property string tipText: aiMod.ai ? aiMod.ai.tipText : "Antigravity"

                Timer {
                    id: aiTipDelay
                    interval: 180
                    onTriggered: {
                        const p = aiMod.mapToItem(null, aiMod.width / 2, aiMod.height / 2);
                        wr.root.showTooltip(aiMod.tipText, p.x, p.y);
                    }
                }

                MouseArea {
                    id: aiMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onEntered: aiTipDelay.restart()
                    onExited: { aiTipDelay.stop(); wr.root.hideTooltip(aiMod.tipText); }
                    onClicked: (e) => {
                        aiTipDelay.stop();
                        wr.root.hideTooltip(aiMod.tipText);
                        if (e.button === Qt.MiddleButton) {
                            if (aiMod.ai) aiMod.ai.refresh(true);
                        } else {
                            if (wr.root.aiVisible) wr.root.aiVisible = false;
                            else wr.root.openAi();
                        }
                    }
                }
            }

            WhiteRoseCell {
                id: notifMod
                root: wr.root
                glyph: wr.root.doNotDisturb ? "󰂛" : "󰂚"
                tooltip: {
                    const s = wr.root.notificationCenterService;
                    const count = s ? s.unread : 0;
                    if (wr.root.doNotDisturb) return count > 0 ? "Notifications silenced · " + count + " unread" : "Notifications silenced";
                    if (count === 1) return "1 new notification";
                    if (count > 1) return count + " new notifications";
                    return "Notifications";
                }
                strong: wr.root.doNotDisturb
                borderless: true
                minWidth: 28
                maxWidth: 28
                fontSize: 12
                onActivated: {
                    if (wr.root.notificationCenterVisible) wr.root.notificationCenterVisible = false;
                    else wr.root.openNotificationCenter();
                }
                onRightActivated: wr.root.toggleDnd()

                Rectangle {
                    visible: {
                        const s = wr.root.notificationCenterService;
                        return s ? (s.unread > 0) : false;
                    }
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.top: parent.top
                    anchors.topMargin: 4
                    width: 5
                    height: 5
                    radius: 2.5
                    color: wr.root.accent
                }
            }

            WhiteRoseCell {
                id: btMod
                root: wr.root
                glyph: wr.root.btIcon
                tooltip: {
                    if (!wr.root.btPowered) return "Bluetooth off";
                    const conn = wr.root.btDevices.filter(d => d.connected);
                    if (conn.length === 0) return "Bluetooth on";
                    return conn.map(d => d.name + (d.battery > 0 ? " " + d.battery + "%" : "")).join("\n");
                }
                ink: wr.root.btPowered ? wr.text : wr.muted
                borderless: true
                minWidth: 28
                maxWidth: 28
                onActivated: {
                    if (wr.root.btVisible) wr.root.btVisible = false;
                    else wr.root.openBluetooth();
                }
            }

            WhiteRoseCell {
                id: netMod
                root: wr.root
                glyph: wr.root.netIcon
                tooltip: {
                    if (wr.root.netKind === "eth") return "Ethernet";
                    if (wr.root.netKind === "wifi") {
                        const name = wr.root.wifiSsid || "(hidden)";
                        return name + " · " + wr.root.wifiSignal + "%";
                    }
                    return "Offline";
                }
                ink: wr.root.wireprotonActiveIface.length > 0 ? wr.root.accent : (wr.root.netKind === "none" ? wr.muted : wr.text)
                borderless: true
                minWidth: 28
                maxWidth: 28
                fontSize: 11
                onActivated: {
                    if (wr.root.networkVisible) wr.root.networkVisible = false;
                    else wr.root.openNetwork();
                }
            }

            Item {
                id: warpMod
                readonly property var warp: wr.root.warpService
                visible: wr.root.warpVisible || (warpMod.warp && (warpMod.warp.active || warpMod.warp.connecting))
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: visible ? 28 : 0
                Layout.preferredHeight: wr.root.barHeight

                WarpIcon {
                    anchors.centerIn: parent
                    iconSize: 13
                    color: warpMod.warp && warpMod.warp.active ? wr.root.accent : (warpMod.warp && warpMod.warp.daemonDown ? wr.root.sumi : wr.text)
                    badgeColor: wr.root.warn
                    crossed: warpMod.warp && !warpMod.warp.active && !warpMod.warp.daemonDown
                    warning: warpMod.warp && (warpMod.warp.daemonDown || warpMod.warp.needsRegistration)
                }

                readonly property string tipText: {
                    var w = warpMod.warp;
                    if (!w || !w.probed) return "Cloudflare WARP";
                    if (w.daemonDown) return "Cloudflare WARP: Daemon inactive\nClick to start";
                    if (!w.registered) return "Cloudflare WARP: Needs registration";
                    var lines = ["Cloudflare WARP: " + w.statusText];
                    if (w.mode) lines.push("Mode: " + w.modeLabel(w.mode));
                    if (w.active && w.tunnelStats) {
                        if (w.tunnelStats.endpoint) lines.push("Colo: " + w.tunnelStats.endpoint);
                        if (w.tunnelStats.latency) lines.push("Latency: " + w.tunnelStats.latency);
                        if (w.tunnelStats.sent || w.tunnelStats.received)
                            lines.push("↑ " + (w.tunnelStats.sent || "0 B") + "   ↓ " + (w.tunnelStats.received || "0 B"));
                    }
                    return lines.join("\n");
                }

                Timer {
                    id: warpTipDelay
                    interval: 180
                    onTriggered: {
                        const p = warpMod.mapToItem(null, warpMod.width / 2, warpMod.height / 2);
                        wr.root.showTooltip(warpMod.tipText, p.x, p.y);
                    }
                }

                MouseArea {
                    id: warpMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onEntered: warpTipDelay.restart()
                    onExited: { warpTipDelay.stop(); wr.root.hideTooltip(warpMod.tipText); }
                    onClicked: (e) => {
                        warpTipDelay.stop();
                        wr.root.hideTooltip(warpMod.tipText);
                        if (e.button === Qt.RightButton) {
                            if (warpMod.warp) {
                                if (warpMod.warp.daemonDown) warpMod.warp.startDaemon();
                                else warpMod.warp.toggleConnection();
                            }
                        } else if (e.button === Qt.MiddleButton) {
                            if (warpMod.warp) warpMod.warp.refresh();
                        } else {
                            if (wr.root.warpVisible) wr.root.warpVisible = false;
                            else wr.root.openWarp();
                        }
                    }
                }
            }

            WhiteRoseCell {
                id: audioMod
                root: wr.root
                glyph: wr.root.audioIcon
                tooltip: (wr.root.audioSinkDesc ? wr.root.audioSinkDesc + " " : "") + (wr.root.audioDevType !== "bt" && wr.root.audioPort ? "(" + wr.root.audioPort + ") " : "") + wr.root.audioVol + "%" + (wr.root.audioMuted ? " (muted)" : "")
                strong: wr.root.audioMuted
                borderless: true
                minWidth: 28
                maxWidth: 28
                onActivated: {
                    if (wr.root.audioVisible) wr.root.audioVisible = false;
                    else wr.root.openAudio();
                }
                onMiddleActivated: wr.root.run("pamixer -t && qs -c desktop ipc call audio refresh")
                onRightActivated: wr.root.run("~/.config/waybar/scripts/pulse_switch.sh")
                onWheelActivated: (delta) => wr.root.nudgeVolume(delta)
            }

            WhiteRoseCell {
                root: wr.root
                visible: wr.root.batPresent
                glyph: wr.root.batteryIcon()
                tooltip: wr.batteryTip()
                strong: wr.root.batVal <= 10
                borderless: true
                minWidth: 28
                maxWidth: 28
                onActivated: wr.root.run("omarchy-menu power")
            }

            WhiteRoseCell {
                root: wr.root
                glyph: "󰻂"
                visible: wr.root.recordingActive
                tooltip: "RECORDING"
                strong: true
                accentColor: wr.root.seal
                borderless: true
                minWidth: 28
                maxWidth: 28
                fontSize: 11
                onActivated: wr.root.run("qs -c desktop ipc call screenrecord toggle")
            }
        }
    }

    ColumnLayout {
        visible: !wr.root.isHorizontal
        anchors.fill: parent
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 3

        WhiteRoseCell {
            root: wr.root
            imageSource: wr.logoSource
            tooltip: "Menu"
            borderless: true
            minWidth: 20
            maxWidth: 20
            iconSize: 13
            onActivated: wr.root.paletteToggleRequested()
            onRightActivated: wr.root.run("xdg-terminal-exec")
        }

        Rectangle { Layout.preferredWidth: 14; Layout.preferredHeight: 1; Layout.alignment: Qt.AlignHCenter; color: wr.line }

        Repeater {
            model: 10
            delegate: Workspace {
                required property int index
                root: wr.root
                wsId: index + 1
                label: wr.root.indexKanji(index + 1)
                active: wr.root.activeWs === (index + 1)
                present: wr.root.existingWs.indexOf(index + 1) !== -1
                onActivated: wr.root.focusWorkspace(index + 1)
            }
        }

        Item { Layout.fillHeight: true }

        Item {
            id: clockItemV
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: wr.root.barHeight
            Layout.preferredHeight: 30

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                color: "transparent"
                border.width: 0
                border.color: wr.lineStrong
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.verticalCenter
                anchors.bottomMargin: 1
                text: wr.root.dow + " " + wr.root.dd
                color: wr.text
                font.family: wr.root.mono
                font.pixelSize: 8
                font.weight: Font.Medium
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                anchors.topMargin: 1
                text: wr.root.hh + ":" + wr.root.mm
                color: wr.text
                font.family: wr.root.mono
                font.pixelSize: 9
                font.weight: Font.Medium
            }
            MouseArea {
                id: clockMouseV
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                        wr.root.paletteToggleRequested();
                    } else {
                        if (wr.root.calendarVisible) wr.root.calendarVisible = false;
                        else wr.root.openCalendar();
                    }
                }
            }
        }

        Separator { root: wr.root }

        Tray { root: wr.root }

        WhiteRoseCell {
            id: systemModV
            root: wr.root
            glyph: "󰍛"
            tooltip: "CPU " + Math.round(wr.root.cpuVal) + "% · MEM " + Math.round(wr.root.memVal) + "%"
            strong: wr.root.cpuVal > 80
            borderless: true
            minWidth: 20
            fontSize: 11
            onActivated: {
                if (wr.root.systemVisible) wr.root.systemVisible = false;
                else wr.root.openSystem();
            }
            onRightActivated: wr.root.openDisplay()
        }
        Item {
            id: aiModV
            readonly property var ai: wr.root.aiService
            visible: wr.root.aiVisible || (aiModV.ai && aiModV.ai.agentRunning)
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: wr.root.barHeight
            Layout.preferredHeight: visible ? 24 : 0

            AiIcon {
                anchors.centerIn: parent
                iconSize: 13
                fontFamily: wr.root.mono
                glyphYOffset: -1
                color: aiModV.ai && aiModV.ai.agentState === "working" ? wr.root.accent : wr.text
                badgeColor: aiModV.ai && aiModV.ai.agentState === "action_needed" ? wr.root.warn : wr.root.seal
                successColor: wr.root.accent
                state: aiModV.ai ? aiModV.ai.agentState : "idle"
            }

            readonly property string tipText: aiModV.ai ? aiModV.ai.tipText : "Antigravity"

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (e) => {
                    if (e.button === Qt.MiddleButton) {
                        if (aiModV.ai) aiModV.ai.refresh(true);
                    } else {
                        if (wr.root.aiVisible) wr.root.aiVisible = false;
                        else wr.root.openAi();
                    }
                }
            }
        }
        WhiteRoseCell {
            id: notifModV
            root: wr.root
            glyph: wr.root.doNotDisturb ? "󰂛" : "󰂚"
            tooltip: {
                const s = wr.root.notificationCenterService;
                const count = s ? s.unread : 0;
                if (wr.root.doNotDisturb) return count > 0 ? "Notifications silenced · " + count + " unread" : "Notifications silenced";
                return count > 0 ? count + " new notifications" : "Notifications";
            }
            strong: wr.root.doNotDisturb
            borderless: true
            minWidth: 20
            fontSize: 11
            onActivated: {
                if (wr.root.notificationCenterVisible) wr.root.notificationCenterVisible = false;
                else wr.root.openNotificationCenter();
            }
            onRightActivated: wr.root.toggleDnd()

            Rectangle {
                visible: {
                    const s = wr.root.notificationCenterService;
                    return s ? (s.unread > 0) : false;
                }
                anchors.right: parent.right
                anchors.rightMargin: 5
                anchors.top: parent.top
                anchors.topMargin: 3
                width: 5
                height: 5
                radius: 2.5
                color: wr.root.accent
            }
        }
        WhiteRoseCell {
            id: btModV
            root: wr.root
            glyph: wr.root.btIcon
            tooltip: {
                if (!wr.root.btPowered) return "Bluetooth off";
                const conn = wr.root.btDevices.filter(d => d.connected);
                if (conn.length === 0) return "Bluetooth on";
                return conn.map(d => d.name + (d.battery > 0 ? " " + d.battery + "%" : "")).join("\n");
            }
            ink: wr.root.btPowered ? wr.text : wr.muted
            borderless: true
            minWidth: 20
            fontSize: 11
            onActivated: {
                if (wr.root.btVisible) wr.root.btVisible = false;
                else wr.root.openBluetooth();
            }
        }
        WhiteRoseCell {
            id: netModV
            root: wr.root
            glyph: wr.root.netIcon
            tooltip: {
                if (wr.root.netKind === "eth") return "Ethernet";
                if (wr.root.netKind === "wifi") return "Wi-Fi - " + (wr.root.wifiSsid || "(hidden)") + " - " + wr.root.wifiSignal + "%";
                return "Offline";
            }
            ink: wr.root.wireprotonActiveIface.length > 0 ? wr.root.accent : (wr.root.netKind === "none" ? wr.muted : wr.text)
            borderless: true
            minWidth: 20
            fontSize: 11
            onActivated: {
                if (wr.root.networkVisible) wr.root.networkVisible = false;
                else wr.root.openNetwork();
            }
        }
        Item {
            id: warpModV
            readonly property var warp: wr.root.warpService
            visible: wr.root.warpVisible || (warpModV.warp && (warpModV.warp.active || warpModV.warp.connecting))
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: wr.root.barHeight
            Layout.preferredHeight: visible ? 24 : 0

            WarpIcon {
                anchors.centerIn: parent
                iconSize: 13
                color: warpModV.warp && warpModV.warp.active ? wr.root.accent : (warpModV.warp && warpModV.warp.daemonDown ? wr.root.sumi : wr.text)
                badgeColor: wr.root.warn
                crossed: warpModV.warp && !warpModV.warp.active && !warpModV.warp.daemonDown
                warning: warpModV.warp && (warpModV.warp.daemonDown || warpModV.warp.needsRegistration)
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (e) => {
                    if (e.button === Qt.RightButton) {
                        if (warpModV.warp) {
                            if (warpModV.warp.daemonDown) warpModV.warp.startDaemon();
                            else warpModV.warp.toggleConnection();
                        }
                    } else if (e.button === Qt.MiddleButton) {
                        if (warpModV.warp) warpModV.warp.refresh();
                    } else {
                        if (wr.root.warpVisible) wr.root.warpVisible = false;
                        else wr.root.openWarp();
                    }
                }
            }
        }
        WhiteRoseCell {
            id: audioModV
            root: wr.root
            glyph: wr.root.audioIcon
            tooltip: wr.root.audioMuted
                     ? "Audio muted - " + wr.root.audioVol + "%"
                     : "Audio " + wr.root.audioVol + "%"
            strong: wr.root.audioMuted
            borderless: true
            minWidth: 20
            fontSize: 11
            onActivated: {
                if (wr.root.audioVisible) wr.root.audioVisible = false;
                else wr.root.openAudio();
            }
            onMiddleActivated: wr.root.run("pamixer -t && qs -c desktop ipc call audio refresh")
            onRightActivated: wr.root.run("~/.config/waybar/scripts/pulse_switch.sh")
            onWheelActivated: (delta) => wr.root.nudgeVolume(delta)
        }
        WhiteRoseCell {
            root: wr.root
            visible: wr.root.batPresent
            glyph: wr.root.batteryIcon()
            tooltip: wr.batteryTip()
            strong: wr.root.batVal <= 10
            borderless: true
            minWidth: 20
            fontSize: 9
            onActivated: wr.root.run("omarchy-menu power")
        }
        WhiteRoseCell {
            root: wr.root
            visible: wr.root.recordingActive
            glyph: "󰻂"
            tooltip: "RECORDING"
            strong: true
            accentColor: wr.root.seal
            borderless: true
            minWidth: 20
            fontSize: 11
            onActivated: wr.root.run("qs -c desktop ipc call screenrecord toggle")
        }
    }
}
