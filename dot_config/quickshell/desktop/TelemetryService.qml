import QtQuick
import Quickshell.Io
import "TelemetryModel.js" as Model

// No subprocesses: preserve the 5s cadence and 2s CPU window, and read
// network counters once a second only while the bar can display bursts.
Item {
    id: service

    property bool systemEnabled: true
    property bool burstEnabled: true
    property string statPath: "/proc/stat"
    property string memoryPath: "/proc/meminfo"
    property string networkPath: "/proc/net/dev"
    property int systemIntervalMs: 5000
    property int cpuWindowMs: 2000
    property int burstIntervalMs: 1000
    property int burstSettleMs: 2500
    property int burstCooldownMs: 2000
    property real burstThresholdBytes: 1.5 * 1024 * 1024

    property int cpuVal: 0
    property int memVal: 0
    property real netBytes: -1
    property bool burstArmed: false
    signal netBurst()

    property int _systemGeneration: 0
    property int _statGeneration: 0
    property int _memoryGeneration: 0
    property bool _statBusy: false
    property bool _memoryBusy: false
    property bool _systemRequested: false
    property string _phase: "idle"
    property var _cpuStart: null
    property int _pendingCpu: 0

    onSystemEnabledChanged: {
        if (systemEnabled) return;
        _systemGeneration += 1;
        _systemRequested = false;
        _phase = "idle";
        _cpuStart = null;
        if (cpuWindow) cpuWindow.stop();
    }

    // Explicit popup refreshes work even when periodic sampling is paused.
    // An existing sample is allowed to finish, as with the old probe.
    function requestSystemSample() {
        if (_phase !== "idle") return;
        _systemRequested = true;
        tryStartSystem();
    }

    function tryStartSystem() {
        // A cancelled asynchronous read must drain before its reader is reused.
        if (!_systemRequested || _phase !== "idle" || _statBusy || _memoryBusy) return;
        _systemRequested = false;
        _phase = "start";
        readStat();
    }

    function readStat() {
        _statBusy = true;
        _statGeneration = _systemGeneration;
        if (statFile.path === statPath) statFile.reload();
        else statFile.path = statPath;
    }

    function finishStat(text) {
        if (!_statBusy) return;
        _statBusy = false;
        if (_statGeneration !== _systemGeneration) { tryStartSystem(); return; }
        const counters = Model.cpuCounters(text);
        if (!counters) { finishSystem(); return; }
        if (_phase === "start") {
            _cpuStart = counters;
            _phase = "window";
            cpuWindow.restart();
        } else if (_phase === "end") {
            const cpu = Model.cpuPercent(_cpuStart, counters);
            if (cpu === null) { finishSystem(); return; }
            _pendingCpu = cpu;
            _phase = "memory";
            _memoryBusy = true;
            _memoryGeneration = _systemGeneration;
            if (memoryFile.path === memoryPath) memoryFile.reload();
            else memoryFile.path = memoryPath;
        }
    }

    function finishMemory(text) {
        if (!_memoryBusy) return;
        _memoryBusy = false;
        if (_memoryGeneration !== _systemGeneration) { tryStartSystem(); return; }
        const memory = Model.memoryPercent(text);
        if (memory !== null && _phase === "memory") {
            cpuVal = _pendingCpu;
            memVal = memory;
        }
        finishSystem();
    }

    function finishSystem() {
        _phase = "idle";
        _cpuStart = null;
        tryStartSystem();
    }

    FileView {
        id: statFile
        // Start unloaded. Assigning the path on request starts a background
        // load; preload must stay enabled for reload() to perform reads.
        path: ""
        blockLoading: false
        blockAllReads: false
        watchChanges: false
        printErrors: false
        onLoaded: service.finishStat(text())
        onLoadFailed: service.finishStat(null)
    }
    FileView {
        id: memoryFile
        path: ""
        blockLoading: false
        blockAllReads: false
        watchChanges: false
        printErrors: false
        onLoaded: service.finishMemory(text())
        onLoadFailed: service.finishMemory(null)
    }
    Timer {
        interval: service.systemIntervalMs
        running: service.systemEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: service.requestSystemSample()
    }
    Timer {
        id: cpuWindow
        interval: service.cpuWindowMs
        onTriggered: {
            service._phase = "end";
            service.readStat();
        }
    }

    property int _netGeneration: 0
    property int _netReadGeneration: 0
    property bool _netBusy: false
    property bool _netRequested: false
    property var _netPrevious: null

    onBurstEnabledChanged: {
        _netGeneration += 1;
        _netRequested = false;
        _netPrevious = null;
        netBytes = -1;
        burstArmed = false;
        if (burstCooldown) burstCooldown.stop();
    }

    function requestNetworkSample() {
        if (!burstEnabled) return;
        if (_netBusy) { _netRequested = true; return; }
        _netRequested = false;
        _netBusy = true;
        _netReadGeneration = _netGeneration;
        if (networkFile.path === networkPath) networkFile.reload();
        else networkFile.path = networkPath;
    }

    function finishNetwork(text) {
        if (!_netBusy) return;
        _netBusy = false;
        if (_netReadGeneration === _netGeneration && burstEnabled) {
            const counters = Model.networkCounters(text);
            const delta = Model.networkDelta(_netPrevious, counters);
            // A failed read or interface/counter reset seeds the next sample.
            _netPrevious = counters;
            if (counters) netBytes = counters.total;
            if (delta !== null && burstArmed && delta > burstThresholdBytes) {
                burstArmed = false;
                burstCooldown.restart();
                netBurst();
            }
        }
        if (_netRequested && burstEnabled) requestNetworkSample();
    }

    FileView {
        id: networkFile
        path: ""
        blockLoading: false
        blockAllReads: false
        watchChanges: false
        printErrors: false
        onLoaded: service.finishNetwork(text())
        onLoadFailed: service.finishNetwork(null)
    }
    Timer {
        interval: service.burstIntervalMs
        running: service.burstEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: service.requestNetworkSample()
    }
    Timer {
        interval: service.burstSettleMs
        running: service.burstEnabled
        onTriggered: service.burstArmed = true
    }
    Timer {
        id: burstCooldown
        interval: service.burstCooldownMs
        onTriggered: service.burstArmed = true
    }
}
