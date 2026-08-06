import QtQuick

// Network popup — Wi-Fi list (same iwd backend as QuickWifiBody) plus a
// live connection-details grid. Details are ported from omarchy's network
// panel: ping latency + packet loss (rolling sample window), rx/tx rates
// (byte deltas between ~1.5s samples), cumulative downloaded/uploaded, and
// the interface IP + gateway (click to copy). Backed by Navbar's
// netDetailsProbe, polled while this popup is open.
CardWindow {
    id: netpopup
    required property var root

    theme: root
    plain: true
    revealed: root.networkVisible
    cardWidth: 390
    layerNamespace: "omarchy-network"
    title: "NETWORK"
    subtitle: {
        if (root.netKind === "eth") return "ETHERNET";
        if (root.netKind === "wifi")
            return (root.wifiSsid || "(hidden)") + " · " + root.wifiSignal + "%";
        return "OFFLINE";
    }
    footer: "T AUTOCONNECT · S SCAN · U FORGET · ESC CLOSE"

    anchorEdge: netpopup.root.barEdge
    anchorBarX: netpopup.root.popupAnchorX
    anchorBarY: netpopup.root.popupAnchorY

    // 0 = RADIO toggle, 1 = SCAN, 2..N+1 = network rows.
    property int kbdIndex: 2
    readonly property int _headerCount: 2
    readonly property var _visibleNets: root.wifiRadioOn
                                        ? root.wifiNetworks.slice(0, 8)
                                        : []
    readonly property int _kbdMax: _headerCount + _visibleNets.length

    property string passphraseSsid: ""
    property string passphraseText: ""
    property string statusText: ""

    function _isProtected(sec) { return !!sec && sec !== "open"; }

    function kbdHandle(event) {
        const k = event.key;
        if (netpopup.passphraseSsid !== "") return true;
        const n = netpopup._kbdMax;
        if (n === 0) return false;
        if (k === Qt.Key_Up || k === Qt.Key_Left) {
            netpopup.kbdIndex = Math.max(0, netpopup.kbdIndex - 1);
            return true;
        }
        if (k === Qt.Key_Down || k === Qt.Key_Right || k === Qt.Key_Tab) {
            netpopup.kbdIndex = Math.min(n - 1, netpopup.kbdIndex + 1);
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            netpopup._activateAt(netpopup.kbdIndex);
            return true;
        }
        if (k === Qt.Key_T) {
            const net = netpopup._visibleNets[netpopup.kbdIndex - netpopup._headerCount];
            if (net && net.known) root.wifiToggleAutoConnect(net.ssid);
            return true;
        }
        if (k === Qt.Key_S) {
            root.refreshWifi();
            return true;
        }
        if (k === Qt.Key_U) {
            const net = netpopup._visibleNets[netpopup.kbdIndex - netpopup._headerCount];
            if (net && net.known && !net.inUse) root.forgetWifi(net.ssid);
            return true;
        }
        return false;
    }

    function _activateAt(i) {
        netpopup.kbdIndex = i;
        if (netpopup.passphraseSsid !== "" || root.wifiBusy) return;
        if (i === 0) { root.toggleWifiRadio(); return; }
        if (i === 1) { root.refreshWifi(); return; }
        const net = netpopup._visibleNets[i - netpopup._headerCount];
        if (!net) return;
        if (net.inUse) { root.disconnectWifi(); return; }
        root.wifiConnect(net.ssid);
    }

    function _openPassphrase(ssid) {
        netpopup.passphraseSsid = ssid;
        netpopup.passphraseText = "";
        netpopup.statusText = "";
    }
    function _submitPassphrase() {
        const ssid = netpopup.passphraseSsid;
        const pw = netpopup.passphraseText;
        netpopup.passphraseSsid = "";
        netpopup.passphraseText = "";
        root.wifiConnect(ssid, pw);
    }
    function _cancelPassphrase() {
        netpopup.passphraseSsid = "";
        netpopup.passphraseText = "";
        netpopup.statusText = "";
    }
    function _onWifiResult(ssid, ok) {
        if (ok) { netpopup.statusText = ""; return; }
        netpopup.statusText = "CONNECT FAILED";
        const net = netpopup._visibleNets.find(n => n && n.ssid === ssid);
        if (net && !net.known && netpopup._isProtected(net.security)) netpopup._openPassphrase(ssid);
    }

    function _copy(value) {
        root.run("printf %s " + JSON.stringify(String(value)) + " | wl-copy");
    }

    readonly property var _detailRows: [
        { l: "PING",        kind: "ping",   copy: false },
        { l: "PACKET LOSS", kind: "loss",   copy: false },
        { l: "RECEIVING",   kind: "rxrate", copy: false },
        { l: "SENDING",     kind: "txrate", copy: false },
        { l: "DOWNLOADED",  kind: "rx",     copy: false },
        { l: "UPLOADED",    kind: "tx",     copy: false },
        { l: "IP",          kind: "ip",     copy: true },
        { l: "GATEWAY",     kind: "gw",     copy: true }
    ]

    // Hand focus back to the card surface after the passphrase field closes
    // (Esc cancel or Enter submit) so arrow/t/s nav resumes. Deferred until
    // the field is actually destroyed.
    onPassphraseSsidChanged: {
        if (netpopup.passphraseSsid === "") {
            Qt.callLater(function() { netpopup.refocus(); });
        }
    }

    Component.onCompleted: root.refreshWifi()

    // Connections (not connect()) so the emit is dropped once the Loader
    // destroys this popup — a manual connect survives and calls a dead
    // instance's method, throwing on the netpopup root id.
    Connections {
        target: root
        function onWifiConnectResult(ssid, ok) { netpopup._onWifiResult(ssid, ok); }
    }

    onDismiss: root.networkVisible = false
    onKeyPressed: (event) => {
        if (netpopup.kbdHandle(event)) event.accepted = true;
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
                text: netpopup.statusText !== ""
                      ? netpopup.statusText
                      : root.wifiBusy ? "CONNECTING…"
                      : root.wifiRadioOn
                        ? (root.wifiScanning ? "SCANNING…"
                           : (root.wifiNetworks.length + " NETWORKS"))
                        : "RADIO OFF"
                color: netpopup.statusText !== "" ? root.warn : root.inkDeep
                font.family: root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                QuickButton {
                    root: netpopup.root
                    label: root.wifiRadioOn ? "RADIO OFF" : "RADIO ON"
                    selected: netpopup.kbdIndex === 0
                    onClicked: if (!root.wifiBusy) root.toggleWifiRadio()
                }
                QuickButton {
                    root: netpopup.root
                    glyph: root.icoRefresh
                    label: "SCAN"
                    selected: netpopup.kbdIndex === 1
                    onClicked: if (!root.wifiBusy) root.refreshWifi()
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: root.sep }

        Repeater {
            id: netRepeater
            model: netpopup._visibleNets
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool kbdFocused: netpopup.kbdIndex === (index + netpopup._headerCount)
                readonly property bool isPassRow: netpopup.passphraseSsid === modelData.ssid
                readonly property bool dimmed: !modelData.known && !modelData.inUse
                width: col.width
                height: isPassRow ? 56 : 32
                radius: root.cornerRadius
                color: isPassRow
                       ? root.rowHi
                       : modelData.inUse || kbdFocused
                         ? root.rowSel
                         : netMouse.containsMouse
                           ? root.rowHi
                           : "transparent"
                border.color: modelData.inUse || kbdFocused || isPassRow ? root.seal : root.sep
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
                        text: root.wifiBarsGlyph(modelData.signal)
                        color: modelData.inUse ? root.seal : root.ink
                        font.family: root.mono
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
                        color: modelData.inUse ? root.ink : root.fg
                        font.family: root.mono
                        font.pixelSize: 11
                        font.weight: modelData.inUse ? Font.Medium : Font.Normal
                    }
                    Text {
                        id: secTag
                        anchors.right: sigText.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: netpopup._isProtected(modelData.security) ? "󰌾" : ""
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 11
                    }
                    Text {
                        id: sigText
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.signal + "%"
                        color: root.inkDeep
                        font.family: root.mono
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
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }
                    Rectangle {
                        id: passField
                        width: parent.width
                        height: 20
                        radius: root.cornerRadius
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
                        border.color: root.seal
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
                            text: isPassRow ? netpopup.passphraseText : ""
                            echoMode: TextInput.Password
                            inputMethodHints: Qt.ImhHiddenText
                            color: root.fg
                            font.family: root.mono
                            font.pixelSize: 11
                            selectByMouse: true
                            onTextChanged: if (netpopup.passphraseSsid !== "") netpopup.passphraseText = passInput.text
                            Keys.onReturnPressed: (event) => { netpopup._submitPassphrase(); event.accepted = true; }
                            Keys.onEnterPressed:  (event) => { netpopup._submitPassphrase(); event.accepted = true; }
                            Keys.onEscapePressed: (event) => { netpopup._cancelPassphrase(); event.accepted = true; }
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
                        if (netpopup.passphraseSsid !== "" || root.wifiBusy) return;
                        if (mouse.button === Qt.RightButton) {
                            if (modelData.known && !modelData.inUse)
                                root.forgetWifi(modelData.ssid);
                            return;
                        }
                        netpopup._activateAt(index + netpopup._headerCount);
                    }
                }
            }
        }

        Text {
            visible: root.wifiRadioOn && root.wifiNetworks.length === 0 && !root.wifiScanning
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "NO NETWORKS FOUND"
            color: root.inkDeep
            font.family: root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
            opacity: 0.6
        }

        // ---------- Connection details ----------
        Rectangle {
            width: parent.width
            height: 1
            color: root.sep
            visible: !!root.netInfo.iface
        }
        Column {
            visible: !!root.netInfo.iface
            width: parent.width
            spacing: 4

            Repeater {
                model: netpopup._detailRows
                delegate: Item {
                    required property var modelData
                    readonly property string _val: {
                        switch (modelData.kind) {
                            case "ping":   return root.fmtPing(root.netInternetPing);
                            case "loss":   return root.fmtLoss(root.netPacketLoss);
                            case "rxrate": return root.fmtRate(root.netDownloadRate);
                            case "txrate": return root.fmtRate(root.netUploadRate);
                            case "rx":     return root.fmtBytes(root.netInfo.rx_bytes);
                            case "tx":     return root.fmtBytes(root.netInfo.tx_bytes);
                            case "ip":     return root.netInfo.ip || "—";
                            case "gw":     return root.netInfo.gateway || "—";
                        }
                        return "";
                    }
                    readonly property bool _warn: (modelData.kind === "ping"
                                                   || modelData.kind === "loss")
                                                  && root.netPacketLoss > 0
                    readonly property bool _copy: modelData.copy && _val !== "—"
                    width: parent.width
                    height: 20

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.l
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1.5
                        opacity: 0.7
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent._val
                        color: parent._warn ? root.warn : root.ink
                        font.family: root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        anchors.fill: parent
                        visible: parent._copy
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: netpopup._copy(parent._val)
                    }
                }
            }
        }
    }
}
