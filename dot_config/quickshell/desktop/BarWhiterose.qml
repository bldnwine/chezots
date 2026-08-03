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
    readonly property color musicAccent: root.green

    readonly property string logoSource:
        "file://" + Quickshell.env("HOME") + "/Code/whiterose/site/assets/logo.svg"
    readonly property string icoCpu: String.fromCodePoint(0xf035b)

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
        wr.root.calendarAnchorItem = wr.root.isHorizontal ? clockItem : clockItemV;
        wr.root.weatherAnchorItem  = wr.root.isHorizontal ? weatherMod : weatherModV;
        wr.root.systemAnchorItem   = wr.root.isHorizontal ? systemMod : systemModV;
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
        color: wr.bg

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
                interval: 320
                onTriggered: {
                    const p = clockItem.mapToItem(null, clockItem.width / 2, clockItem.height / 2);
                    wr.root.showTooltip("Calendar", p.x, p.y);
                }
            }
            MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: clockTipDelay.restart()
                onExited: { clockTipDelay.stop(); wr.root.hideTooltip("Calendar"); }
                onClicked: {
                    clockTipDelay.stop();
                    wr.root.hideTooltip("Calendar");
                    if (wr.root.calendarVisible) wr.root.calendarVisible = false;
                    else wr.root.openCalendar();
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
                delegate: Item {
                    id: wsDot
                    required property int index
                    readonly property int wsId: index + 1
                    readonly property bool active: wr.root.activeWs === wsId
                    readonly property bool present: wr.root.existingWs.indexOf(wsId) !== -1

                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: wr.root.barHeight
                    opacity: wsMouse.containsMouse || present ? 1.0 : 0.34

                    Rectangle {
                        anchors.centerIn: parent
                        width: wsDot.active ? 7 : 4
                        height: width
                        radius: width / 2
                        color: wsDot.active ? wr.text : wr.faint
                        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        id: wsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: wr.root.focusWorkspace(wsDot.wsId)
                    }
                }
            }

            Item { Layout.fillWidth: true }

            WhiteRoseCell {
                root: wr.root
                visible: wr.root.musicTitle.length > 0
                glyph: wr.root.musicPlaying ? wr.root.icoMusic : wr.root.icoPause
                tooltip: wr.root.musicArtist.length > 0
                         ? wr.root.musicTitle + " - " + wr.root.musicArtist
                         : wr.root.musicTitle
                strong: true
                borderless: true
                accentColor: wr.musicAccent
                iconSize: 10
                iconYOffset: 0
                minWidth: 28
                maxWidth: 28
                onActivated: wr.root.musicToggle()
                onRightActivated: wr.root.musicNext()
            }

            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 14; Layout.alignment: Qt.AlignVCenter; color: wr.line }

            WhiteRoseCell {
                id: weatherMod
                root: wr.root
                glyph: wr.root.weatherUnavailable ? "?"
                       : (wr.root.weatherLoaded ? wr.root.weatherIcon : ".")
                tooltip: wr.root.weatherUnavailable
                         ? "Weather offline"
                         : (wr.root.weatherLoaded
                            ? wr.root.weatherDesc + " - " + Math.round(wr.root.weatherTempC) + "C"
                            : "Weather...")
                borderless: true
                minWidth: 28
                maxWidth: 28
                ink: wr.root.weatherUnavailable ? wr.muted : wr.text
                onActivated: {
                    if (wr.root.weatherVisible) wr.root.weatherVisible = false;
                    else wr.root.openWeather();
                }
                onRightActivated: wr.root.refreshWeather()
            }

            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 14; Layout.alignment: Qt.AlignVCenter; color: wr.line }

            WhiteRoseCell {
                id: systemMod
                root: wr.root
                glyph: wr.icoCpu
                tooltip: "System - CPU " + Math.round(wr.root.cpuVal) + "% / MEM " + Math.round(wr.root.memVal) + "%"
                strong: wr.root.cpuVal > 80 || wr.root.memVal > 85
                borderless: true
                minWidth: 28
                maxWidth: 28
                onActivated: {
                    if (wr.root.systemVisible) wr.root.systemVisible = false;
                    else wr.root.openSystem();
                }
                onRightActivated: wr.root.run("omarchy-launch-or-focus-tui btop")
            }
            WhiteRoseCell {
                root: wr.root
                glyph: wr.root.btIcon
                tooltip: {
                    if (!wr.root.btPowered) return "Bluetooth off";
                    return wr.root.btCount > 0
                        ? "Bluetooth - " + wr.root.btCount + " connected"
                        : "Bluetooth on";
                }
                ink: wr.root.btPowered ? wr.text : wr.muted
                borderless: true
                minWidth: 28
                maxWidth: 28
                onActivated: wr.root.run("ghostty --title='Bluetooth Manager' -e bluetui")
            }
            WhiteRoseCell {
                root: wr.root
                glyph: wr.root.netIcon
                tooltip: {
                    if (wr.root.netKind === "eth") return "Ethernet";
                    if (wr.root.netKind === "wifi") {
                        const name = wr.root.wifiSsid || "(hidden)";
                        return "Wi-Fi - " + name + " - " + wr.root.wifiSignal + "%";
                    }
                    return "Offline";
                }
                ink: wr.root.netKind === "none" ? wr.muted : wr.text
                borderless: true
                minWidth: 28
                maxWidth: 28
                onActivated: wr.root.run("ghostty --title=impala -e impala")
            }
            WhiteRoseCell {
                root: wr.root
                glyph: wr.root.audioIcon
                tooltip: wr.root.audioMuted
                         ? "Audio muted - " + wr.root.audioVol + "%"
                         : "Audio " + wr.root.audioVol + "%"
                strong: wr.root.audioMuted
                borderless: true
                minWidth: 28
                maxWidth: 28
                onActivated: wr.root.run("pavucontrol")
                onMiddleActivated: wr.root.run("pamixer -t && qs -c desktop ipc call audio refresh")
                onRightActivated: wr.root.run("~/.config/waybar/scripts/pulse_switch.sh")
            }
            WhiteRoseCell {
                root: wr.root
                visible: wr.root.omarchyUpdateAvailable
                glyph: wr.root.icoUpdate
                tooltip: wr.root.omarchyLatestTag
                         ? "Omarchy update available - " + wr.root.omarchyLatestTag
                         : "Omarchy update available"
                strong: true
                borderless: true
                minWidth: 28
                maxWidth: 28
                onActivated: wr.root.openOmarchyUpdate()
            }
            WhiteRoseCell {
                root: wr.root
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
                text: wr.root.edgeArrow()
                tooltip: "Move bar"
                borderless: true
                minWidth: 28
                onActivated: wr.root.cycleBarEdge()
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
            delegate: Item {
                id: wsDotV
                required property int index
                readonly property int wsId: index + 1
                readonly property bool active: wr.root.activeWs === wsId
                readonly property bool present: wr.root.existingWs.indexOf(wsId) !== -1

                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: wr.root.barHeight
                Layout.preferredHeight: 14
                opacity: wsMouseV.containsMouse || present ? 1.0 : 0.34

                Rectangle {
                    anchors.centerIn: parent
                    width: wsDotV.active ? 7 : 4
                    height: width
                    radius: width / 2
                    color: wsDotV.active ? wr.text : wr.faint
                    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    id: wsMouseV
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: wr.root.focusWorkspace(wsDotV.wsId)
                }
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
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (wr.root.calendarVisible) wr.root.calendarVisible = false;
                    else wr.root.openCalendar();
                }
            }
        }

        Rectangle { Layout.preferredWidth: 14; Layout.preferredHeight: 1; Layout.alignment: Qt.AlignHCenter; color: wr.line }

        WhiteRoseCell {
            id: systemModV
            root: wr.root
            glyph: wr.icoCpu
            tooltip: "System - CPU " + Math.round(wr.root.cpuVal) + "% / MEM " + Math.round(wr.root.memVal) + "%"
            strong: wr.root.cpuVal > 80 || wr.root.memVal > 85
            borderless: true
            minWidth: 20
            fontSize: 9
            onActivated: {
                if (wr.root.systemVisible) wr.root.systemVisible = false;
                else wr.root.openSystem();
            }
            onRightActivated: wr.root.run("omarchy-launch-or-focus-tui btop")
        }
        WhiteRoseCell {
            root: wr.root
            glyph: wr.root.netIcon
            tooltip: {
                if (wr.root.netKind === "eth") return "Ethernet";
                if (wr.root.netKind === "wifi") return "Wi-Fi - " + (wr.root.wifiSsid || "(hidden)") + " - " + wr.root.wifiSignal + "%";
                return "Offline";
            }
            ink: wr.root.netKind === "none" ? wr.muted : wr.text
            borderless: true
            minWidth: 20
            fontSize: 9
            onActivated: wr.root.run("ghostty --title=impala -e impala")
        }
        WhiteRoseCell {
            root: wr.root
            glyph: wr.root.audioIcon
            tooltip: wr.root.audioMuted
                     ? "Audio muted - " + wr.root.audioVol + "%"
                     : "Audio " + wr.root.audioVol + "%"
            strong: wr.root.audioMuted
            borderless: true
            minWidth: 20
            fontSize: 9
            onActivated: wr.root.run("pavucontrol")
            onMiddleActivated: wr.root.run("pamixer -t && qs -c desktop ipc call audio refresh")
            onRightActivated: wr.root.run("~/.config/waybar/scripts/pulse_switch.sh")
        }
        WhiteRoseCell {
            id: weatherModV
            root: wr.root
            glyph: wr.root.weatherUnavailable ? "?"
                   : (wr.root.weatherLoaded ? wr.root.weatherIcon : ".")
            tooltip: wr.root.weatherUnavailable
                     ? "Weather offline"
                     : (wr.root.weatherLoaded
                        ? wr.root.weatherDesc + " - " + Math.round(wr.root.weatherTempC) + "C"
                        : "Weather...")
            ink: wr.root.weatherUnavailable ? wr.muted : wr.text
            borderless: true
            minWidth: 20
            fontSize: 9
            onActivated: {
                if (wr.root.weatherVisible) wr.root.weatherVisible = false;
                else wr.root.openWeather();
            }
            onRightActivated: wr.root.refreshWeather()
        }
        WhiteRoseCell {
            root: wr.root
            glyph: wr.root.batteryIcon()
            tooltip: wr.batteryTip()
            strong: wr.root.batVal <= 10
            borderless: true
            minWidth: 20
            fontSize: 9
            onActivated: wr.root.run("omarchy-menu power")
        }

        Rectangle { Layout.preferredWidth: 14; Layout.preferredHeight: 1; Layout.alignment: Qt.AlignHCenter; color: wr.line }

        WhiteRoseCell {
            root: wr.root
            text: wr.root.edgeArrow()
            tooltip: "Move bar"
            borderless: true
            minWidth: 20
            fontSize: 11
            onActivated: wr.root.cycleBarEdge()
        }
    }
}
