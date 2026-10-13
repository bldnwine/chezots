import QtQuick
import Quickshell
import Quickshell.Io
import "CalendarModel.js" as Model

// Owned by Navbar so closing the popup cannot interrupt a Google mutation.
Item {
    id: root
    property bool viewVisible: false
    property string eventsPath: Quickshell.env("HOME") + "/.local/state/omarchy/calendar-events.json"
    property string actionScript: Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/calendar-sync/action.py"
    property var syncCommand: ["systemctl", "--user", "start", "omarchy-calendar-sync.service"]
    property var eventDoc: null
    property var _optimisticEvents: null
    readonly property var allEvents: _optimisticEvents !== null ? _optimisticEvents : (eventDoc ? eventDoc.events : [])
    property bool _actionPending: false
    property bool _syncPending: false
    readonly property bool syncing: _syncPending || _actionPending || syncProcess.running || actionProcess.running
    readonly property bool actionRunning: _actionPending || actionProcess.running
    property string lastError: ""
    property int _syncFailures: 0
    property double _nextAutoSyncMs: 0
    property bool _syncRequested: false
    property bool _actionTimedOut: false
    property bool _syncTimedOut: false

    function ensureFresh() {
        if (Date.now() < root._nextAutoSyncMs) return;
        const synced = root.eventDoc ? Date.parse(root.eventDoc.syncedAt || "") : NaN;
        if (!isFinite(synced) || Date.now() - synced > 120000) root.syncNow();
    }

    function syncNow() {
        if (root.actionRunning) { root._syncRequested = true; return; }
        if (root._syncPending || syncProcess.running) return;
        root._syncTimedOut = false;
        root._syncPending = true;
        syncProcess.command = root.syncCommand;
        syncProcess.running = true;
    }

    function runAction(args, optimistic) {
        if (root.syncing) { root.lastError = "Another Calendar operation is still running"; return false; }
        root.lastError = "";
        root._actionTimedOut = false;
        root._actionPending = true;
        root._optimisticEvents = optimistic;
        actionProcess.command = ["python3", root.actionScript].concat(args);
        actionProcess.running = true;
        return true;
    }

    function createEvent(title, dateKey, start, end, allDay, location) {
        const events = root.allEvents.slice();
        const next = Model.dateFromKey(dateKey);
        next.setDate(next.getDate() + 1);
        events.push({id: "pending-" + Date.now(), calendarId: "primary", calendarName: "Personal",
            color: "#658594", dateKey: dateKey, title: title, location: location || "", allDay: allDay,
            start: allDay ? dateKey : dateKey + "T" + start + ":00",
            end: allDay ? Model.keyForDate(next) : dateKey + "T" + end + ":00", meetingUrl: "", eventUrl: ""});
        const args = ["create", "--calendar", "primary", "--title", title, "--date", dateKey];
        if (allDay) args.push("--all-day");
        else args.push("--start", start, "--end", end);
        if (location) args.push("--location", location);
        return root.runAction(args, events);
    }

    function deleteEvent(calId, eventId) {
        const events = root.allEvents.filter(e => !(e.calendarId === calId && e.id === eventId));
        return root.runAction(["delete", "--calendar", calId, "--id", eventId], events);
    }

    function editEvent(calId, eventId, title, dateKey, start, end, allDay) {
        // A title-only edit must preserve multi-day/all-day start and end.
        const events = root.allEvents.map(function(event) {
            if (event.calendarId !== calId || event.id !== eventId) return event;
            const changed = Object.assign({}, event, {title: title});
            if (dateKey && (allDay || (start && end))) {
                changed.dateKey = dateKey;
                changed.allDay = allDay;
                changed.start = allDay ? dateKey : dateKey + "T" + start + ":00";
                const next = Model.dateFromKey(dateKey);
                next.setDate(next.getDate() + 1);
                changed.end = allDay ? Model.keyForDate(next) : dateKey + "T" + end + ":00";
            }
            return changed;
        });
        const args = ["edit", "--calendar", calId, "--id", eventId, "--title", title];
        if (dateKey && (allDay || (start && end))) {
            args.push("--date", dateKey);
            if (allDay) args.push("--all-day");
            else args.push("--start", start, "--end", end);
        }
        return root.runAction(args, events);
    }

    onViewVisibleChanged: if (root.viewVisible) root.ensureFresh()

    FileView {
        id: eventsFile
        path: root.eventsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const doc = JSON.parse(text());
                if (doc.version !== 1 || !Array.isArray(doc.events)) throw new Error("Invalid Calendar cache");
                root.eventDoc = doc;
            } catch (error) { root.lastError = "Could not read Calendar cache; refresh to recover"; }
            // Reading the cache must never launch a sync: failed syncs leave
            // the old file in place, and reload -> sync would loop forever.
        }
    }

    Process {
        id: syncProcess
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { id: syncError; waitForEnd: true }
        onExited: function(code) {
            root._syncPending = false;
            if (code !== 0 || root._syncTimedOut) {
                root._syncFailures++;
                root._nextAutoSyncMs = Date.now() + Math.min(300000, 30000 * Math.pow(2, root._syncFailures - 1));
                root.lastError = root._syncTimedOut ? "Calendar sync timed out"
                    : String(syncError.text || "").trim() || "Calendar sync failed; retry or check its service logs";
            } else {
                root._syncFailures = 0;
                root._nextAutoSyncMs = 0;
                root.lastError = "";
                eventsFile.reload();
            }
        }
    }
    Process {
        id: actionProcess
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { id: actionError; waitForEnd: true }
        onExited: function(code) {
            root._actionPending = false;
            root._optimisticEvents = null;
            if (code !== 0 || root._actionTimedOut) {
                root.lastError = root._actionTimedOut ? "Calendar action timed out; refresh to confirm its outcome"
                    : String(actionError.text || "").trim() || "Calendar action failed";
                if (root._actionTimedOut || /sync to confirm/i.test(root.lastError)) root._syncRequested = true;
            } else {
                root.lastError = "";
                root._syncRequested = true;
            }
            eventsFile.reload();
            if (root._syncRequested) {
                root._syncRequested = false;
                Qt.callLater(root.syncNow);
            }
        }
    }
    Timer {
        interval: 120000; running: actionProcess.running
        onTriggered: { root._actionTimedOut = true; actionProcess.running = false; }
    }
    Timer {
        interval: 130000; running: syncProcess.running
        onTriggered: { root._syncTimedOut = true; syncProcess.running = false; }
    }
    Timer {
        interval: 300000; repeat: true; running: root.viewVisible
        onTriggered: root.ensureFresh()
    }
    Timer {
        interval: 30000; repeat: true; running: root.viewVisible && root._syncFailures > 0
        onTriggered: root.ensureFresh()
    }
}
