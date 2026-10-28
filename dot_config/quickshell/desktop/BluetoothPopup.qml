import QtQuick
import QtQuick.Controls

// Native Bluetooth view. Operations and live state belong to the persistent service.
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
               : root.btAvailable ? "POWER OFF" : "NO ADAPTER"
    footer: root.btPrompt.kind ? "ESC CANCEL" : "T TRUST · S SCAN · U UNPAIR"

    anchorEdge: btpopup.root.barEdge
    anchorBarX: btpopup.root.popupAnchorX
    anchorBarY: btpopup.root.popupAnchorY

    // 0 = POWER toggle, 1 = SCAN, 2..N+1 = device rows.
    property int kbdIndex: 2
    property string kbdMac: ""   // selected device; survives list re-sorts

    readonly property int headerCount: 2
    property var visibleDevs: root.btPowered
                              ? root.btDevices
                              : []
    readonly property int kbdMax: headerCount + visibleDevs.length

    // Re-home the selection cursor whenever the device list changes
    onVisibleDevsChanged: { btpopup.rehome(); Qt.callLater(btpopup.syncMac); }

    // Keep kbdMac in sync whenever the keyboard cursor moves
    onKbdIndexChanged: btpopup.syncMac()

    function syncMac() {
        const d = btpopup.visibleDevs[btpopup.kbdIndex - btpopup.headerCount];
        btpopup.kbdMac = d ? d.mac : "";
        if (d && deviceScroll) {
            const top = (btpopup.kbdIndex - btpopup.headerCount) * 38;
            if (top < deviceScroll.contentY) deviceScroll.contentY = top;
            else if (top + 32 > deviceScroll.contentY + deviceScroll.height)
                deviceScroll.contentY = top + 32 - deviceScroll.height;
        }
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
        if (root.btPrompt.kind) {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.btPrompt.kind !== "display") {
                root.btPairAnswer(true, pairCode.text); return true;
            }
            return false;
        }
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

    Component.onCompleted: {
        root.refreshBluetooth(); Qt.callLater(btpopup.syncMac);
        if (root.btPrompt.kind === "pin" || root.btPrompt.kind === "passkey")
            Qt.callLater(function() { if (btpopup.revealed) pairCode.forceActiveFocus(); });
    }

    onDismiss: root.btVisible = false
    Connections {
        target: root
        function onBtPromptChanged() {
            pairCode.text = "";
            if (root.btPrompt.kind === "pin" || root.btPrompt.kind === "passkey")
                Qt.callLater(function() { if (btpopup.revealed) pairCode.forceActiveFocus(); });
            else if (btpopup.revealed) btpopup.refocus();
        }
    }
    onKeyPressed: (event) => {
        if (btpopup.kbdHandle(event)) event.accepted = true;
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        Item {
            visible: !root.btPrompt.kind
            width: parent.width
            height: visible ? 28 : 0
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: !root.btAvailable ? "NO ADAPTER" : !root.btPowered ? "POWER OFF"
                      : (root.btDevices.length + " DEVICES"
                         + (root.btCount > 0
                            ? "  ·  " + root.btCount + " CONN"
                            : "")
                                      )
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
                    label: root.btScanning ? "STOP SCAN" : "SCAN"
                    selected: btpopup.kbdIndex === 1 || root.btScanning
                    onClicked: root.btToggleScan()
                }
            }
        }

        Column {
            width: parent.width
            visible: !!root.btPrompt.kind
            spacing: 10
            Text {
                width: parent.width; wrapMode: Text.Wrap
                color: root.ink; font.family: root.mono; font.pixelSize: 11
                text: root.btPrompt.kind === "display" ? "ENTER THIS CODE ON YOUR DEVICE"
                    : root.btPrompt.kind === "confirm" ? "CONFIRM THIS CODE MATCHES YOUR DEVICE"
                    : root.btPrompt.kind === "authorize" ? "ALLOW THIS DEVICE TO PAIR?"
                    : "ENTER THE CODE SHOWN ON YOUR DEVICE"
            }
            Text {
                visible: root.btPrompt.kind === "display" || root.btPrompt.kind === "confirm"
                text: root.btPrompt.code || ""; color: root.seal; font.family: root.mono; font.pixelSize: 22
            }
            TextInput {
                id: pairCode
                visible: root.btPrompt.kind === "pin" || root.btPrompt.kind === "passkey"
                width: parent.width; height: 30; color: root.ink; font.family: root.mono; font.pixelSize: 14
                maximumLength: root.btPrompt.kind === "pin" ? 16 : 6
                clip: true
                Keys.onReturnPressed: event => { root.btPairAnswer(true, text); event.accepted = true; }
                Keys.onEnterPressed: event => { root.btPairAnswer(true, text); event.accepted = true; }
                Keys.onEscapePressed: event => { root.btVisible = false; event.accepted = true; }
            }
            Row {
                spacing: 8
                QuickButton { root: btpopup.root; label: "CANCEL"; onClicked: root.btVisible = false }
                QuickButton { root: btpopup.root; visible: root.btPrompt.kind !== "display"; label: "CONFIRM"; onClicked: root.btPairAnswer(true, pairCode.text) }
            }
        }
        Rectangle { width: parent.width; height: 1; color: root.sep }

        Text {
            width: parent.width
            visible: !root.btPrompt.kind && text.length > 0
            text: root.btError || root.btActionText
            wrapMode: Text.Wrap
            color: root.btError ? root.seal : root.inkDeep
            font.family: root.mono
            font.pixelSize: 10
        }

        Flickable {
            id: deviceScroll
            visible: !root.btPrompt.kind
            width: col.width
            height: visible ? Math.min(deviceCol.height, Math.max(64, Math.min(360, (btpopup.screen ? btpopup.screen.height : btpopup.height) - 260))) : 0
            contentWidth: width
            contentHeight: deviceCol.height
            onContentHeightChanged: Qt.callLater(btpopup.syncMac)
            onHeightChanged: Qt.callLater(btpopup.syncMac)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: deviceCol
                width: deviceScroll.width
                spacing: 6
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
                                     ? "CONNECTED" + (modelData.batteryAvailable
                                                      ? " · " + modelData.battery + "%"
                                                      : "")
                                     : modelData.state || (modelData.paired ? "PAIRED" : ""))
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
                                btpopup._activateAt(index + btpopup.headerCount);
                            }
                        }
                    }
                }

            }
        }

        Text {
            visible: !root.btPrompt.kind && root.btPowered && root.btDevices.length === 0
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
