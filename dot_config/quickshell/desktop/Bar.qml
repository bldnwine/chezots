import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: bar
    required property var root

    color: "transparent"
    // Anchors track barEdge — three sides anchored, the side opposite
    // the bar's edge is left free for the bar's thickness to extend.
    anchors {
        top:    bar.root.barEdge !== "bottom"
        bottom: bar.root.barEdge !== "top"
        left:   bar.root.barEdge !== "right"
        right:  bar.root.barEdge !== "left"
    }
    // Cloud mode: horizontal+round only. Vertical bars keep the original
    // slab geometry to avoid breaking the proven layout.
    readonly property int cloudPad: 2
    readonly property int cloudAir: 5
    readonly property int cloudInnerAir: 2
    readonly property bool cloudMode: bar.root.round && bar.root.isHorizontal
    readonly property int extraThickness: cloudMode ? 2 * cloudPad + cloudAir + cloudInnerAir : 0
    // innerSign tells which side gets the extra outer air (away from screen).
    readonly property int innerSign: bar.root.barEdge === "top" ? 1 : (bar.root.barEdge === "bottom" ? -1 : 0)

    implicitHeight: bar.root.isHorizontal ? bar.root.barHeight + extraThickness : 0
    implicitWidth:  bar.root.isHorizontal ? 0 : bar.root.barHeight
    exclusiveZone:  bar.root.isHorizontal ? bar.root.barHeight + extraThickness : bar.root.barHeight

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "omarchy-menu"

    // Re-claim the popup anchors when this face becomes the visible one.
    // Popups read these at open time, so whoever is mapped must own them.
    onVisibleChanged: if (visible) {
        bar.root.calendarAnchorItem = clockItem;
        bar.root.displayAnchorItem = clockItem;
    }

    // In cloud mode the slab bg is replaced by a single rounded backdrop
    // sized to match the inner bar (barHeight tall, with cloudAir margins
    // on each side along the bar axis, sliding toward the inner edge so
    // outer-side air sits between cloud and screen edge).
    Rectangle {
        id: cloudBg
        visible: bar.cloudMode
        x: bar.cloudAir
        y: bar.innerSign === 1 ? bar.cloudAir : bar.cloudInnerAir
        width: parent.width - 2 * bar.cloudAir
        height: bar.root.barHeight + 2 * bar.cloudPad
        radius: bar.root.cornerRadius
        color: bar.root.barTransparent ? "transparent" : bar.root.bg
        z: 0
    }

    // Container for clock + modules + hairlines. In cloud mode the bg
    // becomes transparent so the cloud rectangle above shows through;
    // in slab mode this acts as the bar background.
    Rectangle {
        id: slabBg
        anchors.fill: parent
        color: bar.cloudMode ? "transparent" : (bar.root.barTransparent ? "transparent" : bar.root.bg)


        // Inner-edge hairline (facing the rest of the screen). Hidden in
        // cloud mode — the rounded backdrop replaces it visually.
        Rectangle {
            visible: !bar.cloudMode && bar.root.isHorizontal
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    bar.root.barEdge === "bottom" ? parent.top    : undefined
            anchors.bottom: bar.root.barEdge === "top"    ? parent.bottom : undefined
            height: 1
            color: bar.root.barTransparent ? "transparent" : bar.root.sep
        }
        Rectangle {
            visible: !bar.cloudMode && !bar.root.isHorizontal
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            anchors.right:  bar.root.barEdge === "left"  ? parent.right : undefined
            anchors.left:   bar.root.barEdge === "right" ? parent.left  : undefined
            width: 1
            color: bar.root.barTransparent ? "transparent" : bar.root.sep
        }

        // Centre cluster: clock only, clickable. Horizontal bars show
        // "HH:MM" on one line; vertical bars stack HH and MM.
        Item {
            id: clockItem
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter:   parent.verticalCenter
            anchors.verticalCenterOffset: bar.cloudMode ? (bar.innerSign === 1 ? 2 : -2) : 0
            z: 10
            Component.onCompleted: bar.root.calendarAnchorItem = clockItem

            implicitWidth:  bar.root.isHorizontal
                            ? clockOneLine.implicitWidth + 14
                            : Math.max(clockHH.implicitWidth, clockMM.implicitWidth) + 8
            implicitHeight: bar.root.isHorizontal
                            ? clockOneLine.implicitHeight + 8
                            : (clockHH.implicitHeight + clockMM.implicitHeight + 6)

            Bloom { id: clockBloom; root: bar.root }

            Text {
                id: clockOneLine
                visible: bar.root.isHorizontal
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                text: bar.root.dow + " " + bar.root.dd + " - " + bar.root.hh + ":" + bar.root.mm
                color: clockMouse.containsMouse ? bar.root.seal : bar.root.ink
                font.family: bar.root.mono
                font.pixelSize: 11
                font.letterSpacing: 2
                font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: 180 } }
            }
            Text {
                id: clockHH
                visible: !bar.root.isHorizontal
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.verticalCenter
                anchors.bottomMargin: 1
                text: bar.root.dow + " " + bar.root.dd
                color: clockMouse.containsMouse ? bar.root.seal : bar.root.ink
                font.family: bar.root.mono
                font.pixelSize: 9
                font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: 180 } }
            }
            Text {
                id: clockMM
                visible: !bar.root.isHorizontal
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.verticalCenter
                anchors.topMargin: 1
                text: bar.root.hh + ":" + bar.root.mm
                color: clockMouse.containsMouse ? bar.root.seal : bar.root.ink
                font.family: bar.root.mono
                font.pixelSize: 11
                font.weight: Font.Light
                Behavior on color { ColorAnimation { duration: 180 } }
            }

            Timer {
                id: clockTipDelay
                interval: 320
                onTriggered: {
                    const p = clockItem.mapToItem(null, clockItem.width / 2, clockItem.height / 2);
                    bar.root.showTooltip("Calendar", p.x, p.y);
                }
            }

            MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onEntered: { clockBloom.fire(mouseX, mouseY); clockTipDelay.restart(); }
                onExited:  { clockTipDelay.stop(); bar.root.hideTooltip("Calendar"); }
                onClicked: function(mouse) {
                    clockTipDelay.stop();
                    bar.root.hideTooltip("Calendar");
                    if (mouse.button === Qt.RightButton) {
                        bar.root.paletteToggleRequested();
                    } else {
                        if (bar.root.calendarVisible) bar.root.calendarVisible = false;
                        else bar.root.openCalendar();
                    }
                }
            }
        }

        GridLayout {
            anchors.fill: parent
            anchors.leftMargin:   bar.root.isHorizontal ? (bar.cloudMode ? bar.cloudAir + bar.cloudPad : 10) : 0
            anchors.rightMargin:  bar.root.isHorizontal
                                  ? (bar.cloudMode ? bar.cloudAir + bar.cloudPad : 10)
                                  : 0
            anchors.topMargin:    bar.root.isHorizontal
                                  ? (bar.cloudMode
                                     ? (bar.root.barEdge === "top" ? bar.cloudAir + bar.cloudPad : bar.cloudInnerAir + bar.cloudPad)
                                     : 0)
                                  : 10
            anchors.bottomMargin: bar.root.isHorizontal
                                  ? (bar.cloudMode
                                     ? (bar.root.barEdge === "top" ? bar.cloudInnerAir + bar.cloudPad : bar.cloudAir + bar.cloudPad)
                                     : 0)
                                  : 10
            flow: bar.root.isHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
            rowSpacing: 4
            columnSpacing: 4
            columns: bar.root.isHorizontal ? -1 : 1
            rows:    bar.root.isHorizontal ? 1  : -1

            Repeater {
                model: 10
                delegate: Workspace {
                    required property int index
                    root: bar.root
                    wsId: index + 1
                    label: bar.root.indexKanji(index + 1)
                    active: bar.root.activeWs === (index + 1)
                    present: bar.root.existingWs.indexOf(index + 1) !== -1
                    onActivated: { console.log("[WS-ACT fired] ws=" + (index + 1) + " runType=" + (typeof (bar.root && bar.root.run))); bar.root.focusWorkspace(index + 1); }
                }
            }

            Item {
                Layout.fillWidth:  bar.root.isHorizontal
                Layout.fillHeight: !bar.root.isHorizontal
            }

            Item {
                id: musicItem
                readonly property bool present: bar.root.isHorizontal && bar.root.musicTitle.length > 0
                readonly property real contentW: musicRow.width + 12
                property real openW: present ? contentW + 8 : 0
                Behavior on openW { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                visible: present || openW > 0.5
                Layout.preferredWidth: openW
                Layout.preferredHeight: 16
                Layout.alignment: Qt.AlignVCenter

                readonly property string tipText: bar.root.musicArtist.length > 0
                                                  ? bar.root.musicTitle + " - " + bar.root.musicArtist
                                                  : bar.root.musicTitle

                Rectangle {
                    id: musicPill
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - 8)
                    height: parent.height
                    radius: height / 2
                    color: bar.root.accent
                    clip: true
                    opacity: musicMouse.containsMouse ? 1.0 : 0.9
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    Row {
                        id: musicRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            id: musicIcon
                            anchors.verticalCenter: parent.verticalCenter
                            text: bar.root.icoMusic
                            color: bar.root.paper
                            font.family: bar.root.mono
                            font.pixelSize: 9
                        }

                        Text {
                            id: musicLabel
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property int maxChars:
                                Math.max(2, Math.floor(140 / chMetric.advanceWidth))
                            readonly property bool truncated:
                                bar.root.musicTitle.length > maxChars
                            text: truncated
                                  ? bar.root.musicTitle.slice(0, maxChars - 2) + ".."
                                  : bar.root.musicTitle
                            color: bar.root.paper
                            font.family: bar.root.mono
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
                            GradientStop { position: 0.0; color: Qt.rgba(bar.root.accent.r, bar.root.accent.g, bar.root.accent.b, 0) }
                            GradientStop { position: 0.6; color: bar.root.accent }
                            GradientStop { position: 1.0; color: bar.root.accent }
                        }
                    }
                }

                Timer {
                    id: musicTipDelay
                    interval: 320
                    onTriggered: {
                        const p = musicItem.mapToItem(null, musicItem.width / 2, musicItem.height / 2);
                        bar.root.showTooltip(musicItem.tipText, p.x, p.y);
                    }
                }

                MouseArea {
                    id: musicMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton | Qt.XButton1 | Qt.XButton2
                    cursorShape: Qt.PointingHandCursor
                    onEntered: musicTipDelay.restart()
                    onExited:  { musicTipDelay.stop(); bar.root.hideTooltip(musicItem.tipText); }
                    onClicked: (e) => {
                        musicTipDelay.stop();
                        bar.root.hideTooltip(musicItem.tipText);
                        if (e.button === Qt.RightButton)       bar.root.musicNext();
                        else if (e.button === Qt.MiddleButton) bar.root.musicPrev();
                        else if (e.button === Qt.XButton1)     bar.root.musicPrev();
                        else if (e.button === Qt.XButton2)     bar.root.musicNext();
                        else                                    bar.root.musicToggle();
                    }
                    onWheel: (wheel) => {
                        if (wheel.angleDelta.y > 0) bar.root.musicNextSource();
                        else if (wheel.angleDelta.y < 0) bar.root.musicPrevSource();
                    }
                }
            }

            // Aether / Display / Screenshots / Videos moved into the
            // OmniMenu Quick panel (Alt+Space). The bar keeps only the
            // always-glanced status indicators on the right.

            Separator { root: bar.root }

            // System indicators read right-to-left as
            //   battery · sound · wifi · bluetooth · cpu · [edge]
            // so the most-glanced item (battery) sits adjacent to the
            // bar-position chevron.
            Module {
                root: bar.root
                glyph: "󰍛"
                fontSize: 14
                tooltip: "CPU " + Math.round(bar.root.cpuVal) + "% · MEM " + Math.round(bar.root.memVal) + "%"
                color: bar.root.cpuVal > 80 ? bar.root.seal : bar.root.ink
                Component.onCompleted: bar.root.systemAnchorItem = this
                onActivated: {
                    if (bar.root.systemVisible) bar.root.systemVisible = false;
                    else bar.root.openSystem();
                }
            }

            Module {
                root: bar.root
                glyph: bar.root.btIcon
                fontSize: 13
                tooltip: {
                    if (!bar.root.btPowered) return "Bluetooth off";
                    const conn = bar.root.btDevices.filter(d => d.connected);
                    if (conn.length === 0) return "Bluetooth on";
                    return conn.map(d => d.name + (d.battery > 0 ? " " + d.battery + "%" : "")).join("\n");
                }
                Component.onCompleted: bar.root.btAnchorItem = this
                onActivated: {
                    if (bar.root.btVisible) bar.root.btVisible = false;
                    else bar.root.openBluetooth();
                }
            }

            Module {
                id: netMod
                root: bar.root
                glyph: bar.root.netIcon
                fontSize: 12
                color: bar.root.wireprotonActiveIface.length > 0 ? bar.root.accent : bar.root.ink
                tooltip: {
                    if (bar.root.netKind === "eth") return "Ethernet";
                    if (bar.root.netKind === "wifi") {
                        const name = bar.root.wifiSsid || "(hidden)";
                        return name + " · " + bar.root.wifiSignal + "%";
                    }
                    return "Offline";
                }
                Component.onCompleted: bar.root.networkAnchorItem = this
                onActivated: {
                    if (bar.root.networkVisible) bar.root.networkVisible = false;
                    else bar.root.openNetwork();
                }

                // Network-burst dot: traverses the wifi glyph's outermost
                // arc once when a heavy rx+tx burst is detected.
                // Geometry is eyeballed for the Nerd Font wifi icon
                // rendered at fontSize 12 inside the 24x26 Module slot.
                Item {
                    id: arc
                    anchors.fill: parent
                    property real t: 0
                    property real op: 0
                    readonly property real cx: width / 2
                    readonly property real cy: 17
                    readonly property real r:  6

                    Rectangle {
                        width: 3
                        height: 3
                        radius: 1.5
                        color: Qt.lighter(bar.root.seal, 1.7)
                        antialiasing: true
                        opacity: arc.op
                        x: arc.cx - arc.r * Math.cos(Math.PI * arc.t) - width / 2
                        y: arc.cy - arc.r * Math.sin(Math.PI * arc.t) - height / 2
                    }

                    ParallelAnimation {
                        id: arcAnim
                        NumberAnimation {
                            target: arc; property: "t"
                            from: 0; to: 1
                            duration: 700
                            easing.type: Easing.InOutQuad
                        }
                        SequentialAnimation {
                            NumberAnimation { target: arc; property: "op"; from: 0; to: 1; duration: 120; easing.type: Easing.OutQuad }
                            PauseAnimation { duration: 380 }
                            NumberAnimation { target: arc; property: "op"; to: 0; duration: 200; easing.type: Easing.InCubic }
                        }
                    }

                    Connections {
                        target: bar.root
                        function onNetBurst() { arc.t = 0; arcAnim.restart(); }
                    }
                }
            }

            Module {
                root: bar.root
                glyph: bar.root.audioIcon
                tooltip: (bar.root.audioSinkDesc ? bar.root.audioSinkDesc + " " : "") + (bar.root.audioDevType !== "bt" && bar.root.audioPort ? "(" + bar.root.audioPort + ") " : "") + bar.root.audioVol + "%" + (bar.root.audioMuted ? " (muted)" : "")
                Component.onCompleted: bar.root.audioAnchorItem = this
                onActivated: {
                    if (bar.root.audioVisible) bar.root.audioVisible = false;
                    else bar.root.openAudio();
                }
                onMiddleActivated: bar.root.run("pamixer -t && qs -c desktop ipc call audio refresh")
                onRightActivated: bar.root.run("~/.config/waybar/scripts/pulse_switch.sh")
                onWheelActivated: (delta) => bar.root.run(delta > 0 ? "~/.config/quickshell/desktop/scripts/volume +5" : "~/.config/quickshell/desktop/scripts/volume -5")
            }

            Module {
                root: bar.root
                visible: bar.root.batPresent
                glyph: bar.root.batteryIcon()
                // Hide power below 0.05 W: idle Full / Not charging
                // states often report a sub-noise trickle that just
                // adds chatter to the tooltip.
                tooltip: {
                    let s = "Battery " + bar.root.batVal + "%";
                    if (bar.root.batPower >= 0.05) {
                        const sign = bar.root.batState === "Charging"    ? "+"
                                   : bar.root.batState === "Discharging" ? "-"
                                   : "";
                        s += "  " + sign + bar.root.batPower.toFixed(1) + " W";
                    }
                    return s;
                }
                color: bar.root.batVal <= 10 ? bar.root.seal : bar.root.batVal <= 20 ? bar.root.indigo : bar.root.ink
                onActivated: bar.root.run("omarchy-menu power")
            }

            Module {
                root: bar.root
                glyph: "󰻂"
                visible: bar.root.recordingActive
                color: bar.root.seal
                tooltip: "RECORDING"
                fontSize: 9
                onActivated: bar.root.run("qs -c desktop ipc call screenrecord toggle")
            }

        }
    }
}
