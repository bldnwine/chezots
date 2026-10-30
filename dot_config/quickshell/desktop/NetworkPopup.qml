import QtQuick
import QtQuick.Controls

// The view owns input and scrolling; the persistent service owns iwd actions.
CardWindow {
    id: netpopup
    required property var root

    theme: root
    plain: true
    revealed: root.networkVisible
    escDismiss: netpopup.passphraseSsid === ""
    cardWidth: Math.max(1, Math.min(390, width - 2 * anchorGap))
    cardHeight: Math.min(700, availableCardHeight)
    readonly property real availableCardHeight: Math.max(1,
        height - ((anchorEdge === "top" || anchorEdge === "bottom") ? root.barOffset : 0) - 2 * anchorGap)
    layerNamespace: "omarchy-network"
    title: "NETWORK"
    subtitle: {
        if (root.netKind === "eth" && root.wifiSsid)
            return "ETHERNET · " + root.wifiSsid + " · " + root.wifiSignal + "%";
        return root.netKind === "eth" ? "ETHERNET"
             : root.netKind === "wifi" ? ((root.wifiSsid || "(hidden)") + " · " + root.wifiSignal + "%")
             : "OFFLINE";
    }
    footer: "T AUTOCONNECT · S SCAN · U FORGET"

    anchorEdge: netpopup.root.barEdge
    anchorBarX: netpopup.root.popupAnchorX
    anchorBarY: netpopup.root.popupAnchorY

    // 0 = RADIO toggle, 1 = SCAN, 2..N+1 = network rows.
    property int kbdIndex: 2
    property string kbdSsid: ""
    readonly property int headerCount: 2
    property var visibleNets: root.wifiRadioOn
                              ? root.wifiNetworks
                              : []
    readonly property int kbdMax: headerCount + visibleNets.length + (retrySsid !== "" ? 1 : 0)

    // Re-home the selection cursor whenever the network list changes
    onVisibleNetsChanged: netpopup.rehome()

    // Keep kbdSsid in sync whenever the keyboard cursor moves
    onKbdIndexChanged: {
        netpopup.syncSsid();
        Qt.callLater(netpopup.ensureSelectionVisible);
    }

    function syncSsid() {
        const n = netpopup.visibleNets[netpopup.kbdIndex - netpopup.headerCount];
        netpopup.kbdSsid = n ? n.ssid : "";
    }

    function rehome() {
        const index = netpopup.visibleNets.findIndex(n => n.ssid === netpopup.kbdSsid);
        netpopup.kbdIndex = index >= 0 ? index + netpopup.headerCount
            : Math.max(0, Math.min(netpopup.kbdIndex, netpopup.headerCount + netpopup.visibleNets.length - 1));
        netpopup.syncSsid();
        Qt.callLater(netpopup.ensureSelectionVisible);
    }
    function ensureSelectionVisible() {
        if (netpopup.passphraseSsid !== "") {
            bodyScroll.showItem(passInput);
            return;
        }
        const index = netpopup.kbdIndex - netpopup.headerCount;
        if (index >= 0 && index < netpopup.visibleNets.length) {
            Qt.callLater(function() {
                networkList.forceLayout();
                const row = networkList.itemAtIndex(index);
                if (row) bodyScroll.showItem(row);
            });
        } else if (netpopup.retrySsid && netpopup.kbdIndex === netpopup.kbdMax - 1) {
            bodyScroll.showItem(retryButton);
        } else bodyScroll.contentY = 0;
    }

    property string passphraseSsid: ""
    property string passphraseText: ""
    property string retrySsid: ""
    property string statusText: ""

    function _isProtected(sec) { return !!sec && sec !== "open"; }
    function _isPasswordBased(sec) { return /psk|wpa|sae/i.test(sec || ""); }

    function kbdHandle(event) {
        const k = event.key;
        if (netpopup.passphraseSsid !== "") {
            if (k === Qt.Key_Escape) netpopup._cancelPassphrase();
            return true;
        }
        const n = netpopup.kbdMax;
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
            const net = netpopup.visibleNets[netpopup.kbdIndex - netpopup.headerCount];
            if (net && net.known) root.wifiToggleAutoConnect(net.ssid);
            return true;
        }
        if (k === Qt.Key_S) {
            root.refreshWifi("popup");
            return true;
        }
        if (k === Qt.Key_U) {
            const net = netpopup.visibleNets[netpopup.kbdIndex - netpopup.headerCount];
            if (net && net.known && !net.inUse) root.forgetWifi(net.ssid);
            return true;
        }
        return false;
    }

    function _activateAt(i) {
        netpopup.kbdIndex = i;
        if (netpopup.passphraseSsid !== "" || root.wifiBusy) return;
        if (i === 0) { root.toggleWifiRadio(); return; }
        if (i === 1) { root.refreshWifi("popup"); return; }
        if (netpopup.retrySsid && i === netpopup.kbdMax - 1) {
            netpopup._openPassphrase(netpopup.retrySsid);
            return;
        }
        const net = netpopup.visibleNets[i - netpopup.headerCount];
        if (!net) return;
        if (net.inUse) { root.disconnectWifi(); return; }
        netpopup.statusText = "";
        netpopup.retrySsid = "";
        if (!net.known && netpopup._isPasswordBased(net.security))
            netpopup._openPassphrase(net.ssid);
        else root.wifiConnect(net.ssid);
    }

    function _openPassphrase(ssid) {
        netpopup.passphraseSsid = ssid;
        netpopup.passphraseText = "";
        netpopup.statusText = "";
        bodyScroll.contentY = 0;
        passInput.text = "";
        passInput.forceActiveFocus();
        Qt.callLater(function() {
            if (netpopup.revealed && netpopup.passphraseSsid) {
                bodyScroll.showItem(passInput);
                passInput.forceActiveFocus();
            }
        });
    }
    function _submitPassphrase() {
        if (!netpopup.passphraseSsid || root.wifiBusy) return;
        const ssid = netpopup.passphraseSsid;
        const pw = netpopup.passphraseText;
        netpopup.passphraseSsid = "";
        netpopup.passphraseText = "";
        passInput.text = "";
        netpopup.retrySsid = ssid;
        root.wifiConnect(ssid, pw);
    }
    function _cancelPassphrase() {
        netpopup.passphraseSsid = "";
        netpopup.passphraseText = "";
        passInput.text = "";
        passInput.focus = false;
        if (netpopup.revealed) netpopup.refocus();
        netpopup.statusText = "";
    }
    function _onWifiResult(ssid, ok) {
        if (!netpopup.revealed) return;
        netpopup.retrySsid = "";
        if (ok) { netpopup.statusText = ""; return; }
        netpopup.statusText = root.wifiError || "CONNECT FAILED";
        const net = netpopup.visibleNets.find(n => n.ssid === ssid);
        if (net && netpopup._isPasswordBased(net.security)
            && ["auth", "command"].indexOf(root.wifiErrorKind) >= 0)
            netpopup.retrySsid = ssid;
    }

    function _copy(value) { root.copyNetworkText(String(value)); }

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

    // Restore navigation focus after the stable password editor is hidden.
    onPassphraseSsidChanged: {
        if (netpopup.passphraseSsid === "") {
            Qt.callLater(function() { if (netpopup.revealed) netpopup.refocus(); });
        }
    }

    // The Navbar/service starts a fresh scan on every reveal, including reuse.
    onRevealedChanged: {
        if (!revealed) {
            netpopup._cancelPassphrase();
            netpopup.retrySsid = "";
            netpopup.statusText = "";
            netpopup.kbdIndex = 0;
            netpopup.kbdSsid = "";
            bodyScroll.contentY = 0;
        }
    }

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

    component NetworkScrollBar: ScrollBar {
        policy: ScrollBar.AsNeeded
        visible: size < 1
        minimumSize: 0.08
        implicitWidth: 5
        padding: 0
        contentItem: Rectangle { implicitWidth: 5; implicitHeight: 20; radius: 2; color: netpopup.root.seal }
        background: Rectangle { radius: 2; color: netpopup.root.sep }
    }
    Item {
        width: parent.width
        height: netpopup.bodyAvailableHeight

        Flickable {
            id: bodyScroll
            width: parent.width
            height: Math.max(0, parent.height - (statsScroll.visible ? statsScroll.height + 10 : 0))
            contentWidth: width
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            ScrollBar.vertical: NetworkScrollBar {
                parent: bodyScroll.parent
                anchors.top: bodyScroll.top
                anchors.bottom: bodyScroll.bottom
                anchors.left: bodyScroll.right
                anchors.leftMargin: 4
            }
            function showItem(item) {
                const top = item.mapToItem(col, 0, 0).y;
                const bottom = top + item.height;
                if (top < contentY) contentY = top;
                else if (bottom > contentY + height) contentY = Math.max(0, bottom - height);
            }
            onContentHeightChanged: contentY = Math.max(0, Math.min(contentY, contentHeight - height))
            onHeightChanged: Qt.callLater(netpopup.ensureSelectionVisible)
            Column {
                id: col
                width: parent.width
                spacing: 10

                Item {
                    width: parent.width
                    height: 28
                    Text {
                        id: statusLine
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, wifiActions.x - 12)
                        elide: Text.ElideRight
                        text: root.wifiBusy ? root.wifiActionText
                              : netpopup.statusText !== ""
                              ? netpopup.statusText
                              : root.wifiError ? root.wifiError
                              : root.wifiRadioOn
                                ? (root.wifiScanning ? "SCANNING…"
                                   : (root.wifiNetworks.length + " NETWORKS"))
                                : "RADIO OFF"
                        color: !root.wifiBusy && (netpopup.statusText || root.wifiError) ? root.warn : root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }
                    Row {
                        id: wifiActions
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
                            label: root.wifiScanning ? "SCANNING…" : "SCAN"
                            selected: netpopup.kbdIndex === 1
                            onClicked: if (!root.wifiBusy) root.refreshWifi("popup")
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: root.sep }

                Column {
                    width: parent.width
                    visible: netpopup.passphraseSsid !== ""
                    spacing: 6
                    Text {
                        width: parent.width
                        text: "PASSPHRASE · " + netpopup.passphraseSsid
                        elide: Text.ElideRight
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 10
                    }
                    Rectangle {
                        width: parent.width
                        height: 30
                        radius: root.cornerRadius
                        color: root.rowHi
                        border.color: root.seal
                        clip: true
                        TextInput {
                            id: passInput
                            anchors.fill: parent
                            anchors.margins: 6
                            echoMode: TextInput.Password
                            inputMethodHints: Qt.ImhHiddenText | Qt.ImhNoPredictiveText
                            color: root.fg
                            font.family: root.mono
                            font.pixelSize: 12
                            selectByMouse: true
                            onTextChanged: netpopup.passphraseText = text
                            Keys.onReturnPressed: (event) => { netpopup._submitPassphrase(); event.accepted = true; }
                            Keys.onEnterPressed: (event) => { netpopup._submitPassphrase(); event.accepted = true; }
                            Keys.onEscapePressed: (event) => { netpopup._cancelPassphrase(); event.accepted = true; }
                        }
                    }
                }
                QuickButton {
                    id: retryButton
                    root: netpopup.root
                    visible: netpopup.retrySsid !== "" && netpopup.passphraseSsid === "" && !root.wifiBusy
                    label: "RETRY WITH PASSWORD"
                    selected: netpopup.kbdIndex === netpopup.kbdMax - 1
                    onClicked: if (!root.wifiBusy) netpopup._openPassphrase(netpopup.retrySsid)
                }

                ListView {
                    id: networkList
                    width: col.width
                    height: contentHeight
                    clip: true
                    spacing: 10
                    interactive: false
                    onContentHeightChanged: Qt.callLater(netpopup.ensureSelectionVisible)
                    model: netpopup.visibleNets
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool kbdFocused: netpopup.kbdIndex === (index + netpopup.headerCount)
                        readonly property bool dimmed: !modelData.known && !modelData.inUse
                        width: networkList.width
                        height: 32
                        radius: root.cornerRadius
                        color: modelData.inUse || kbdFocused
                                 ? root.rowSel
                                 : netMouse.containsMouse
                                   ? root.rowHi
                                   : "transparent"
                        border.color: modelData.inUse || kbdFocused ? root.seal : root.sep
                        border.width: kbdFocused ? 2 : 1
                        Behavior on color        { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        Behavior on border.width { NumberAnimation { duration: 120 } }

                        // Normal row content; dims for networks iwd hasn't saved yet.
                        Item {
                            anchors.fill: parent
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

                        MouseArea {
                            id: netMouse
                            anchors.fill: parent
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
                                netpopup._activateAt(index + netpopup.headerCount);
                            }
                        }
                    }
                }

                Text {
                    visible: root.wifiRadioOn && netpopup.visibleNets.length === 0 && root.wifiScanning
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "SCANNING FOR NETWORKS…"
                    color: root.inkDeep
                    font.family: root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                    opacity: 0.6
                }

                Text {
                    visible: root.wifiRadioOn && netpopup.visibleNets.length === 0 && !root.wifiScanning
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "NO NETWORKS FOUND"
                    color: root.inkDeep
                    font.family: root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                    opacity: 0.6
                }
            }
        }

        // Connection stats stay at the bottom while networks scroll above them.
        // On short screens the stats can also scroll, preserving room for controls.
        Flickable {
            id: statsScroll
            anchors.bottom: parent.bottom
            width: parent.width
            visible: !!root.netInfo.iface || !!root.netDetailsError
            height: visible ? Math.min(statsColumn.implicitHeight,
                Math.max(0, parent.height - Math.min(100, parent.height / 2) - 10)) : 0
            contentWidth: width
            contentHeight: statsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            onContentHeightChanged: contentY = Math.max(0, Math.min(contentY, Math.max(0, contentHeight - height)))
            ScrollBar.vertical: NetworkScrollBar {
                parent: statsScroll.parent
                anchors.top: statsScroll.top
                anchors.bottom: statsScroll.bottom
                anchors.left: statsScroll.right
                anchors.leftMargin: 4
            }
            Column {
                id: statsColumn
                width: parent.width
                spacing: 10
                Text {
                    width: parent.width
                    visible: !!root.netDetailsError
                    text: root.netDetailsError
                    wrapMode: Text.WordWrap
                    color: root.warn
                    font.family: root.mono
                    font.pixelSize: 10
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
                                                          && (root.netPacketLoss > 0 || _val === "TIMEOUT")
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
    }
}
