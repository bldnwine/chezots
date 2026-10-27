import QtQuick
import Quickshell
ShellRoot {
    Window {
        visible: true
        width: 720; height: 480
        Item {
            id: test
            property int phase: 0
            function check(ok, message) { if (!ok) throw new Error(message); }
            QtObject {
                id: fakeRoot
                property int testPanelWidth: 720
                property int testPanelHeight: 480
                property bool btVisible: true
                property bool btAvailable: true
                property bool btPowered: true
                property int btCount: 0
                property bool btScanning: false
                property bool btBusy: false
                property string btError: ""
                property string btActionText: ""
                property var btDevices: []
                property string barEdge: "top"
                property real popupAnchorX: 100
                property real popupAnchorY: 20
                property color ink: "#eeeeee"
                property color inkDeep: "#aaaaaa"
                property color fg: "#ffffff"
                property color seal: "#55aaff"
                property color sep: "#555555"
                property color rowSel: "#333333"
                property color rowHi: "#222222"
                property int cornerRadius: 4
                property string mono: "monospace"
                function refreshBluetooth() {}
                function btToggleScan() { btScanning = !btScanning; }
                function btTogglePower() { btPowered = !btPowered; }
                function btConnect(mac) {}
                function btDisconnect(mac) {}
                function btToggleTrust(mac) {}
                function btUnpair(mac) {}
            }
            Loader { id: view; sourceComponent: BluetoothPopup { root: fakeRoot } }
            Timer {
                interval: 150; repeat: true; running: true
                onTriggered: {
                    const popup = view.item;
                    switch (test.phase++) {
                    case 0:
                        const devices = [];
                        for (let i = 0; i < 20; i++) devices.push({mac: "device-" + i, name: "Device " + i,
                            connected: false, paired: true, trusted: false, batteryAvailable: true, battery: 0, state: "PAIRED"});
                        fakeRoot.btDevices = devices;
                        Qt.callLater(function() { popup.kbdIndex = 19; });
                        break;
                    case 1:
                        test.check(popup.visibleDevs.length === 20, "device list truncated");
                        test.check(popup.testScrollY > 0, "keyboard selection not scrolled into view");
                        test.check(popup.testScrollHeight <= 220, "list exceeds small screen");
                        fakeRoot.btDevices = fakeRoot.btDevices.slice().reverse();
                        break;
                    case 2:
                        test.check(popup.kbdMac === "device-17", "sorting lost selected device");
                        fakeRoot.btDevices = fakeRoot.btDevices.filter(device => device.mac !== "device-17");
                        break;
                    case 3:
                        test.check(popup.kbdIndex < popup.kbdMax, "removal left invalid keyboard selection");
                        popup.kbdHandle({key: Qt.Key_S});
                        test.check(fakeRoot.btScanning, "scan shortcut failed");
                        popup.kbdHandle({key: Qt.Key_S});
                        test.check(!fakeRoot.btScanning, "scan shortcut did not cancel");
                        fakeRoot.btPowered = false;
                        break;
                    case 4:
                        test.check(popup.visibleDevs.length === 0, "powered-off list not cleared");
                        console.log("Bluetooth popup lifecycle tests passed");
                        Qt.quit();
                    }
                }
            }
        }
    }
}
