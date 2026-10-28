import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "." as Desktop
ShellRoot {
    id: test
    property int phase: 0
    property string mode: "cancel"
    property int promptSignals: 0
    function check(ok, msg) { if (!ok) throw new Error(msg); }
    QtObject {
        id: device
        property string address: "AA:BB:CC:DD:EE:FF"
        property string dbusPath: "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
        property string name: "Test"
        property string deviceName: "Test"
        property bool connected: false
        property bool paired: false
        property bool trusted: false
        property bool pairing: false
        property bool batteryAvailable: false
        property real battery: 0
        property int state: BluetoothDeviceState.Disconnected
    }
    QtObject {
        id: adapter
        property bool enabled: true
        property bool discovering: false
        property QtObject devices: QtObject { property var values: [device] }
    }
    Desktop.BluetoothService {
        id: bt
        adapter: adapter
        powerDevices: []
        pairingCommand: ["python3", Quickshell.env("QS_PAIR_FIXTURE"), test.mode, Quickshell.env("QS_PAIR_MARKER")]
        cliPath: Quickshell.env("QS_TEST_AGENT")
        connectTimeoutMs: 2000
        onPairingPrompt: test.promptSignals++
    }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            switch (test.phase) {
            case 0: test.check(bt.connectDevice(device.address), "pair failed to start"); test.phase++; break;
            case 1:
                if (!bt.prompt.kind) break;
                test.check(bt.prompt.kind === "passkey" && bt.prompt.id === 7 && test.promptSignals === 1, "stale prompt replaced current prompt");
                test.check(!bt.answerPairing(true, "1234567"), "invalid passkey accepted");
                test.check(bt.cancelPairing(), "cancel failed"); test.phase++; break;
            case 2:
                if (bt.busy) break;
                test.check(bt.lastError === "Pairing canceled", "cancel result lost");
                test.mode = "success";
                test.check(bt.connectDevice(device.address), "second pair failed"); test.phase++; break;
            case 3:
                if (!bt.prompt.kind) break;
                test.check(bt.answerPairing(true, "42"), "valid answer rejected"); test.phase++; break;
            case 4:
                if (bt.phase !== "connect") break;
                device.paired = true; device.connected = true; test.phase++; break;
            case 5:
                if (bt.busy) break;
                test.check(!bt.lastError && device.connected, "pair then connect did not finish");
                device.connected = false; device.paired = false; test.mode = "hang"; bt.connectTimeoutMs = 300;
                test.check(bt.connectDevice(device.address), "timeout test did not start"); test.phase++; break;
            case 6:
                if (bt.busy) break;
                test.check(bt.lastError.indexOf("timed out") >= 0 && !bt.prompt.kind, "timeout leaked prompt");
                bt.connectTimeoutMs = 2000;
                test.check(bt.connectDevice(device.address), "adapter loss test did not start");
                bt.adapter = null; test.phase++; break;
            case 7:
                if (bt.busy) break;
                test.check(bt.lastError.indexOf("adapter changed") >= 0, "adapter loss stuck");
                bt.adapter = adapter;
                test.check(bt.connectDevice(device.address), "device loss test did not start");
                adapter.devices.values = []; test.phase++; break;
            case 8:
                if (bt.busy) break;
                test.check(bt.lastError.indexOf("device disappeared") >= 0, "device loss stuck");
                adapter.devices.values = [device];
                test.check(bt.connectDevice(device.address), "power loss test did not start");
                adapter.enabled = false; test.phase++; break;
            case 9:
                if (bt.busy) break;
                test.check(bt.lastError === "Bluetooth is powered off" && !bt.prompt.kind, "power loss stuck");
                console.log("Bluetooth pairing lifecycle tests passed"); Qt.quit();
            }
        }
    }
}
