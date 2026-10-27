import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "NotificationModel.js" as NotificationModel

Item {
    id: root
    required property var root

    property bool opened: false
    readonly property bool doNotDisturb: Boolean(root.root && root.root.doNotDisturb)
    property var currentNotif: null
    property string currentNotifKey: ""

    property real _opacity: 0
    Behavior on _opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    property var _recentNotifHashes: ({})
    property string archiveDirectory: Quickshell.env("HOME") + "/.local/state/quickshell-desktop/notifications"
    ListModel { id: retainedNotifications; dynamicRoles: true }
    readonly property int retainedCount: retainedNotifications.count

    function removeRetainedAt(index, expire) {
        const entry = retainedNotifications.get(index);
        const notification = entry.notification;
        if (root.root && root.root.activeNotifications) {
            delete root.root.activeNotifications[entry.key];
            const idKey = "id:" + entry.notificationId;
            if (root.root.activeNotifications[idKey] === notification)
                delete root.root.activeNotifications[idKey];
        }
        if (root.currentNotif === notification) root.close();
        // Disconnect the closed handler before expiring an evicted object.
        retainedNotifications.remove(index);
        if (expire && notification) notification.expire();
    }

    function releaseNotification(key) {
        for (let i = retainedNotifications.count - 1; i >= 0; i--) {
            if (retainedNotifications.get(i).key === key) {
                root.removeRetainedAt(i, false);
                return;
            }
        }
    }

    function pruneRetained() {
        const service = root.root ? root.root.notificationCenterService : null;
        const maxItems = service ? service.maxItems : 1000;
        const keepDays = service ? service.keepDays : 30;
        const now = Date.now();
        for (let i = retainedNotifications.count - 1; i >= 0; i--) {
            const entry = retainedNotifications.get(i);
            if (i >= maxItems || NotificationModel.outsideRetention(entry.timestamp, now, keepDays))
                root.removeRetainedAt(i, true);
        }
    }

    Instantiator {
        model: retainedNotifications
        delegate: Connections {
            required property string key
            required property var notification
            target: notification
            function onClosed() { root.releaseNotification(key); }
        }
    }
    Connections {
        target: root.root ? root.root.notificationCenterService : null
        function onScreenshotOpened(key) {
            if (root.root && root.root.removeNotification) root.root.removeNotification(key);
        }
    }
    Timer {
        id: dedupExpiry
        interval: 3000
        onTriggered: root._recentNotifHashes = ({})
    }
    Timer {
        interval: 60000
        running: retainedNotifications.count > 0
        repeat: true
        onTriggered: root.pruneRetained()
    }

    function recordNotification(notification) {
        if (!notification) return false;
        var app = String(notification.appName || "");
        var summary = String(notification.summary || "");
        var body = String(notification.body || "");
        var screenshotPath = "";
        var screenshotTemporary = false;
        try {
            if (notification.hints) {
                screenshotPath = String(notification.hints["x-owlcat-screenshot-path"] || "");
                screenshotTemporary = notification.hints["x-owlcat-screenshot-temporary"] === true;
            }
        } catch (e) {}
        var hash = JSON.stringify([app, summary, body, screenshotPath]);
        var now = Date.now();
        root._recentNotifHashes = NotificationModel.recentHashes(root._recentNotifHashes, now);
        if (root._recentNotifHashes[hash] && (now - root._recentNotifHashes[hash] < 3000)) {
            // Replacements reuse the live object; don't expire that object's
            // existing archive actions merely because its content is unchanged.
            for (let i = 0; i < retainedNotifications.count; i++) {
                if (retainedNotifications.get(i).notification === notification) return true;
            }
            return false;
        }
        root._recentNotifHashes[hash] = now;
        dedupExpiry.restart();

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
            execArgv: execArgv,
            screenshotPath: screenshotPath,
            screenshotTemporary: screenshotTemporary
        };

        var dir = root.archiveDirectory;
        var file = dir + "/" + data.key + ".json";
        var jsonStr = JSON.stringify(data);

        Quickshell.execDetached(["sh", "-c", "mkdir -p -- \"$1\" && printf '%s' \"$2\" > \"$3\"",
            "sh", dir, jsonStr, file]);

        if (root.root && root.root.activeNotifications) {
            for (let i = retainedNotifications.count - 1; i >= 0; i--) {
                const previous = retainedNotifications.get(i);
                if (previous.notificationId === id)
                    root.removeRetainedAt(i, previous.notification !== notification);
            }
            root.root.activeNotifications[data.key] = notification;
            if (notification.id) {
                root.root.activeNotifications["id:" + notification.id] = notification;
            }
            retainedNotifications.insert(0, {
                key: data.key, notificationId: id, timestamp: stamp, notification: notification
            });
            root.pruneRetained();
        }
        return true;
    }

    function showNotif(notification) {
        root.currentNotif = notification;
        root.currentNotifKey = "";
        for (let i = 0; i < retainedNotifications.count; i++) {
            const entry = retainedNotifications.get(i);
            if (entry.notification === notification) {
                root.currentNotifKey = entry.key;
                break;
            }
        }
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
        root.currentNotif = null;
        root.currentNotifKey = "";
        hideTimer.stop();
    }

    function invoke() {
        if (!root.currentNotif) return;
        const notification = root.currentNotif;
        const key = root.currentNotifKey;
        var screenshotPath = "";
        var screenshotTemporary = false;
        try {
            if (notification.hints) {
                screenshotPath = String(notification.hints["x-owlcat-screenshot-path"] || "");
                screenshotTemporary = notification.hints["x-owlcat-screenshot-temporary"] === true;
            }
        } catch (e) {}
        if (screenshotPath && key && root.root && root.root.notificationCenterService) {
            root.close();
            root.root.notificationCenterService.editScreenshot(key, screenshotPath, screenshotTemporary);
            return;
        }
        // Non-resident actions may destroy the notification synchronously.
        // Close the card first and avoid a second dismiss after invoking.
        root.close();
        try {
            for (var i = 0; i < notification.actions.length; i++) {
                var a = notification.actions[i];
                if (a && a.identifier === "default") { a.invoke(); return; }
            }
        } catch (e) {}
        try { notification.dismiss(); } catch (e) {}
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
            notification.tracked = true;
            if (!root.recordNotification(notification)) { notification.expire(); return; }
            if (root.doNotDisturb) {
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
        margins {
            top: root.root.barEdge === "top" ? root.root.barOffset + 7 : 7
            right: root.root.barEdge === "right" ? root.root.barOffset + 8 : 8
        }
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
