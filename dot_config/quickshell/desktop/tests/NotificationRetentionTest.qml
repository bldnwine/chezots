import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import ".." as Desktop

ShellRoot {
    id: test
    property var notifications: []
    property bool completed: false
    function check(condition, message) { if (!condition) throw new Error(message); }

    Item {
        id: navbar
        property var activeNotifications: ({})
        property bool doNotDisturb: false
        property var notificationCenterService: QtObject {
            property int maxItems: 3
            property int keepDays: 30
            property var editArgs: []
            signal screenshotOpened(string key)
            function editScreenshot(key, path, temporary) { editArgs = [key, path, temporary]; }
        }
        property string barEdge: "top"
        property int barOffset: 0
        property color bg: "black"
        property color sep: "gray"
        property color ink: "white"
        property color inkDeep: "gray"
        property string mono: "monospace"
        property var theme: QtObject { property int cornerRadius: 0 }
    }
    Desktop.NotificationOverlay {
        id: overlay
        root: navbar
        archiveDirectory: Quickshell.env("QS_TEST_ARCHIVE_DIR")
    }
    Component {
        id: fakeNotification
        QtObject {
            property int id: 0
            property string appName: "Quickshell regression test"
            property string appIcon: ""
            property string summary: ""
            property string body: ""
            property string image: ""
            property var hints: ({})
            property var actions: []
            property int urgency: NotificationUrgency.Normal
            property real expireTimeout: -1
            property bool tracked: true
            property bool expired: false
            signal closed()
            function expire() { expired = true; closed(); }
            function dismiss() { closed(); }
        }
    }
    Component.onCompleted: {
        for (let i = 1; i <= 5; i++) {
            const n = fakeNotification.createObject(test, { id: i, summary: "Notification " + i });
            notifications.push(n);
            test.check(overlay.recordNotification(n), "recording failed");
        }
        test.check(overlay.retainedCount === 3, "live notification cap was not enforced");
        test.check(notifications[0].expired && notifications[1].expired, "evicted objects were not expired");
        test.check(Object.keys(navbar.activeNotifications).length === 6, "stale action references remained");
        notifications[4].dismiss();
        test.check(overlay.retainedCount === 2, "closed notification was not removed");
        test.check(!navbar.activeNotifications["id:5"], "closed action reference remained");
        const duplicate = fakeNotification.createObject(test, { id: 6, summary: "Notification 4" });
        test.check(!overlay.recordNotification(duplicate), "duplicate archive entry was accepted");
        test.check(overlay.recordNotification(notifications[3]), "replacement should preserve live actions");
        const screenshot1 = fakeNotification.createObject(test, { id: 7, summary: "Screenshot", hints: {
            "x-owlcat-screenshot-path": "/tmp/first.png", "x-owlcat-screenshot-temporary": true } });
        const screenshot2 = fakeNotification.createObject(test, { id: 8, summary: "Screenshot", hints: {
            "x-owlcat-screenshot-path": "/tmp/second.png", "x-owlcat-screenshot-temporary": true } });
        test.check(overlay.recordNotification(screenshot1), "first screenshot rejected");
        test.check(overlay.recordNotification(screenshot2), "distinct screenshot deduplicated");
        overlay.showNotif(screenshot2);
        const key = overlay.currentNotifKey;
        test.check(key.length > 0, "screenshot key missing");
        overlay.invoke();
        const args = navbar.notificationCenterService.editArgs;
        test.check(args[0] === key && args[1] === "/tmp/second.png" && args[2] === true,
                   "screenshot click did not route metadata");
        completed = true;
    }
    Timer {
        interval: 3300
        running: true
        onTriggered: {
            test.check(test.completed, "initial lifecycle assertions failed");
            test.check(Object.keys(overlay._recentNotifHashes).length === 0, "dedup cache did not expire");
            console.log("notification lifecycle regression tests passed");
            Qt.quit();
        }
    }
}
