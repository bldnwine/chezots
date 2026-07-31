import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications

Item {
    id: root
    required property var root

    property bool opened: false
    property bool doNotDisturb: false
    property var currentNotif: null

    property real _opacity: 0
    Behavior on _opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    function showNotif(notification) {
        root.currentNotif = notification;
        root.opened = true;
        var ms = Number(notification.expireTimeout || 0);
        if (notification.urgency === NotificationUrgency.Critical) {
            hideTimer.stop();
        } else {
            hideTimer.interval = ms > 0 ? Math.min(ms, 30000) : 5000;
            hideTimer.restart();
        }
    }

    function close() {
        root.opened = false;
        root.currentNotif = null;
        hideTimer.stop();
    }

    function invoke() {
        if (!root.currentNotif) return;
        try {
            for (var i = 0; i < root.currentNotif.actions.length; i++) {
                var a = root.currentNotif.actions[i];
                if (a && a.identifier === "default") { a.invoke(); break; }
            }
        } catch (e) {}
        root.currentNotif.dismiss();
        root.close();
    }

    Timer {
        id: hideTimer
        onTriggered: root.close()
    }

    NotificationServer {
        actionsSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: function(notification) {
            if (root.doNotDisturb) {
                notification.tracked = false;
                return;
            }
            notification.tracked = true;
            root.showNotif(notification);
        }
    }

    IpcHandler {
        target: "notifications"
        function close(): string { root.close(); return "ok"; }
        function ping(): string { return "ok"; }
        function state(): string { return root.opened ? "open" : "closed"; }
        function toggleDnd(): string {
            root.doNotDisturb = !root.doNotDisturb;
            if (root.root) root.root.run("qs -c desktop ipc call -- osd show "
                + JSON.stringify({ icon: "󰂛",
                                   message: root.doNotDisturb ? "NOTIFICATIONS OFF" : "NOTIFICATIONS ON" }));
            return root.doNotDisturb ? "on" : "off";
        }
    }

    onOpenedChanged: root._opacity = root.opened ? 1 : 0

    PanelWindow {
        id: panel
        visible: _opacity > 0.001
        color: "transparent"
        anchors { top: true; right: true }
        margins { top: root.root.barHeight + root.root.barExtraThickness + 7; right: 8 }
        implicitWidth: card.implicitWidth
        implicitHeight: card.implicitHeight
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omarchy-notifications"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            id: card
            anchors.fill: parent
            color: root.root.bg
            border.color: root.root.sep
            border.width: 1
            radius: root.root.theme.cornerRadius
            opacity: root._opacity
            implicitWidth: col.implicitWidth + 120
            implicitHeight: col.implicitHeight + 60

            MouseArea {
                anchors.fill: parent
                onClicked: root.invoke()
            }

            Column {
                id: col
                x: 60
                y: 30
                spacing: 4
                width: Math.max(200, col.implicitWidth)

                Text {
                    text: root.currentNotif ? root.currentNotif.summary : ""
                    font.family: root.root.mono
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    font.letterSpacing: 1.5
                    color: root.root.ink
                    elide: Text.ElideRight
                    visible: text.length > 0
                }

                Text {
                    text: root.currentNotif ? root.currentNotif.body : ""
                    font.family: root.root.mono
                    font.pixelSize: 13
                    color: root.root.inkDeep
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    visible: text.length > 0
                }
            }
        }
    }
}
