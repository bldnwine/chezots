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

    // Emil Kowalski Motion System:
    readonly property var motionCurve: [0.23, 1.0, 0.32, 1.0, 1.0, 1.0]
    readonly property int arriveDuration: 160
    readonly property int leaveDuration: 200
    readonly property real travel: 24

    property real _offsetY: 0
    property real _opacity: 0
    property bool _leaving: false

    // Decoupled display snapshot (preserves content during exit animation and C++ D-Bus destruction)
    property string displayedSummary: ""
    property string displayedBody: ""
    property string displayedApp: ""

    // Arrival: Clean stationary fade-in as before (zero vertical translation, zero stutter)
    NumberAnimation {
        id: arriveAnim
        target: root
        property: "_opacity"
        from: 0
        to: 1
        duration: root.arriveDuration
        easing.type: Easing.OutCubic
    }

    // Departure: Smooth Kowalski lift-out toward the bar
    ParallelAnimation {
        id: leaveAnim
        NumberAnimation {
            target: root
            property: "_offsetY"
            to: -root.travel
            duration: root.leaveDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: root.motionCurve
        }
        NumberAnimation {
            target: root
            property: "_opacity"
            to: 0
            duration: root.leaveDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: root.motionCurve
        }
        onFinished: {
            root._leaving = false;
            root.opened = false;
            root._offsetY = 0;
            root.currentNotif = null;
            root.currentNotifKey = "";
            root.displayedSummary = "";
            root.displayedBody = "";
            root.displayedApp = "";
        }
    }

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
        if (!notification) return;

        // Mid-exit revival: if departing, cancel exit and bring back smoothly to rest
        const wasLeaving = root._leaving;
        if (root._leaving) {
            leaveAnim.stop();
            root._leaving = false;
        }

        root.currentNotif = notification;
        root.displayedSummary = String(notification.summary || "");
        root.displayedBody = String(notification.body || "");
        root.displayedApp = String(notification.appName || "");

        root.currentNotifKey = "";
        for (let i = 0; i < retainedNotifications.count; i++) {
            const entry = retainedNotifications.get(i);
            if (entry.notification === notification) {
                root.currentNotifKey = entry.key;
                break;
            }
        }
        notification.tracked = true;

        if (!root.opened || wasLeaving) {
            root.opened = true;
            leaveAnim.stop();
            root._offsetY = 0;
            arriveAnim.restart();
        }

        var ms = Number(notification.expireTimeout || 0);
        if (notification.urgency === NotificationUrgency.Critical) {
            hideTimer.stop();
        } else {
            hideTimer.interval = ms > 0 ? Math.min(ms, 30000) : 5000;
            hideTimer.restart();
        }
    }

    function close(instant) {
        hideTimer.stop();
        if (instant) {
            arriveAnim.stop();
            leaveAnim.stop();
            root._leaving = false;
            root.opened = false;
            root._opacity = 0;
            root._offsetY = 0;
            root.currentNotif = null;
            root.currentNotifKey = "";
            root.displayedSummary = "";
            root.displayedBody = "";
            root.displayedApp = "";
            return;
        }

        if (!root.opened || root._leaving) return;
        root._leaving = true;
        arriveAnim.stop();
        leaveAnim.restart();
    }

    function invoke() {
        if (!root.currentNotif || root._leaving) return;
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
            root.close(false);
            root.root.notificationCenterService.editScreenshot(key, screenshotPath, screenshotTemporary);
            return;
        }
        // Non-resident actions may destroy the notification synchronously.
        // Close first with snapshot preserved before invoking action.
        root.close(false);
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
        onTriggered: root.close(false)
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
        function close(): string { root.close(true); return "ok"; }
        function dismiss(): string { root.close(true); return "ok"; }
        function ping(): string { return "ok"; }
        function state(): string { return (root.opened && !root._leaving) ? "open" : "closed"; }
        function toggleDnd(): string {
            if (root.root) root.root.toggleDnd();
            return root.doNotDisturb ? "on" : "off";
        }
    }

    PanelWindow {
        id: panel
        visible: root.opened || root._opacity > 0.001
        color: "transparent"
        anchors { top: true; right: true }
        margins {
            top: Math.max(0, (root.root.barEdge === "top" ? root.root.barOffset + 7 : 7) - root.travel)
            right: root.root.barEdge === "right" ? root.root.barOffset + 8 : 8
        }
        implicitWidth: card.implicitWidth
        implicitHeight: card.implicitHeight + root.travel
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omarchy-notifications"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: Region { item: card }

        Rectangle {
            id: card
            x: 0
            y: root.travel + root._offsetY
            width: card.implicitWidth
            height: card.implicitHeight
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
            Behavior on implicitHeight {
                enabled: root.opened && !root._leaving
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            MouseArea {
                id: cardMouse
                anchors.fill: parent
                enabled: root.opened && !root._leaving
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
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
                    text: root.displayedSummary
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
                    text: root.displayedBody
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
