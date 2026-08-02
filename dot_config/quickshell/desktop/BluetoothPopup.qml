import QtQuick

// Bluetooth popup — same iwd-free bluez-tools body as QuickBluetoothBody
// (power toggle, scan, device list) in a CardWindow, plus the connected
// device's battery percentage in the status tag. Backed by Navbar's
// btDevices probe (already carries { mac, name, connected, paired,
// trusted, battery }).
CardWindow {
    id: btpopup
    required property var root

    theme: root
    plain: true
    revealed: root.btVisible
    cardWidth: 390
    layerNamespace: "omarchy-bluetooth"
    title: "BLUETOOTH"
    subtitle: root.btPowered
               ? (root.btDevices.length + " DEVICES"
                  + (root.btCount > 0 ? " · " + root.btCount + " CONN" : ""))
               : "POWER OFF"
    footer: "T TRUST · S SCAN · U UNPAIR · ESC CLOSE"

    anchorEdge: btpopup.root.barEdge
    anchorBarX: btpopup.root.popupAnchorX
    anchorBarY: btpopup.root.popupAnchorY

    // 0 = POWER toggle, 1 = SCAN, 2..N+1 = device rows.
    property int kbdIndex: 2
    property string kbdMac: ""   // selected device; survives list re-sorts

    readonly property int headerCount: 2
    property var visibleDevs: root.btPowered
                              ? root.btDevices.slice(0, 8)
                              : []
    readonly property int kbdMax: headerCount + visibleDevs.length

    // Re-home the selection cursor whenever the device list changes
    onVisibleDevsChanged: btpopup.rehome()

    // Keep kbdMac in sync whenever the keyboard cursor moves
    onKbdIndexChanged: btpopup.syncMac()

    function syncMac() {
        const d = btpopup.visibleDevs[btpopup.kbdIndex - btpopup.headerCount];
        btpopup.kbdMac = d ? d.mac : "";
    }

    function rehome() {
        if (btpopup.kbdMac !== "") {
            const devs = btpopup.visibleDevs;
            for (let i = 0; i < devs.length; i++) {
                if (devs[i].mac === btpopup.kbdMac) {
                    btpopup.kbdIndex = i + btpopup.headerCount;
                    return;
                }
            }
        }
        if (btpopup.kbdIndex >= btpopup.kbdMax)
            btpopup.kbdIndex = Math.max(0, btpopup.kbdMax - 1);
    }

    function kbdHandle(event) {
        const k = event.key;
        const n = btpopup.kbdMax;
        if (n === 0) return false;
        if (k === Qt.Key_Up || k === Qt.Key_Left) {
            btpopup.kbdIndex = Math.max(0, btpopup.kbdIndex - 1);
            return true;
        }
        if (k === Qt.Key_Down || k === Qt.Key_Right || k === Qt.Key_Tab) {
            btpopup.kbdIndex = Math.min(n - 1, btpopup.kbdIndex + 1);
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            btpopup._activateAt(btpopup.kbdIndex);
            return true;
        }
        if (k === Qt.Key_T) {
            const dev = btpopup.visibleDevs[btpopup.kbdIndex - btpopup.headerCount];
            if (dev) root.btToggleTrust(dev.mac);
            return true;
        }
        if (k === Qt.Key_S) {
            root.btToggleScan();
            return true;
        }
        if (k === Qt.Key_U) {
            const dev = btpopup.visibleDevs[btpopup.kbdIndex - btpopup.headerCount];
            if (dev) root.btUnpair(dev.mac);
            return true;
        }
        return false;
    }

    function _activateAt(i) {
        btpopup.kbdIndex = i;
        if (i === 0) { root.btTogglePower(); return; }
        if (i === 1) { root.btToggleScan(); return; }
        const dev = btpopup.visibleDevs[i - btpopup.headerCount];
        if (!dev) return;
        if (dev.connected) root.btDisconnect(dev.mac);
        else root.btConnect(dev.mac);
    }

    Component.onCompleted: root.refreshBluetooth()

    onDismiss: root.btVisible = false
    onKeyPressed: (event) => {
        if (btpopup.kbdHandle(event)) event.accepted = true;
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        Item {
            width: parent.width
            height: 28
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: !root.btPowered ? "POWER OFF"
                      : (root.btDevices.length + " DEVICES"
                         + (root.btCount > 0
                            ? "  ·  " + root.btCount + " CONN"
                            : "")
                         + (root.btScanning ? "  ·  SCANNING" : ""))
                color: root.inkDeep
                font.family: root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                QuickButton {
                    root: btpopup.root
                    label: root.btPowered ? "POWER OFF" : "POWER ON"
                    selected: btpopup.kbdIndex === 0
                    onClicked: root.btTogglePower()
                }
                QuickButton {
                    root: btpopup.root
                    label: root.btScanning ? "SCANNING" : "SCAN"
                    selected: btpopup.kbdIndex === 1 || root.btScanning
                    onClicked: root.btToggleScan()
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: root.sep }

        Repeater {
            model: btpopup.visibleDevs
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool kbdFocused: btpopup.kbdIndex === (index + btpopup.headerCount)
                readonly property bool dimmed: !modelData.paired && !modelData.connected
                width: col.width
                height: 32
                radius: root.cornerRadius
                color: modelData.connected || kbdFocused
                       ? root.rowSel
                       : devMouse.containsMouse
                           ? root.rowHi
                           : "transparent"
                border.color: modelData.connected || kbdFocused ? root.seal : root.sep
                border.width: kbdFocused ? 2 : 1
                Behavior on color        { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
                Behavior on border.width { NumberAnimation { duration: 120 } }

                Text {
                    id: devIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.connected ? "󰂱" : (modelData.paired ? "󰂯" : "󰂲")
                    color: modelData.connected ? root.seal : root.ink
                    font.family: root.mono
                    font.pixelSize: 14
                    opacity: dimmed ? 0.55 : 1
                }
                Text {
                    anchors.left: devIcon.right
                    anchors.right: tag.left
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    elide: Text.ElideRight
                    color: modelData.connected ? root.ink : root.fg
                    font.family: root.mono
                    font.pixelSize: 11
                    font.weight: modelData.connected ? Font.Medium : Font.Normal
                    opacity: dimmed ? 0.55 : 1
                }
                Text {
                    id: tag
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: (modelData.trusted ? "✓ " : "")
                          + (modelData.connected
                             ? "CONNECTED" + (modelData.battery > 0
                                              ? " · " + modelData.battery + "%"
                                              : "")
                             : modelData.paired ? "PAIRED"
                                                : "")
                    color: root.inkDeep
                    font.family: root.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1.5
                    opacity: dimmed ? 0.55 : 1
                }
                MouseArea {
                    id: devMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            root.btUnpair(modelData.mac);
                            return;
                        }
                        btpopup._activateAt(index + btpopup._headerCount);
                    }
                }
            }
        }

        Text {
            visible: root.btPowered && root.btDevices.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "NO DEVICES — TAP SCAN"
            color: root.inkDeep
            font.family: root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
            opacity: 0.6
        }
    }
}
