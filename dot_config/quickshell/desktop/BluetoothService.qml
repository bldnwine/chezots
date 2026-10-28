import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell
import Quickshell.Services.UPower

// Native BlueZ state is always live; pairing uses a local agent and connect uses bluetoothctl.
Item {
    id: service
    visible: false
    property var adapter: Bluetooth.defaultAdapter
    property var powerDevices: UPower.devices.values
    property var pairingCommand: ["python3", Quickshell.shellDir + "/scripts/bluetooth_helper.py"]
    property var prompt: ({kind: ""})
    property int pairSerial: 0
    property int pairJob: 0
    property int lastPromptId: 0
    property string pairPath: ""
    signal pairingPrompt()
    property string cliPath: "bluetoothctl"
    property int actionTimeoutMs: 10000
    property int connectTimeoutMs: 55000
    readonly property bool available: adapter !== null
    readonly property bool powered: adapter !== null && adapter.enabled
    readonly property bool scanning: adapter !== null && adapter.discovering
    readonly property var objects: adapter ? adapter.devices.values : []
    readonly property var devices: {
        const result = objects.map(function(device) {
            const mac = String(device.address || "").toLowerCase();
            const power = /^(?:[a-f0-9]{2}:){5}[a-f0-9]{2}$/.test(mac)
                ? powerDevices.find(p => !p.powerSupply && p.ready
                    && String(p.nativePath || "").toLowerCase().replace(/_/g, ":").indexOf(mac) >= 0) : null;
            const nativeBattery = device.batteryAvailable && isFinite(device.battery);
            const fallbackBattery = power && isFinite(power.percentage);
            const battery = nativeBattery ? device.battery : fallbackBattery ? power.percentage : 0;
            return {mac: device.address, name: device.name || device.deviceName || device.address,
                connected: device.connected, paired: device.paired, trusted: device.trusted,
                batteryAvailable: !!(nativeBattery || fallbackBattery),
                battery: Math.max(0, Math.min(100, Math.round(battery * 100))),
                state: device.pairing ? "PAIRING" : device.state === BluetoothDeviceState.Connecting ? "CONNECTING"
                    : device.state === BluetoothDeviceState.Disconnecting ? "DISCONNECTING"
                    : device.connected ? "CONNECTED" : device.paired ? "PAIRED" : ""};
        });
        result.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name) || a.mac.localeCompare(b.mac));
        return result;
    }
    readonly property int count: devices.filter(device => device.connected).length
    readonly property bool busy: operation !== "" || agentActive || pairAgent.active || agent.active
    property bool agentActive: false
    property string operation: ""
    property string actionMac: ""
    property string phase: ""
    property bool wanted: false
    property string lastError: ""
    property var scanAdapter: null
    readonly property string actionText: !busy ? "" : operation.toUpperCase() + (actionMac ? " · " + actionMac : "")

    function deviceFor(mac) { return objects.find(device => device.address === mac) || null; }
    function finish(error) {
        deadline.stop();
        startGuard.stop();
        operation = "";
        actionMac = "";
        phase = "";
        agentActive = false;
        prompt = {kind: ""};
        pairJob = 0; pairPath = "";
        if (pairAgent.running) pairAgent.running = false;
        lastError = error || "";
    }
    function begin(op, mac) {
        if (busy) return false;
        if (!adapter) { lastError = "No Bluetooth adapter available"; return false; }
        if (mac && !deviceFor(mac)) { lastError = "Bluetooth device is no longer available"; return false; }
        operation = op;
        actionMac = mac || "";
        lastError = "";
        deadline.interval = op === "connect" ? connectTimeoutMs : actionTimeoutMs;
        deadline.restart();
        return true;
    }
    function togglePower() {
        if (!begin("power", "")) return false;
        wanted = !powered;
        try { if (!wanted) stopScan(); adapter.enabled = wanted; }
        catch (error) { finish(String(error)); return false; }
        Qt.callLater(checkAction);
        return true;
    }
    function connectDevice(mac) {
        if (!begin("connect", mac)) return false;
        if (!powered) { finish("Bluetooth is powered off"); return false; }
        phase = deviceFor(mac).paired ? "connect" : "pair";
        if (phase === "pair") runPairAgent(); else runAgent();
        return true;
    }
    function runPairAgent() {
        const device = deviceFor(actionMac);
        pairPath = device && device.dbusPath || "";
        if (!/^\/org\/bluez\/hci\d+\/dev_(?:[0-9A-Fa-f]{2}_){5}[0-9A-Fa-f]{2}$/.test(pairPath)) { finish("Bluetooth device path unavailable"); return; }
        pairJob = ++pairSerial;
        lastPromptId = 0;
        pairAgent.sent = false;
        pairAgent.active = true;
        pairAgent.command = pairingCommand.slice();
        agentActive = true;
        pairAgent.stdinEnabled = true;
        pairAgent.running = true;
        startGuard.restart();
    }
    function answerPairing(accept, value) {
        if (!pairAgent.running || !prompt.kind || prompt.kind === "display") return false;
        const code = String(value || "");
        if (accept && ((prompt.kind === "passkey" && !/^[0-9]{1,6}$/.test(code)) || (prompt.kind === "pin" && (code.length < 1 || code.length > 16)))) return false;
        pairAgent.write(JSON.stringify({action: "answer", promptId: prompt.id, accept: !!accept, value: code}) + "\n");
        return true;
    }
    function cancelPairing() {
        if (operation !== "connect" || phase !== "pair") return false;
        prompt = {kind: ""};
        phase = "cancelling";
        if (pairAgent.running) pairAgent.write(JSON.stringify({action: "cancel"}) + "\n");
        deadline.interval = 1000; deadline.restart();
        return true;
    }
    function runAgent() {
        if (operation !== "connect" || phase !== "connect") return;
        agentActive = true;
        agent.active = true;
        agent.command = [cliPath, "--timeout", "25", "--agent", "NoInputNoOutput", phase, actionMac];
        agent.running = true;
        startGuard.restart();
    }
    function nativeAction(op, mac) {
        if (!begin(op, mac)) return false;
        const device = deviceFor(mac);
        try {
            if (op === "disconnect") device.disconnect();
            else if (op === "trust") { wanted = !device.trusted; device.trusted = wanted; }
            else if (op === "forget") device.forget();
        } catch (error) { finish(String(error)); return false; }
        Qt.callLater(checkAction);
        return true;
    }
    function checkAction() {
        if (operation === "") return;
        if (!adapter) { if (agent.running) agent.running = false; finish("Bluetooth adapter disappeared"); return; }
        const device = deviceFor(actionMac);
        if (operation === "power") { if (powered === wanted) finish(""); }
        else if (operation === "forget") { if (!device) finish(""); }
        else if (!device) { if (agent.running) agent.running = false; finish("Bluetooth device disappeared"); }
        else if (operation === "disconnect" && !device.connected) finish("");
        else if (operation === "trust" && device.trusted === wanted) finish("");
        else if (operation === "connect" && phase === "connect" && !agent.running && !startGuard.running && device.connected) finish("");
    }
    function toggleScan() {
        if (scanning || scanAdapter) { stopScan(); return true; }
        if (!powered) { lastError = available ? "Bluetooth is powered off" : "No Bluetooth adapter available"; return false; }
        lastError = "";
        scanAdapter = adapter;
        try { adapter.discovering = true; } catch (error) { scanAdapter = null; lastError = String(error); return false; }
        scanDeadline.restart();
        scanStartGuard.restart();
        return true;
    }
    function stopScan() {
        scanDeadline.stop();
        scanStartGuard.stop();
        const target = scanAdapter || adapter;
        scanAdapter = null;
        try { if (target && target.discovering) target.discovering = false; }
        catch (error) { lastError = String(error); }
    }
    onDevicesChanged: Qt.callLater(checkAction)
    onPoweredChanged: {
        if (!powered && scanAdapter) stopScan();
        if (!powered && operation === "connect") {
            if (agent.running) agent.running = false;
            finish("Bluetooth is powered off");
        }
        Qt.callLater(checkAction);
    }
    onAdapterChanged: {
        if (scanAdapter && scanAdapter !== adapter) stopScan();
        if (operation !== "") { if (agent.running) agent.running = false; finish("Bluetooth adapter changed"); }
    }
    Process {
        id: pairAgent
        property bool sent: false
        property bool active: false
        stdout: SplitParser {
            onRead: line => {
                let msg;
                try { msg = JSON.parse(line); } catch (error) { service.finish("Invalid Bluetooth pairing response"); return; }
                if (["pair", "cancelling"].indexOf(service.phase) < 0 || service.operation !== "connect") return;
                if (service.phase === "cancelling") { if (msg.event === "result") service.finish("Pairing canceled"); return; }
                if (msg.event === "ready" && !pairAgent.sent) {
                    pairAgent.sent = true;
                    pairAgent.write(JSON.stringify({id: service.pairJob, action: "pair", path: service.pairPath}) + "\n");
                } else if (msg.event === "prompt") {
                    if (!msg.kind) { service.prompt = {kind: ""}; return; }
                    if (msg.path !== service.pairPath || !Number.isInteger(msg.id) || ["pin", "passkey", "display", "confirm", "authorize"].indexOf(msg.kind) < 0) { service.finish("Invalid Bluetooth pairing prompt"); return; }
                    if (msg.id <= service.lastPromptId) return;
                    service.lastPromptId = msg.id;
                    service.prompt = {id: msg.id, kind: msg.kind, code: String(msg.code || ""), entered: Number(msg.entered || 0)};
                    service.pairingPrompt();
                } else if (msg.event === "result") {
                    if (msg.id !== service.pairJob || msg.path !== service.pairPath || typeof msg.success !== "boolean") { service.finish("Invalid Bluetooth pairing result"); return; }
                    service.prompt = {kind: ""};
                    if (!msg.success) service.finish(String(msg.error || "Bluetooth pairing failed").slice(0, 512));
                    else { service.phase = "connect"; startGuard.restart(); Qt.callLater(service.runAgent); }
                }
            }
        }
        onStarted: startGuard.stop()
        onExited: function(code) {
            pairAgent.active = false;
            if (service.operation === "connect" && (service.phase === "pair" || service.phase === "cancelling")) {
                service.agentActive = false;
                service.finish(service.phase === "cancelling" ? "Pairing canceled" : "Bluetooth pairing helper stopped");
            }
        }
    }
    Process {
        id: agent
        property bool active: false
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onStarted: startGuard.stop()
        onExited: function(code) {
            startGuard.stop();
            agent.active = false;
            service.agentActive = false;
            if (service.operation !== "connect") return;
            if (code !== 0) service.finish((errors.text || output.text || "Bluetooth connection failed").trim().slice(0, 512));
            else Qt.callLater(service.checkAction);
        }
    }
    Timer {
        id: startGuard
        interval: 1000
        onTriggered: if (service.operation === "connect" && !agent.running && !pairAgent.running) {
            service.agentActive = false;
            pairAgent.active = false; agent.active = false;
            service.finish("Could not start Bluetooth authorization agent");
        }
    }
    Timer {
        id: deadline
        onTriggered: {
            const message = service.operation + " timed out";
            service.finish(message);
            if (agent.running) agent.running = false;
        }
    }
    Timer { id: scanDeadline; interval: 15000; onTriggered: service.stopScan() }
    Timer {
        id: scanStartGuard
        interval: 2000
        onTriggered: if (!service.scanning) { service.stopScan(); service.lastError = "Bluetooth discovery did not start"; }
    }
    Component.onDestruction: if (scanAdapter) stopScan()
}
