import QtQuick
import Quickshell.Io

// The index outlives the lazily loaded wallpaper panel.
Item {
    id: service
    property string helperPath: Qt.resolvedUrl("scripts/wallpaper-scan.py").toString().replace(/^file:\/\//, "")
    property var scanCommand: ["python3", helperPath]
    property int staleAfterMs: 30000
    property int timeoutMs: 30000
    property var wallpapers: []
    property bool hasIndex: false
    property bool scanning: false
    property double lastSuccess: 0
    property string error: ""
    property bool rescanRequested: false
    property bool timedOut: false
    property bool processExited: false
    property bool outputFinished: false
    property int exitCode: -1
    property int exitStatus: -1
    property string outputText: ""

    function enter() {
        if (!hasIndex || Date.now() - lastSuccess >= staleAfterMs)
            requestRefresh(false);
    }
    function requestRefresh(force) {
        if (scanning) {
            if (force) rescanRequested = true;
            return;
        }
        timedOut = false;
        processExited = false;
        outputFinished = false;
        outputText = "";
        scanning = true;
        scanProcess.command = scanCommand;
        scanProcess.running = true;
        deadline.restart();
    }
    function validIndex(value) {
        return Array.isArray(value) && value.every(item => item
            && typeof item.name === "string" && typeof item.path === "string"
            && typeof item.mtime === "number" && isFinite(item.mtime)
            && typeof item.btime === "number" && isFinite(item.btime)
            && typeof item.size === "number" && isFinite(item.size));
    }
    function finishIfReady() {
        if (!scanning || !processExited || !outputFinished) return;
        deadline.stop();
        if (!timedOut && exitCode === 0 && exitStatus === 0) {
            try {
                const data = JSON.parse(outputText);
                if (!validIndex(data)) throw new Error("Invalid wallpaper index");
                if (!hasIndex || JSON.stringify(wallpapers) !== JSON.stringify(data))
                    wallpapers = data;
                hasIndex = true;
                lastSuccess = Date.now();
                error = "";
            } catch (e) { error = "Wallpaper index could not be read"; }
        } else {
            error = timedOut ? "Wallpaper scan timed out" : "Wallpaper scan failed";
        }
        scanning = false;
        if (rescanRequested) {
            rescanRequested = false;
            Qt.callLater(() => requestRefresh(false));
        }
    }
    Process {
        id: scanProcess
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                service.outputText = this.text;
                service.outputFinished = true;
                service.finishIfReady();
            }
        }
        onExited: function(code, status) {
            service.exitCode = code;
            service.exitStatus = status;
            service.processExited = true;
            service.finishIfReady();
        }
    }
    Timer {
        id: deadline
        interval: service.timeoutMs
        onTriggered: {
            service.timedOut = true;
            scanProcess.running = false;
        }
    }
}
