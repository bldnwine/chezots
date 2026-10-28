import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import "." as Desktop

ShellRoot {
    id: test
    property int phase: 0
    function check(ok, message) { if (!ok) throw new Error(message); }
    QtObject {
        id: device
        property string address: "AA:BB:CC:DD:EE:FF"
        property string name: "Headset"
        property string deviceName: "Headset"
        property bool connected: true
        property bool paired: true
        property bool trusted: false
        property bool pairing: false
        property bool batteryAvailable: true
        property real battery: 0
        property int state: BluetoothDeviceState.Connected
        function disconnect() { connected = false; }
        function forget() { adapter.devices.values = []; }
    }
    QtObject {
        id: adapter
        property bool enabled: true
        property bool discovering: false
        property QtObject devices: QtObject { property var values: [device] }
    }
    QtObject {
        id: power
        property bool ready: false
        property bool powerSupply: false
        property string nativePath: "AA_BB_CC_DD_EE_FF"
        property bool isPresent: true
        property bool isLaptopBattery: true
        property real percentage: 0.42
        property real changeRate: 6.5
        property int state: UPowerDeviceState.Discharging
    }
    Desktop.BluetoothService { id: bt; adapter: adapter; powerDevices: [power]; actionTimeoutMs: 100; connectTimeoutMs: 100; cliPath: Quickshell.env("QS_TEST_AGENT") }
    Desktop.BatteryService { id: battery; device: power }
    Timer {
        interval: 150; repeat: true; running: true
        onTriggered: {
            switch (test.phase++) {
            case 0:
                test.check(!battery.ready && battery.state === "Unknown", "unavailable UPower data fabricated");
                power.ready = true;
                test.check(battery.present && battery.percentage === 42 && battery.watts === 6.5, "UPower units incorrect");
                power.state = UPowerDeviceState.Charging;
                test.check(battery.state === "Charging", "charging state stale");
                power.isLaptopBattery = false;
                test.check(!battery.present && battery.percentage === 0 && battery.state === "AC", "peripheral treated as laptop battery");
                power.isLaptopBattery = true;
                power.isPresent = false;
                test.check(!battery.present, "missing battery present");
                test.check(bt.count === 1 && bt.devices[0].battery === 0 && bt.devices[0].batteryAvailable, "zero battery hidden");
                device.batteryAvailable = false;
                test.check(bt.devices[0].batteryAvailable && bt.devices[0].battery === 42, "UPower battery fallback failed");
                device.batteryAvailable = true;
                device.battery = .65;
                test.check(bt.devices[0].battery === 65, "native battery change not reactive");
                bt.nativeAction("trust", device.address);
                break;
            case 1:
                test.check(!bt.busy && device.trusted, "trust did not settle");
                bt.toggleScan();
                test.check(adapter.discovering, "scan did not start");
                bt.toggleScan();
                test.check(!adapter.discovering, "scan did not cancel");
                bt.nativeAction("disconnect", device.address);
                break;
            case 2:
                test.check(!bt.busy && bt.count === 0, "disconnect did not settle");
                bt.connectDevice(device.address);
                break;
            case 3:
                test.check(!bt.busy && bt.lastError.length > 0, "failed connection stuck busy or error hidden");
                bt.nativeAction("forget", device.address);
                break;
            case 4:
                test.check(!bt.busy && bt.devices.length === 0, "forget did not settle");
                bt.toggleScan();
                bt.adapter = null;
                test.check(!bt.available && !adapter.discovering, "adapter replacement leaked discovery");
                console.log("hardware service lifecycle tests passed");
                Qt.quit();
            }
        }
    }
}
