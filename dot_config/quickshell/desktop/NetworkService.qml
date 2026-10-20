import QtQuick
import Quickshell
import Quickshell.Io

// Survives the popup Loader: mutations finish even after the view closes.
Item {
    id: service
    property string helperPath: Qt.resolvedUrl("scripts/network_helper.py").toString().replace(/^file:\/\//, "")
    property var helperCommand: ["python3", helperPath]
    property int scanTimeoutMs: 15000
    property int stateTimeoutMs: 10000
    property int detailsTimeoutMs: 4000
    property int mutationTimeoutMs: 10000
    property int actionTimeoutMs: 30000
    property int cleanupGraceMs: 1000
    property bool viewVisible: false
    property var networks: []
    property bool radioOn: true
    property bool scanning: false
    property bool busy: false
    property string wifiActionText: ""
    property string wifiError: ""
    property string wifiErrorKind: ""
    property string netDetailsError: ""
    property var info: ({})
    property real downloadRate: 0
    property real uploadRate: 0
    property real internetPing: -1
    property int packetLoss: 0
    property var pingSamples: []
    property double prevRx: 0
    property double prevTx: 0
    property double prevTime: 0
    property string routeKey: ""

    property int epoch: 0
    property int viewEpoch: 0
    property bool scanAgain: false
    property string queuedScanOwner: "popup"
    property bool stateAgain: false
    property bool preserveActionError: false
    property string actionOp: ""
    property string actionSsid: ""
    signal wifiConnectResult(string ssid, bool ok)

    function resetRates() {
        prevRx = 0; prevTx = 0; prevTime = 0; routeKey = "";
        downloadRate = 0; uploadRate = 0;
        pingSamples = []; internetPing = -1; packetLoss = 0;
    }
    function parse(text) {
        try {
            const result = JSON.parse(text);
            return result && typeof result.ok === "boolean" ? result : null;
        } catch (error) { return null; }
    }
    function validNetworks(result) {
        return result && result.ok && typeof result.radioOn === "boolean"
            && Array.isArray(result.networks) && result.networks.every(n => n
                && typeof n.ssid === "string" && typeof n.security === "string"
                && typeof n.signal === "number" && isFinite(n.signal)
                && typeof n.inUse === "boolean" && typeof n.known === "boolean");
    }
    function validDetails(result) {
        const value = result && result.info;
        return result && result.ok && value && typeof value.iface === "string"
            && typeof value.ip === "string" && typeof value.gateway === "string"
            && typeof value.rx_bytes === "number" && isFinite(value.rx_bytes) && value.rx_bytes >= 0
            && typeof value.tx_bytes === "number" && isFinite(value.tx_bytes) && value.tx_bytes >= 0
            && typeof value.sample_time === "number" && isFinite(value.sample_time)
            && (value.internet_ping_ms === null || (typeof value.internet_ping_ms === "number"
                && isFinite(value.internet_ping_ms) && value.internet_ping_ms >= 0));
    }
    function setNetworks(value) {
        if (JSON.stringify(value) !== JSON.stringify(networks)) networks = value;
    }
    function syncWifiActiveState(ssid) {
        if (busy) return;
        applyActiveState(ssid);
    }
    function applyActiveState(ssid) {
        const updated = networks.map(n => Object.assign({}, n, {
            inUse: !!ssid && n.ssid === ssid,
            known: n.known || !!(ssid && n.ssid === ssid)
        }));
        updated.sort((a, b) => (b.inUse - a.inUse) || (b.signal - a.signal));
        setNetworks(updated);
    }

    function launch(proc, request, deadline, milliseconds) {
        proc.pending = true;
        proc.timedOut = false;
        proc.cancelled = false;
        proc.hasStarted = false;
        proc.reply = "";
        proc.stopAt = 0;
        proc.requestJson = JSON.stringify(request);
        proc.command = Array.isArray(helperCommand) ? helperCommand.slice() : [];
        if (!proc.command.length || !proc.command[0]) {
            proc.requestJson = "";
            finish(proc, -1, 1, true);
            return false;
        }
        proc.stdinEnabled = true;
        proc.running = true;
        deadline.interval = milliseconds;
        deadline.restart();
        launchGuard.start();
        return true;
    }
    function sendRequest(proc) {
        proc.hasStarted = true;
        proc.write(proc.requestJson + "\n");
        proc.stdinEnabled = false;
        proc.requestJson = "";
    }
    function cancel(proc) {
        if (!proc.pending) return;
        proc.cancelled = true;
        if (!proc.stopAt) proc.stopAt = Date.now() + cleanupGraceMs;
        if (proc.running) proc.signal(15);
        cleanupTimer.start();
    }
    function timedOut(proc) {
        if (!proc.pending) return;
        proc.timedOut = true;
        if (!proc.stopAt) proc.stopAt = Date.now() + cleanupGraceMs;
        if (proc.running) proc.signal(15);
        else finish(proc, -1, 1, !proc.hasStarted);
        cleanupTimer.start();
    }
    function requestScan(owner) {
        const who = owner || "external";
        if (who === "popup" && !viewVisible) return false;
        if (busy || readProcess.pending) {
            scanAgain = true;
            if (who === "external" || queuedScanOwner !== "external") queuedScanOwner = who;
            return false;
        }
        preserveActionError = false;
        wifiError = ""; wifiErrorKind = "";
        return launchRead("scan", who);
    }
    function refreshWifi() { return requestScan("external"); }
    function requestState() {
        if (busy || readProcess.pending) { stateAgain = true; return false; }
        return launchRead("state", "external");
    }
    function launchRead(kind, owner) {
        readProcess.kind = kind;
        readProcess.owner = owner;
        readProcess.epoch = epoch;
        scanning = kind === "scan";
        return launch(readProcess, {op: kind}, readDeadline,
                      kind === "scan" ? scanTimeoutMs : stateTimeoutMs);
    }
    function drainReads() {
        if (busy || readProcess.pending) return;
        if (scanAgain) {
            const owner = queuedScanOwner;
            scanAgain = false; queuedScanOwner = "popup";
            if (owner !== "popup" || viewVisible) {
                stateAgain = false;
                requestScan(owner);
                return;
            }
        }
        if (stateAgain) { stateAgain = false; requestState(); }
    }
    function requestDetails() {
        if (!viewVisible || busy || detailsProcess.pending) return false;
        detailsProcess.epoch = viewEpoch;
        return launch(detailsProcess, {op: "details"}, detailsDeadline, detailsTimeoutMs);
    }
    function beginMutation(op, args) {
        if (busy || actionProcess.pending) return false;
        if (["connect", "forget", "autoconnect"].indexOf(op) >= 0
            && (!args || typeof args.ssid !== "string" || !args.ssid)) return false;
        busy = true;
        ++epoch;
        actionOp = op;
        actionSsid = (args && args.ssid) || "";
        wifiActionText = ({connect: "Connecting…", disconnect: "Disconnecting…",
            radio: "Changing Wi-Fi…", forget: "Forgetting network…",
            autoconnect: "Updating autoconnect…"})[op] || "Working…";
        wifiError = ""; wifiErrorKind = ""; preserveActionError = false;
        cancel(readProcess);
        cancel(detailsProcess);
        stateAgain = false;
        return launch(actionProcess, Object.assign({op: op}, args || {}), actionDeadline,
                      op === "connect" ? actionTimeoutMs : mutationTimeoutMs);
    }
    function request(op, args) {
        if (op === "scan") return requestScan();
        if (op === "state") return requestState();
        if (op === "details") return requestDetails();
        if (["connect", "disconnect", "radio", "forget", "autoconnect"].indexOf(op) < 0) return false;
        return beginMutation(op, args || {});
    }
    function wifiConnect(ssid, passphrase) { return beginMutation("connect", {ssid: ssid, passphrase: passphrase || ""}); }
    function forgetWifi(ssid) { return beginMutation("forget", {ssid: ssid}); }
    function wifiToggleAutoConnect(ssid) { return beginMutation("autoconnect", {ssid: ssid}); }
    function disconnectWifi() { return beginMutation("disconnect", {}); }
    function toggleWifiRadio() { return beginMutation("radio", {enabled: !radioOn}); }

    function finish(proc, code, status, launchFailed) {
        if (!proc.pending) return;
        const result = parse(proc.reply);
        const success = status === 0 && code === 0 && !proc.timedOut
            && !proc.cancelled && !launchFailed && result && result.ok === true;
        const error = proc.timedOut ? "Network operation timed out"
            : launchFailed ? "Network helper could not be started"
            : (result && typeof result.error === "string" && result.error)
                || "Network helper returned an invalid response";
        const errorKind = proc.timedOut ? "timeout" : launchFailed ? "unavailable"
            : (result && result.errorKind) || "malformed";
        proc.pending = false;
        proc.stopAt = 0;
        proc.requestJson = "";
        proc.reply = "";
        if (proc === actionProcess) {
            actionDeadline.stop();
            const op = actionOp, ssid = actionSsid;
            if (success) {
                if (op === "radio" && typeof result.enabled === "boolean") radioOn = result.enabled;
                if (op === "connect") applyActiveState(ssid);
                if (op === "disconnect") applyActiveState("");
            } else {
                wifiError = error; wifiErrorKind = errorKind; preserveActionError = true;
            }
            busy = false; actionOp = ""; actionSsid = ""; wifiActionText = "";
            if (op === "connect") wifiConnectResult(ssid, !!success);
            // One bounded state read even if the popup has since closed.
            stateAgain = true;
            drainReads();
            if (viewVisible) requestDetails();
        } else if (proc === readProcess) {
            readDeadline.stop();
            scanning = false;
            const eligible = proc.epoch === epoch && !proc.cancelled && !busy;
            if (eligible && success && validNetworks(result)) {
                setNetworks(result.networks);
                radioOn = result.radioOn;
                if (!preserveActionError) { wifiError = ""; wifiErrorKind = ""; }
            } else if (eligible && !preserveActionError) {
                wifiError = success ? "Invalid Wi-Fi network list" : error;
                wifiErrorKind = success ? "malformed" : errorKind;
            }
            drainReads();
        } else {
            detailsDeadline.stop();
            if (proc.epoch !== viewEpoch || proc.cancelled || !viewVisible || busy) return;
            if (success && validDetails(result)) applyDetails(result.info);
            else netDetailsError = success ? "Invalid network details" : error;
        }
    }
    function applyDetails(value) {
        const key = [value.iface, value.ip, value.gateway].join("|");
        if (key !== routeKey) { resetRates(); routeKey = key; }
        if (prevTime > 0 && value.sample_time > prevTime) {
            const elapsed = value.sample_time - prevTime;
            downloadRate = Math.max(0, (value.rx_bytes - prevRx) / elapsed);
            uploadRate = Math.max(0, (value.tx_bytes - prevTx) / elapsed);
        }
        prevRx = value.rx_bytes; prevTx = value.tx_bytes; prevTime = value.sample_time;
        info = value;
        if (value.iface) {
            pingSamples = pingSamples.concat([value.internet_ping_ms]).slice(-24);
            const recent = pingSamples.slice(-5).filter(v => typeof v === "number");
            internetPing = recent.length ? recent.reduce((sum, v) => sum + v, 0) / recent.length : -1;
            packetLoss = Math.round(pingSamples.filter(v => v === null).length * 100 / pingSamples.length);
        }
        netDetailsError = "";
    }
    function copyText(value) {
        if (clipboardProcess.running) return false;
        clipboardProcess.value = String(value);
        clipboardProcess.stdinEnabled = true;
        clipboardProcess.running = true;
        return true;
    }

    onViewVisibleChanged: {
        ++viewEpoch;
        resetRates(); info = ({}); netDetailsError = "";
        if (viewVisible) {
            requestScan("popup");
            requestDetails();
        } else {
            if (queuedScanOwner === "popup") scanAgain = false;
            if (readProcess.owner === "popup") cancel(readProcess);
            cancel(detailsProcess);
        }
    }
    Process {
        id: actionProcess
        property bool pending: false
        property bool hasStarted: false
        property bool timedOut: false
        property bool cancelled: false
        property double stopAt: 0
        property string requestJson: ""
        property string reply: ""
        stdout: StdioCollector { onStreamFinished: actionProcess.reply = this.text }
        onStarted: service.sendRequest(this)
        onExited: function(code, status) { service.finish(this, code, status, false); }
    }
    Process {
        id: readProcess
        property bool pending: false
        property bool hasStarted: false
        property bool timedOut: false
        property bool cancelled: false
        property double stopAt: 0
        property string requestJson: ""
        property string reply: ""
        property string kind: ""
        property string owner: ""
        property int epoch: 0
        stdout: StdioCollector { onStreamFinished: readProcess.reply = this.text }
        onStarted: service.sendRequest(this)
        onExited: function(code, status) { service.finish(this, code, status, false); }
    }
    Process {
        id: detailsProcess
        property bool pending: false
        property bool hasStarted: false
        property bool timedOut: false
        property bool cancelled: false
        property double stopAt: 0
        property string requestJson: ""
        property string reply: ""
        property int epoch: 0
        stdout: StdioCollector { onStreamFinished: detailsProcess.reply = this.text }
        onStarted: service.sendRequest(this)
        onExited: function(code, status) { service.finish(this, code, status, false); }
    }
    Process {
        id: clipboardProcess
        property string value: ""
        command: ["wl-copy"]
        onStarted: { write(value); stdinEnabled = false; value = ""; }
        onExited: value = ""
    }
    Timer { id: actionDeadline; onTriggered: service.timedOut(actionProcess) }
    Timer { id: readDeadline; onTriggered: service.timedOut(readProcess) }
    Timer { id: detailsDeadline; onTriggered: service.timedOut(detailsProcess) }
    Timer {
        id: cleanupTimer
        interval: 50
        repeat: true
        onTriggered: {
            let waiting = false;
            for (const proc of [readProcess, actionProcess, detailsProcess]) {
                if (proc.pending && proc.stopAt) {
                    waiting = true;
                    if (proc.running && Date.now() >= proc.stopAt) proc.signal(9);
                }
            }
            if (!waiting) stop();
        }
    }
    Timer {
        id: launchGuard
        interval: 250
        repeat: true
        onTriggered: {
            let waiting = false;
            for (const proc of [readProcess, actionProcess, detailsProcess]) {
                if (proc.pending && !proc.hasStarted) {
                    if (!proc.running) service.finish(proc, -1, 1, true);
                    else waiting = true;
                }
            }
            if (!waiting) stop();
        }
    }
    Timer {
        interval: 1500
        running: service.viewVisible
        repeat: true
        onTriggered: service.requestDetails()
    }
}
