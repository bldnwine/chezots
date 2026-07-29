import QtQuick

CardWindow {
    id: popup
    required property var root

    theme: root
    revealed: root.wireprotonVisible
    cardWidth: 280
    layerNamespace: "omarchy-wireproton"
    title: "PROTON VPN"

    subtitle: root.wireprotonActiveIface.length > 0
        ? "CONNECTED · " + root.wireprotonActiveIface
        : "DISCONNECTED"

    onDismiss: popup.root.wireprotonVisible = false

    property int kbdIndex: 0
    readonly property int _kbdMax: root.wireprotonActiveIface.length > 0
        ? 1 : root.wireprotonConfigs.length

    onKeyPressed: function(event) {
        const k = event.key;
        if (k === Qt.Key_Escape || k === Qt.Key_Q) {
            popup.root.wireprotonVisible = false;
        } else if (k === Qt.Key_Up || k === Qt.Key_K) {
            popup.kbdIndex = Math.max(0, popup.kbdIndex - 1);
        } else if (k === Qt.Key_Down || k === Qt.Key_J) {
            popup.kbdIndex = Math.min(popup._kbdMax - 1, popup.kbdIndex + 1);
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            if (root.wireprotonActiveIface.length > 0)
                popup.disconnect();
            else if (root.wireprotonConfigs[popup.kbdIndex])
                popup.connect(root.wireprotonConfigs[popup.kbdIndex]);
        } else if (k === Qt.Key_E) {
            if (root.wireprotonActiveIface.length > 0) popup.disconnect();
        } else if (k >= Qt.Key_1 && k <= Qt.Key_9) {
            var idx = k - Qt.Key_1;
            if (root.wireprotonConfigs[idx]) popup.connect(root.wireprotonConfigs[idx]);
        } else { return; }
        event.accepted = true;
    }

    function connect(name) {
        var cmd = "sudo /usr/bin/wg-quick up " + name;
        if (root.wireprotonActiveIface.length > 0)
            cmd = "sudo /usr/bin/wg-quick down " + root.wireprotonActiveIface + " && " + cmd;
        popup.root.run(cmd);
        popup.root.wireprotonVisible = false;
    }

    function disconnect() {
        popup.root.run("sudo /usr/bin/wg-quick down " + root.wireprotonActiveIface);
        popup.root.wireprotonVisible = false;
    }

    Column {
        width: parent.width
        spacing: 8
        padding: 4

        QuickButton {
            root: popup.root
            visible: root.wireprotonActiveIface.length > 0
            label: "DISCONNECT (" + root.wireprotonActiveIface + ")"
            selected: popup.kbdIndex === 0
            onClicked: popup.disconnect()
        }

        Grid {
            width: parent.width
            columns: 1
            rowSpacing: 6
            columnSpacing: 6
            visible: root.wireprotonActiveIface.length === 0

            Repeater {
                model: root.wireprotonConfigs
                delegate: QuickButton {
                    required property string modelData
                    required property int index
                    root: popup.root
                    label: "CONNECT " + modelData
                    selected: popup.kbdIndex === index
                    onClicked: popup.connect(modelData)
                }
            }
        }
    }
}
