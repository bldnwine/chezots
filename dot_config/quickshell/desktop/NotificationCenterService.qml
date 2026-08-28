import QtQuick
import Quickshell
import Quickshell.Io

// Notification Center background service.
// Manages the persistent notification archive, background watcher, unread counts, and store operations.
Item {
    id: root
    width: 0
    height: 0
    visible: false

    property int keepDays: 30
    property int maxItems: 1000
    property bool showPreview: true
    property int pageSize: 500

    property var entries: []
    property double lastSeen: 0
    property bool loaded: false

    readonly property bool watching: watchProc.running

    readonly property int unread: {
        var count = 0;
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].timestamp > lastSeen) count++;
            else break;
        }
        return count;
    }

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/notification-center"

    readonly property var storeEnvironment: ({
        "NC_KEEP_DAYS": String(root.keepDays),
        "NC_MAX_ITEMS": String(root.maxItems),
        "NC_PREVIEWS": root.showPreview ? "1" : "0"
    })

    signal entryAdded(var entry)
    signal entriesReset()

    function storeCommand(args) {
        return [root.script].concat(args);
    }

    function differsFrom(data) {
        if (!data || !entries) return true;
        if (data.length !== entries.length) return true;
        if (data.length === 0) return false;
        return String(data[0].key) !== String(entries[0].key);
    }

    function load() {
        if (listProc.running) return;
        listProc.command = root.storeCommand(["list", String(root.pageSize)]);
        listProc.running = true;
    }

    function readSeen() {
        if (seenProc.running) return;
        seenProc.command = root.storeCommand(["seen"]);
        seenProc.running = true;
    }

    function markSeen() {
        var stamp = Date.now();
        root.lastSeen = stamp;
        if (markProc.running) return;
        markProc.command = root.storeCommand(["seen", String(stamp)]);
        markProc.running = true;
    }

    function remove(key) {
        if (!key) return;
        var next = [];
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].key !== key) next.push(entries[i]);
        }
        entries = next;
        entriesReset();
        Quickshell.execDetached(root.storeCommand(["remove", String(key)]));
    }

    function clearAll() {
        entries = [];
        entriesReset();
        Quickshell.execDetached(root.storeCommand(["clear"]));
    }

    function absorb(line) {
        var entry;
        try {
            entry = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (!entry || !entry.key) return;
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].key === entry.key) return;
        }

        var next = [entry].concat(entries);
        if (next.length > pageSize) next = next.slice(0, pageSize);
        entries = next;
        entryAdded(entry);
    }

    Process {
        id: watchProc
        command: root.storeCommand(["watch"])
        environment: root.storeEnvironment
        running: true
        stdout: SplitParser {
            onRead: function(line) { root.absorb(line); }
        }
        onExited: restartWatch.restart()
    }

    Timer {
        id: restartWatch
        interval: 10000
        onTriggered: if (!watchProc.running) watchProc.running = true
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.load()
    }

    Process {
        id: listProc
        environment: root.storeEnvironment
        stdout: StdioCollector {
            onStreamFinished: {
                var data;
                try {
                    data = JSON.parse(text);
                } catch (e) {
                    return;
                }
                if (!Array.isArray(data)) return;
                var wasLoaded = root.loaded;
                root.loaded = true;
                if (wasLoaded && !root.differsFrom(data)) return;
                root.entries = data;
                root.entriesReset();
            }
        }
    }

    Process {
        id: seenProc
        environment: root.storeEnvironment
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    if (data.ok === true) root.lastSeen = Number(data.seen) || 0;
                } catch (e) {}
            }
        }
    }

    Process {
        id: markProc
        environment: root.storeEnvironment
    }

    Component.onCompleted: {
        readSeen();
        load();
    }
}
