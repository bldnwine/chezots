import QtQuick
import QtQuick.Layouts

CardWindow {
    id: warppopup
    required property var root

    theme: root
    plain: true
    revealed: root.warpVisible
    cardWidth: 420
    layerNamespace: "omarchy-warp"
    title: "CLOUDFLARE WARP"

    readonly property var warp: warppopup.root.warpService

    subtitle: {
        if (!warp || !warp.probed) return "CHECKING…";
        if (warp.daemonDown) return "DAEMON INACTIVE";
        if (warp.active) {
            var modeStr = warp.mode ? warp.modeLabel(warp.mode) : "WARP";
            return "CONNECTED · " + modeStr.toUpperCase() + (warp.accountLabel !== "" ? " · " + warp.accountLabel.toUpperCase() : "");
        }
        if (warp.connecting) return "CONNECTING…";
        return "DISCONNECTED" + (warp.accountLabel !== "" ? " · " + warp.accountLabel.toUpperCase() : "");
    }

    footer: "T TOGGLE · D DAEMON · M MODES · S SPLIT · C COPY ID · R REFRESH"

    anchorEdge: warppopup.root.barEdge
    anchorBarX: warppopup.root.popupAnchorX
    anchorBarY: warppopup.root.popupAnchorY

    property string focusSection: "header"
    property int modeIndex: 0
    property int splitIndex: 0
    property bool splitExpanded: false

    readonly property var modeRows: warp ? warp.modeRows : []
    readonly property var splitRows: splitExpanded && warp ? warp.splitTunnelEntries : []

    function copyText(val, msg) {
        if (!val) return;
        warppopup.root.run("printf %s " + JSON.stringify(String(val)) + " | wl-copy");
        if (warp) warp.flash(msg || "Copied to clipboard");
    }

    function toggleSplit() {
        warppopup.splitExpanded = !warppopup.splitExpanded;
        warppopup.splitIndex = 0;
    }

    function kbdHandle(event) {
        const k = event.key;
        if (k === Qt.Key_Escape) {
            warppopup.root.warpVisible = false;
            return true;
        }
        if (k === Qt.Key_T) {
            if (warp && warp.canToggle) warp.toggleConnection();
            return true;
        }
        if (k === Qt.Key_D) {
            if (warp) {
                if (warp.daemonDown) warp.startDaemon();
                else warp.stopDaemon();
            }
            return true;
        }
        if (k === Qt.Key_R) {
            if (warp) warp.refresh();
            return true;
        }
        if (k === Qt.Key_C) {
            if (warp && warp.deviceId) copyText(warp.deviceId, "Copied Device ID");
            return true;
        }
        if (k === Qt.Key_S) {
            toggleSplit();
            return true;
        }
        if (k === Qt.Key_M) {
            warppopup.focusSection = "modes";
            warppopup.modeIndex = 0;
            return true;
        }
        if (k === Qt.Key_Up || k === Qt.Key_K) {
            moveFocus(-1);
            return true;
        }
        if (k === Qt.Key_Down || k === Qt.Key_J || k === Qt.Key_Tab) {
            moveFocus(1);
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            activateFocus();
            return true;
        }
        return false;
    }

    function moveFocus(delta) {
        if (focusSection === "header") {
            if (delta > 0) {
                if (modeRows.length > 0) { focusSection = "modes"; modeIndex = 0; }
                else if (splitRows.length > 0) { focusSection = "split"; splitIndex = 0; }
            }
        } else if (focusSection === "modes") {
            var nextMode = modeIndex + delta;
            if (nextMode < 0) {
                focusSection = "header";
            } else if (nextMode >= modeRows.length) {
                if (warp && warp.splitTunnelEntries.length > 0) {
                    focusSection = "split";
                    splitIndex = 0;
                }
            } else {
                modeIndex = nextMode;
            }
        } else if (focusSection === "split") {
            var nextSplit = splitIndex + delta;
            if (nextSplit < 0) {
                if (modeRows.length > 0) {
                    focusSection = "modes";
                    modeIndex = modeRows.length - 1;
                } else {
                    focusSection = "header";
                }
            } else if (nextSplit <= splitRows.length) {
                splitIndex = nextSplit;
            }
        }
    }

    function activateFocus() {
        if (focusSection === "header") {
            if (warp) {
                if (warp.daemonDown) warp.startDaemon();
                else if (warp.needsRegistration) warp.register();
                else warp.toggleConnection();
            }
        } else if (focusSection === "modes") {
            var m = modeRows[modeIndex];
            if (m && warp) warp.setMode(m.id);
        } else if (focusSection === "split") {
            if (splitIndex === 0) {
                toggleSplit();
            } else {
                var entry = splitRows[splitIndex - 1];
                if (entry) copyText(entry.value, "Copied " + entry.value);
            }
        }
    }

    Component.onCompleted: {
        if (warp) warp.refresh();
    }

    onDismiss: warppopup.root.warpVisible = false
    onKeyPressed: (event) => {
        if (warppopup.kbdHandle(event)) event.accepted = true;
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        // Status & Attention Banner (Start Daemon / Needs TOS / Register)
        Rectangle {
            visible: warp && (warp.daemonDown || warp.needsRegistration || warp.needsTos || warp.actionStatus !== "" || warp.lastError !== "")
            width: col.width
            height: bannerCol.implicitHeight + 12
            radius: root.cornerRadius
            color: warp && warp.lastError !== "" ? Qt.rgba(root.warn.r, root.warn.g, root.warn.b, 0.12)
                   : warp && warp.daemonDown ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
                   : Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.10)
            border.color: warp && warp.lastError !== "" ? root.warn : root.seal
            border.width: 1

            Column {
                id: bannerCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 8
                spacing: 6

                RowLayout {
                    width: parent.width
                    Text {
                        text: warp && warp.daemonDown ? "󰑓  WARP daemon is inactive"
                              : warp && warp.needsTos ? "󰗠  Terms of Service acceptance needed"
                              : warp && warp.needsRegistration ? "󰌆  Device registration needed"
                              : warp && warp.lastError !== "" ? ("󰅚  " + warp.lastError)
                              : ("󰑓  " + warp.actionStatus)
                        color: warp && warp.lastError !== "" ? root.warn : root.ink
                        font.family: root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    QuickButton {
                        root: warppopup.root
                        visible: warp && (warp.daemonDown || warp.needsRegistration || warp.needsTos)
                        label: warp && warp.daemonDown ? "START DAEMON"
                               : warp && warp.needsRegistration ? "REGISTER"
                               : "ACCEPT"
                        selected: warppopup.focusSection === "header"
                        onClicked: {
                            if (warp.daemonDown) warp.startDaemon();
                            else if (warp.needsRegistration) warp.register();
                            else warp.refresh();
                        }
                    }
                }
            }
        }

        // Hero Row: Icon + Account/Status + Toggle Button
        Rectangle {
            width: col.width
            height: 48
            radius: root.cornerRadius
            color: warppopup.focusSection === "header" && !warp.daemonDown ? root.rowSel : root.rowHi
            border.color: warppopup.focusSection === "header" && !warp.daemonDown ? root.seal : root.sep
            border.width: warppopup.focusSection === "header" && !warp.daemonDown ? 2 : 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                WarpIcon {
                    iconSize: 22
                    color: warp && warp.active ? root.seal : root.inkDeep
                    badgeColor: root.warn
                    crossed: warp && !warp.active && !warp.daemonDown
                    warning: warp && (warp.daemonDown || warp.needsRegistration)
                    Layout.alignment: Qt.AlignVCenter
                }

                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1

                    Text {
                        text: warp && warp.accountLabel !== "" ? warp.accountLabel : "Cloudflare WARP"
                        color: root.ink
                        font.family: root.mono
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        font.letterSpacing: 1.5
                        elide: Text.ElideRight
                    }

                    Text {
                        text: warp && warp.active ? ("Tunneling traffic via " + (warp.modeLabel(warp.mode) || "WARP"))
                              : warp && warp.connecting ? "Establishing connection…"
                              : warp && warp.daemonDown ? "Daemon is not running"
                              : warp.statusText
                        color: warp && warp.active ? root.seal : root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1
                        elide: Text.ElideRight
                    }
                }

                QuickButton {
                    root: warppopup.root
                    label: warp && warp.active ? "DISCONNECT" : "CONNECT"
                    selected: warppopup.focusSection === "header" && !warp.daemonDown
                    onClicked: {
                        if (warp) {
                            if (warp.daemonDown) warp.startDaemon();
                            else warp.toggleConnection();
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    warppopup.focusSection = "header";
                    if (warp) {
                        if (warp.daemonDown) warp.startDaemon();
                        else warp.toggleConnection();
                    }
                }
            }
        }

        // Live Telemetry Grid
        Column {
            visible: warp && !warp.daemonDown
            width: col.width
            spacing: 4

            readonly property var detailRows: [
                { l: "STATUS",    v: warp ? warp.statusText : "—", copy: false },
                { l: "MODE",      v: warp ? warp.modeLabel(warp.mode) : "—", copy: false },
                { l: "LATENCY",   v: (warp && warp.tunnelStats && warp.tunnelStats.latency) ? warp.tunnelStats.latency : "—", copy: false },
                { l: "ENDPOINT",  v: (warp && warp.tunnelStats && warp.tunnelStats.endpoint) ? warp.tunnelStats.endpoint : "—", copy: false },
                { l: "TRANSFER",  v: (warp && warp.tunnelStats && warp.tunnelStats.ok)
                                     ? ("↑ " + (warp.tunnelStats.sent || "0 B") + "   ↓ " + (warp.tunnelStats.received || "0 B")) : "—", copy: false },
                { l: "DEVICE ID", v: (warp && warp.deviceId) ? warp.deviceId : "—", copy: true }
            ]

            Repeater {
                model: parent.detailRows
                delegate: Item {
                    required property var modelData
                    width: col.width
                    height: 18
                    visible: modelData.v !== "" && modelData.v !== "—"

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.l
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1.5
                        opacity: 0.75
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.v
                        color: modelData.copy && devIdMouse.containsMouse ? root.seal : root.ink
                        font.family: root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: devIdMouse
                        anchors.fill: parent
                        visible: modelData.copy
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: warppopup.copyText(modelData.v, "Copied " + modelData.l)
                    }
                }
            }
        }

        // Operating Mode Selector
        Rectangle { width: col.width; height: 1; color: root.sep; visible: warp && !warp.daemonDown }

        Column {
            visible: warp && !warp.daemonDown
            width: col.width
            spacing: 6

            Text {
                text: "OPERATING MODE"
                color: root.inkDeep
                font.family: root.mono
                font.pixelSize: 9
                font.letterSpacing: 2
                font.weight: Font.Medium
            }

            Column {
                width: col.width
                spacing: 3

                Repeater {
                    model: warppopup.modeRows
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: modelData.current === true
                        readonly property bool isFocused: warppopup.focusSection === "modes" && warppopup.modeIndex === index
                        readonly property bool isSwitching: warp && warp.settingMode === String(modelData.id || "")

                        width: col.width
                        height: 34
                        radius: root.cornerRadius
                        color: isCurrent || isFocused ? root.rowSel : modeMouse.containsMouse ? root.rowHi : "transparent"
                        border.color: isCurrent || isFocused ? root.seal : root.sep
                        border.width: isFocused ? 2 : 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: isCurrent ? "󰄲" : (modelData.tunnel ? "󰖂" : "󰇖")
                                color: isCurrent ? root.seal : root.inkDeep
                                font.family: root.mono
                                font.pixelSize: 12
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Column {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 1

                                Text {
                                    text: modelData.label + (modelData.id === "tunnel_only" ? " (Quad9 DNS)" : "")
                                    color: isCurrent ? root.ink : root.fg
                                    font.family: root.mono
                                    font.pixelSize: 10
                                    font.weight: isCurrent ? Font.Medium : Font.Normal
                                    font.letterSpacing: 1
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: modelData.description
                                    color: root.inkDeep
                                    font.family: root.mono
                                    font.pixelSize: 8
                                    font.letterSpacing: 0.8
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                visible: isCurrent || isSwitching
                                text: isSwitching ? "SWITCHING…" : "ACTIVE"
                                color: root.seal
                                font.family: root.mono
                                font.pixelSize: 8
                                font.letterSpacing: 1.5
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            id: modeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                warppopup.focusSection = "modes";
                                warppopup.modeIndex = index;
                                if (warp) warp.setMode(modelData.id);
                            }
                        }
                    }
                }
            }
        }

        // Split Tunnel Section
        Rectangle {
            width: col.width
            height: 1
            color: root.sep
            visible: warp && !warp.daemonDown && warp.splitTunnelEntries.length > 0
        }

        Column {
            visible: warp && !warp.daemonDown && warp.splitTunnelEntries.length > 0
            width: col.width
            spacing: 4

            Rectangle {
                width: col.width
                height: 28
                radius: root.cornerRadius
                color: warppopup.focusSection === "split" && warppopup.splitIndex === 0 ? root.rowSel : splitMouse.containsMouse ? root.rowHi : "transparent"
                border.color: warppopup.focusSection === "split" && warppopup.splitIndex === 0 ? root.seal : root.sep
                border.width: warppopup.focusSection === "split" && warppopup.splitIndex === 0 ? 2 : 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8

                    Text {
                        text: warppopup.splitExpanded ? "󰅀" : "󰅂"
                        color: root.ink
                        font.family: root.mono
                        font.pixelSize: 11
                    }

                    Text {
                        text: warp.splitTunnelSummary !== "" ? warp.splitTunnelSummary.toUpperCase() : "SPLIT TUNNEL"
                        color: root.ink
                        font.family: root.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1.5
                        Layout.fillWidth: true
                    }

                    Text {
                        text: warppopup.splitExpanded ? "COLLAPSE" : "INSPECT"
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 8
                        font.letterSpacing: 1
                    }
                }

                MouseArea {
                    id: splitMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        warppopup.focusSection = "split";
                        warppopup.splitIndex = 0;
                        warppopup.toggleSplit();
                    }
                }
            }

            Column {
                visible: warppopup.splitExpanded
                width: col.width
                spacing: 2

                Repeater {
                    model: warppopup.splitRows
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool isFocused: warppopup.focusSection === "split" && warppopup.splitIndex === index + 1
                        width: col.width
                        height: 24
                        radius: root.cornerRadius
                        color: isFocused ? root.rowSel : itemMouse.containsMouse ? root.rowHi : "transparent"
                        border.color: isFocused ? root.seal : root.sep
                        border.width: isFocused ? 2 : 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8

                            Text {
                                text: modelData.kind === "host" ? "󰇆" : "󰩟"
                                color: root.inkDeep
                                font.family: root.mono
                                font.pixelSize: 10
                            }

                            Text {
                                text: modelData.value
                                color: root.fg
                                font.family: root.mono
                                font.pixelSize: 9
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: modelData.description || (modelData.kind === "host" ? "HOST" : "IP")
                                color: root.inkDeep
                                font.family: root.mono
                                font.pixelSize: 8
                            }
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                warppopup.focusSection = "split";
                                warppopup.splitIndex = index + 1;
                                warppopup.copyText(modelData.value, "Copied " + modelData.value);
                            }
                        }
                    }
                }
            }
        }

        // Daemon Stop Action (when daemon is running and disconnected)
        RowLayout {
            visible: warp && !warp.daemonDown && !warp.active
            width: col.width

            Item { Layout.fillWidth: true }

            QuickButton {
                root: warppopup.root
                label: "STOP DAEMON"
                onClicked: if (warp) warp.stopDaemon()
            }
        }
    }
}
