import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io

// Native BlueZ state is always live; only pairing/connect needs a CLI agent.
Item {
    id: service
    visible: false
    property var adapter: Bluetooth.defaultAdapter
    property string cliPath: "bluetoothctl"
    property int actionTimeoutMs: 10000
    property int connectTimeoutMs: 55000
    readonly property bool available: adapter !== null
    readonly property bool powered: adapter !== null && adapter.enabled
    readonly property bool scanning: adapter !== null && adapter.discovering
    readonly property var objects: adapter ? adapter.devices.values : []
    readonly property var devices: {
        const result = objects.map(function(device) {
            return {mac: device.address, name: device.name || device.deviceName || device.address,
                connected: device.connected, paired: device.paired, trusted: device.trusted,
                batteryAvailable: device.batteryAvailable,
                battery: device.batteryAvailable ? Math.max(0, Math.min(100, Math.round(device.battery * 100))) : 0,
                state: device.pairing ? "PAIRING" : device.state === BluetoothDeviceState.Connecting ? "CONNECTING"
                    : device.state === BluetoothDeviceState.Disconnecting ? "DISCONNECTING"
                    : device.connected ? "CONNECTED" : device.paired ? "PAIRED" : ""};
        });
        result.sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name) || a.mac.localeCompare(b.mac));
        return result;
    }
    readonly property int count: devices.filter(device => device.connected).length
    readonly property bool busy: operation !== "" || agentActive
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
        runAgent();
        return true;
    }
    function runAgent() {
        agentActive = true;
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
        if (!busy) return;
        if (!adapter) { if (agent.running) agent.running = false; finish("Bluetooth adapter disappeared"); return; }
        const device = deviceFor(actionMac);
        if (operation === "power") { if (powered === wanted) finish(""); }
        else if (operation === "forget") { if (!device) finish(""); }
        else if (!device) { if (agent.running) agent.running = false; finish("Bluetooth device disappeared"); }
        else if (operation === "disconnect" && !device.connected) finish("");
        else if (operation === "trust" && device.trusted === wanted) finish("");
        else if (operation === "connect" && !agent.running && !startGuard.running) {
            if (phase === "pair" && device.paired) { phase = "connect"; runAgent(); }
            else if (phase === "connect" && device.connected) finish("");
        }
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
    onPoweredChanged: { if (!powered && scanAdapter) stopScan(); Qt.callLater(checkAction); }
    onAdapterChanged: {
        if (scanAdapter && scanAdapter !== adapter) stopScan();
        if (busy) { if (agent.running) agent.running = false; finish("Bluetooth adapter changed"); }
    }
    Process {
        id: agent
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onStarted: startGuard.stop()
        onExited: function(code) {
            startGuard.stop();
            service.agentActive = false;
            if (service.operation !== "connect") return;
            if (code !== 0) service.finish((errors.text || output.text || "Bluetooth connection failed").trim().slice(0, 512));
            else Qt.callLater(service.checkAction);
        }
    }
    Timer {
        id: startGuard
        interval: 1000
        onTriggered: if (service.operation === "connect" && !agent.running) {
            service.agentActive = false;
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
