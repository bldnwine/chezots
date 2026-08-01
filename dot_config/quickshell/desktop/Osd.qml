import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "OsdModel.js" as OsdModel

Item {
    id: root
    required property var root

    property bool opened: false
    property string icon: ""
    property string message: ""
    property real value: 0
    property real maxValue: 1
    property bool hasProgress: false
    property int duration: 1200

    property real _opacity: 0
    Behavior on _opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
        var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration);
        root.maxValue = next.maxValue;
        root.hasProgress = next.hasProgress;
        root.value = next.value;
        root.message = next.message;
        root.icon = next.icon;
        root.duration = next.duration;
        root.opened = true;
        if (root.duration > 0) hideTimer.restart();
        else hideTimer.stop();
    }

    function open(payloadJson) {
        try {
            var p = JSON.parse(payloadJson || "{}");
            root.show(
                p.icon || "", p.message || "",
                p.value === undefined ? "" : String(p.value),
                p.max === undefined ? "100" : String(p.max),
                p.progressText || "",
                p.duration === undefined ? "1200" : String(p.duration));
        } catch (e) {}
    }

    function close() { root.opened = false; hideTimer.stop(); }

    Timer {
        id: hideTimer
        interval: root.duration
        onTriggered: root.opened = false
    }

    IpcHandler {
        target: "osd"
        function show(payloadJson: string): string { root.open(payloadJson); return "ok"; }
        function close(): string { root.close(); return "ok"; }
        function state(): string { return root.opened ? "open" : "closed"; }
        function ping(): string { return "ok"; }
    }

    onOpenedChanged: root._opacity = root.opened ? 1 : 0

    PanelWindow {
        id: panel
        visible: _opacity > 0.001
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omarchy-osd"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        Rectangle {
            id: card
            anchors.top: parent.top
            anchors.topMargin: root.root.barOffset + 7
            anchors.right: parent.right
            anchors.rightMargin: 8
            implicitWidth: row.implicitWidth + 120
            implicitHeight: row.implicitHeight + 60
            color: root.root.bg
            border.color: root.root.sep
            border.width: 1
            radius: root.root.theme.cornerRadius
            opacity: root._opacity

            Row {
                id: row
                x: 60
                y: 30
                spacing: 8
                height: 16

                Text {
                    id: iconText
                    width: 24
                    height: 16
                    y: (parent.height - height) / 2
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.icon
                    font.family: root.root.mono
                    font.pixelSize: 16
                    color: root.root.ink
                }

                Rectangle {
                    id: progressBar
                    visible: root.hasProgress
                    width: root.hasProgress ? 100 : 0
                    height: 3
                    y: (parent.height - height) / 2
                    radius: 1.5
                    color: root.root.rowHi
                    Rectangle {
                        height: parent.height
                        width: parent.width * Math.min(root.value / root.maxValue, 1)
                        radius: 1.5
                        color: root.root.seal
                    }
                }

                Text {
                    id: messageText
                    y: (parent.height - height) / 2
                    text: root.message
                    font.family: root.root.mono
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    font.letterSpacing: 1.5
                    color: root.root.ink
                    elide: Text.ElideRight
                }
            }
        }
    }
}
