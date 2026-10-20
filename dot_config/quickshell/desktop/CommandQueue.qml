import QtQuick
import Quickshell.Io

// One owner, one running command. Other owners have independent instances.
// Only pending absolute settings are coalesced; discrete actions are barriers.
Item {
    id: queue
    property string label: "command"
    property var pending: []
    property var current: null
    property string lastError: ""
    property bool _finishing: false
    property bool _started: false
    readonly property bool busy: current !== null || pending.length > 0 || _finishing
    signal finished(var job, int exitCode, string output, string error)

    function enqueue(command, key, context) {
        if (!Array.isArray(command) || command.length === 0) return false;
        const jobs = pending.slice();
        const replaceKey = key || "";
        if (replaceKey) {
            for (let i = jobs.length - 1; i >= 0; i--) {
                if (!jobs[i].key) break;
                if (jobs[i].key === replaceKey) { jobs.splice(i, 1); break; }
            }
        }
        jobs.push({ command: command.slice(), key: replaceKey, context: context || ({}) });
        pending = jobs;
        pump();
        return true;
    }

    function pump() {
        if (current || _finishing || process.running || pending.length === 0) return;
        const jobs = pending.slice();
        current = jobs.shift();
        pending = jobs;
        _started = false;
        process.command = current.command;
        process.running = true;
        startGuard.restart();
    }

    function complete(code, output, error) {
        if (!current) return;
        startGuard.stop();
        _finishing = true;
        const job = current;
        current = null;
        lastError = code === 0 ? "" : String(error || "Command exited with code " + code).trim().slice(0, 4096);
        if (code !== 0) console.warn("[" + label + "] command failed, exit code " + code);
        finished(job, code, output, lastError);
        _finishing = false;
        nextCommand.restart();
    }

    Process {
        id: process
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onStarted: { queue._started = true; startGuard.stop(); }
        onExited: function(code) { queue.complete(code, output.text, errors.text); }
    }
    Timer {
        id: nextCommand
        interval: 0
        onTriggered: queue.pump()
    }
    Timer {
        id: startGuard
        interval: 1000
        onTriggered: {
            if (!queue._started && !process.running)
                queue.complete(-1, "", "Could not start command");
        }
    }
}
