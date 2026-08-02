import QtQuick

// Wi-Fi detail — radio toggle + scan + network list. Backend is iwd
// (iwctl). Rows dim when the network isn't saved yet; right-click a
// saved+disconnected row to forget it. Clicking/Entering an unknown
// protected network swaps the row for a masked passphrase field (iwctl
// 3.x --passphrase). Keyboard: arrows move through header buttons and
// rows, Enter activates.
Item {
    id: body
    required property var root
    required property var nav
    width: parent ? parent.width : 0

    signal close()

    implicitHeight: col.implicitHeight + 8

    Component.onCompleted: {
        if (body.nav) body.nav.refreshWifi();
        if (body.nav && body.nav.wifiConnectResult)
            body.nav.wifiConnectResult.connect(body._onWifiResult);
    }

    // 0 = RADIO toggle, 1 = SCAN, 2..N+1 = network rows.
    property int kbdIndex: 2
    readonly property int _headerCount: 2
    readonly property var _visibleNets: body.nav && body.nav.wifiRadioOn
                                        ? body.nav.wifiNetworks.slice(0, 8)
                                        : []
    readonly property int _kbdMax: _headerCount + _visibleNets.length

    // SSID whose row is replaced by a passphrase field; "" = none.
    property string passphraseSsid: ""
    property string passphraseText: ""
    property string statusText: ""

    function _isProtected(sec) { return !!sec && sec !== "open"; }

    function kbdHandle(event) {
        const k = event.key;
        if (body.passphraseSsid !== "") {
            // The focused TextInput eats real keys; swallow the rest so the
            // tile grid can't move under the field. Esc cancels the field.
            if (k === Qt.Key_Escape) body._cancelPassphrase();
            return true;
        }
        const n = body._kbdMax;
        if (n === 0) return false;
        if (k === Qt.Key_Up) {
            body.kbdIndex = Math.max(0, body.kbdIndex - 1);
            return true;
        }
        if (k === Qt.Key_Down || k === Qt.Key_Tab) {
            body.kbdIndex = Math.min(n - 1, body.kbdIndex + 1);
            return true;
        }
        if (k === Qt.Key_Left) {
            body.kbdIndex = Math.max(0, body.kbdIndex - 1);
            return true;
        }
        if (k === Qt.Key_Right) {
            body.kbdIndex = Math.min(n - 1, body.kbdIndex + 1);
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            body._activateAt(body.kbdIndex);
            return true;
        }
        if (k === Qt.Key_T) {
            const net = body._visibleNets[body.kbdIndex - body._headerCount];
            if (net && net.known && body.nav) body.nav.wifiToggleAutoConnect(net.ssid);
            return true;
        }
        if (k === Qt.Key_S) {
            if (body.nav) body.nav.refreshWifi();
            return true;
        }
        return false;
    }

    function _activateAt(i) {
        body.kbdIndex = i;
        if (body.passphraseSsid !== "" || (body.nav && body.nav.wifiBusy)) return;
        if (i === 0) { if (body.nav) body.nav.toggleWifiRadio(); return; }
        if (i === 1) { if (body.nav) body.nav.refreshWifi(); return; }
        const net = body._visibleNets[i - body._headerCount];
        if (!net || !body.nav) return;
        if (net.inUse) { body.nav.disconnectWifi(); return; }
        if (!net.known && body._isProtected(net.security)) { body._openPassphrase(net.ssid); return; }
        body.nav.wifiConnect(net.ssid);
    }

    function _openPassphrase(ssid) {
        body.passphraseSsid = ssid;
        body.passphraseText = "";
        body.statusText = "";
    }
    function _submitPassphrase() {
        const ssid = body.passphraseSsid;
        const pw = body.passphraseText;
        body.passphraseSsid = "";
        body.passphraseText = "";
        if (body.nav) body.nav.wifiConnect(ssid, pw);
    }
    function _cancelPassphrase() {
        body.passphraseSsid = "";
        body.passphraseText = "";
        body.statusText = "";
    }
    function _onWifiResult(ssid, ok) {
        if (ok) { body.statusText = ""; return; }
        body.statusText = "CONNECT FAILED";
        const net = body._visibleNets.find(n => n && n.ssid === ssid);
        if (net && body._isProtected(net.security)) body._openPassphrase(ssid);
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 6
        spacing: 10

        // Header: state + radio toggle + scan
        Item {
            width: parent.width
            height: 28

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: body.statusText !== ""
                      ? body.statusText
                      : (body.nav && body.nav.wifiBusy) ? "CONNECTING…"
                      : body.nav && body.nav.wifiRadioOn
                        ? (body.nav.wifiScanning ? "SCANNING…"
                           : (body.nav.wifiNetworks.length + " NETWORKS"))
                        : "RADIO OFF"
                color: body.statusText !== "" ? body.root.warn : body.root.inkDeep
                font.family: body.root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                QuickButton {
                    root: body.root
                    label: body.nav && body.nav.wifiRadioOn ? "RADIO OFF" : "RADIO ON"
                    selected: body.kbdIndex === 0
                    onClicked: if (body.nav && !body.nav.wifiBusy) body.nav.toggleWifiRadio()
                }
                QuickButton {
                    root: body.root
                    glyph: body.nav ? body.nav.icoRefresh : ""
                    label: "SCAN"
                    selected: body.kbdIndex === 1
                    onClicked: if (body.nav && !body.nav.wifiBusy) body.nav.refreshWifi()
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: body.root.sep }

        Repeater {
            id: netRepeater
            model: body._visibleNets
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool kbdFocused: body.kbdIndex === (index + body._headerCount)
                readonly property bool isPassRow: body.passphraseSsid === modelData.ssid
                readonly property bool dimmed: !modelData.known && !modelData.inUse
                width: col.width
                height: isPassRow ? 56 : 32
                radius: body.root.cornerRadius
                color: isPassRow
                       ? body.root.rowHi
                       : modelData.inUse || kbdFocused
                         ? body.root.rowSel
                         : netMouse.containsMouse
                           ? body.root.rowHi
                           : "transparent"
                border.color: modelData.inUse || kbdFocused || isPassRow ? body.root.seal : body.root.sep
                border.width: kbdFocused || isPassRow ? 2 : 1
                Behavior on color        { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }
                Behavior on border.width { NumberAnimation { duration: 120 } }

                // Normal row content; dims for networks iwd hasn't saved yet.
                Item {
                    anchors.fill: parent
                    visible: !isPassRow
                    opacity: dimmed ? 0.55 : 1

                    Text {
                        id: barsIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: body.nav.wifiBarsGlyph(modelData.signal)
                        color: modelData.inUse ? body.root.seal : body.root.ink
                        font.family: body.root.mono
                        font.pixelSize: 14
                    }
                    Text {
                        anchors.left: barsIcon.right
                        anchors.right: secTag.left
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.ssid
                        elide: Text.ElideRight
                        color: modelData.inUse ? body.root.ink : body.root.fg
                        font.family: body.root.mono
                        font.pixelSize: 11
                        font.weight: modelData.inUse ? Font.Medium : Font.Normal
                    }
                    Text {
                        id: secTag
                        anchors.right: sigText.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: body._isProtected(modelData.security) ? "󰌾" : ""
                        color: body.root.inkDeep
                        font.family: body.root.mono
                        font.pixelSize: 11
                    }
                    Text {
                        id: sigText
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.signal + "%"
                        color: body.root.inkDeep
                        font.family: body.root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }
                }

                // Passphrase field replaces the row for unknown protected nets.
                Column {
                    id: passCol
                    visible: isPassRow
                    onVisibleChanged: if (passCol.visible) passInput.forceActiveFocus()
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Text {
                        text: "ENTER PASSPHRASE · " + modelData.ssid
                        color: body.root.inkDeep
                        font.family: body.root.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }
                    Rectangle {
                        id: passField
                        width: parent.width
                        height: 20
                        radius: body.root.cornerRadius
                        color: Qt.rgba(body.root.ink.r, body.root.ink.g, body.root.ink.b, 0.05)
                        border.color: body.root.seal
                        border.width: 1
                        clip: true

                        TextInput {
                            id: passInput
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            focus: isPassRow
                            text: isPassRow ? body.passphraseText : ""
                            echoMode: TextInput.Password
                            inputMethodHints: Qt.ImhHiddenText
                            color: body.root.fg
                            font.family: body.root.mono
                            font.pixelSize: 11
                            selectByMouse: true
                            onTextChanged: if (body.passphraseSsid !== "") body.passphraseText = passInput.text
                            Keys.onReturnPressed: (event) => { body._submitPassphrase(); event.accepted = true; }
                            Keys.onEnterPressed:  (event) => { body._submitPassphrase(); event.accepted = true; }
                            Keys.onEscapePressed: (event) => { body._cancelPassphrase(); event.accepted = true; }
                        }
                    }
                }

                MouseArea {
                    id: netMouse
                    anchors.fill: parent
                    visible: !isPassRow
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        if (body.passphraseSsid !== "" || (body.nav && body.nav.wifiBusy)) return;
                        if (mouse.button === Qt.RightButton) {
                            if (modelData.known && !modelData.inUse && body.nav)
                                body.nav.forgetWifi(modelData.ssid);
                            return;
                        }
                        body._activateAt(index + body._headerCount);
                    }
                }
            }
        }

        Text {
            visible: body.nav && body.nav.wifiRadioOn && body.nav.wifiNetworks.length === 0 && !body.nav.wifiScanning
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "NO NETWORKS FOUND"
            color: body.root.inkDeep
            font.family: body.root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
            opacity: 0.6
        }
    }
}
