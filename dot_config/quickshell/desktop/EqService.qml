import QtQuick
import Quickshell

// Persistent across popup closure. Preset operations share the same queue as
// live changes so they see the last requested state, never a partial update.
Item {
    id: service
    property string scriptPath: Qt.resolvedUrl("scripts/pipewire-eq").toString().replace(/^file:\/\//, "")
    property string statePath: Quickshell.env("HOME") + "/.local/state/quickshell-desktop/eq-state.json"
    property string presetsPath: Quickshell.env("HOME") + "/.local/state/quickshell-desktop/eq-presets.json"
    property var desiredState: null
    property string lastError: ""
    property int _revision: 0
    property bool _lastApplySucceeded: true
    readonly property bool busy: jobs.busy
    readonly property bool isApplied: _lastApplySucceeded && !busy
    readonly property bool mutating: {
        if (jobs.current && jobs.current.context.action !== "live") return true;
        return jobs.pending.some(job => job.context.action !== "live");
    }
    signal completed(string action, bool success, string message)

    function apply(state, explicit) {
        desiredState = JSON.parse(JSON.stringify(state));
        _lastApplySucceeded = false;
        const action = explicit ? "apply" : "live";
        submit(action, ["python3", scriptPath, action, JSON.stringify(desiredState)], explicit ? "" : "live", "APPLIED");
    }

    function submit(action, command, key, message) {
        _revision += 1;
        jobs.enqueue(command, key, { action: action, revision: _revision, message: message });
    }

    function save(name) { submit("save", ["python3", scriptPath, "save", name], "", "SAVED: " + name); }
    function remove(name) { submit("delete", ["python3", scriptPath, "delete", name], "", "DELETED"); }
    function importText(text) { submit("import", ["python3", scriptPath, "import", text], "", "IMPORTED"); }
    function exportToClipboard() {
        submit("export", ["bash", "-c", "set -o pipefail; python3 \"$1\" export | wl-copy", "eq-export", scriptPath], "", "COPIED TO CLIPBOARD");
    }

    CommandQueue {
        id: jobs
        label: "equalizer"
        onFinished: function(job, code, output, error) {
            const action = job.context.action;
            const success = code === 0;
            if (action === "live" || action === "apply" || action === "import")
                service._lastApplySucceeded = success;
            let message = job.context.message;
            if (!success) {
                try { message = JSON.parse(error).error || error; }
                catch (e) { message = error || "EQ command failed"; }
                service.lastError = String(message).slice(0, 180);
            } else if (action === "live" || action === "apply" || action === "import") {
                service.lastError = "";
            }
            if (!success || job.context.revision === service._revision)
                service.completed(action, success, String(message).slice(0, 180));
        }
    }

}
