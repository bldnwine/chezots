import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications

Item {
    id: root
    required property var root

    property bool opened: false
    readonly property bool doNotDisturb: Boolean(root.root && root.root.doNotDisturb)
    property var currentNotif: null

    property real _opacity: 0
    Behavior on _opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    property var _recentNotifHashes: ({})

    function recordNotification(notification) {
        if (!notification) return;
        var app = String(notification.appName || "");
        var summary = String(notification.summary || "");
        var body = String(notification.body || "");
        var hash = app + "|" + summary + "|" + body;
        var now = Date.now();
        if (root._recentNotifHashes[hash] && (now - root._recentNotifHashes[hash] < 3000)) {
            return;
        }
        root._recentNotifHashes[hash] = now;

        var stamp = now;
        var id = notification.id || Math.floor(Math.random() * 100000);
        var urgency = 1;
        if (notification.urgency === NotificationUrgency.Low) urgency = 0;
        else if (notification.urgency === NotificationUrgency.Critical) urgency = 2;

        var execArgv = [];
        if (notification.actions) {
            for (var i = 0; i < notification.actions.length; i++) {
                var a = notification.actions[i];
                if (a && a.identifier) execArgv.push(a.identifier);
            }
        }

        var glyph = "";
        var image = "";
        try {
            if (notification.hints) {
                if (notification.hints["image-path"]) image = String(notification.hints["image-path"]);
                if (notification.hints["image_path"]) image = String(notification.hints["image_path"]);
                if (notification.hints["omarchy-glyph"]) glyph = String(notification.hints["omarchy-glyph"]);
                if (notification.hints["glyph"]) glyph = String(notification.hints["glyph"]);
            }
        } catch (e) {}
        if (!image && notification.image) image = String(notification.image);

        var data = {
            key: stamp + "-" + id,
            app: String(notification.appName || ""),
            appIcon: String(notification.appIcon || ""),
            summary: String(notification.summary || ""),
            body: String(notification.body || ""),
            image: image,
            glyph: glyph,
            urgency: urgency,
            timestamp: stamp,
            execArgv: execArgv
        };

        var dir = Quickshell.env("HOME") + "/.local/state/quickshell-desktop/notifications";
        var file = dir + "/" + data.key + ".json";
        var jsonStr = JSON.stringify(data);

        Quickshell.execDetached(["bash", "-c", "mkdir -p " + JSON.stringify(dir) + " && printf '%s' " + JSON.stringify(jsonStr) + " > " + JSON.stringify(file)]);

        if (root.root && root.root.activeNotifications) {
            root.root.activeNotifications[data.key] = notification;
            var cleanupKey = data.key;
            notification.closed.connect(function() {
                if (root.root && root.root.activeNotifications) {
                    delete root.root.activeNotifications[cleanupKey];
                }
            });
        }
    }

    function showNotif(notification) {
        root.currentNotif = notification;
        notification.tracked = true;
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
        if (root.currentNotif) {
            try { root.currentNotif.tracked = false; } catch (e) {}
            root.currentNotif = null;
        }
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
        try { root.currentNotif.dismiss(); } catch (e) {}
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
        persistenceSupported: false
        onNotification: function(notification) {
            root.recordNotification(notification);
            if (root.doNotDisturb) {
                notification.tracked = false;
                return;
            }
            root.showNotif(notification);
        }
    }

    IpcHandler {
        target: "notifications"
        function close(): string { root.close(); return "ok"; }
        function ping(): string { return "ok"; }
        function state(): string { return root.opened ? "open" : "closed"; }
        function toggleDnd(): string {
            if (root.root) root.root.toggleDnd();
            return root.doNotDisturb ? "on" : "off";
        }
    }

    onOpenedChanged: root._opacity = root.opened ? 1 : 0

    PanelWindow {
        id: panel
        visible: _opacity > 0.001
        color: "transparent"
        anchors { top: true; right: true }
        margins { top: root.root.barOffset + 7; right: 8 }
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

            readonly property real contentNaturalWidth: Math.max(
                summaryText.implicitWidth,
                bodyText.implicitWidth
            )
            implicitWidth: Math.min(900, Math.max(320, contentNaturalWidth + 120))
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
                width: card.implicitWidth - 120

                Text {
                    id: summaryText
                    width: col.width
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
                    id: bodyText
                    width: col.width
                    text: root.currentNotif ? root.currentNotif.body : ""
                    font.family: root.root.mono
                    font.pixelSize: 13
                    color: root.root.inkDeep
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    visible: text.length > 0
                }
            }
        }
    }
}
