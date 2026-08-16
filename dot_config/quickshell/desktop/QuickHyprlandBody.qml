import QtQuick

Item {
    id: body
    required property var root
    required property var nav
    width: parent ? parent.width : 0

    signal close()

    implicitHeight: col.implicitHeight + 8

    function setLayout(name) {
        body.nav.run("hyprctl eval \"hl.config({ general = { layout = '" + name + "' } })\"");
    }

    function editConfig() {
        body.nav.runTerminal("nvim ~/.config/hypr/hyprland.lua");
        body.close();
    }

    property int kbdIndex: 0
    readonly property int _kbdMax: 5

    function kbdHandle(event) {
        const k = event.key;
        if (k === Qt.Key_Down || k === Qt.Key_J) {
            body.kbdIndex = Math.min(body._kbdMax - 1, body.kbdIndex + 1);
            return true;
        }
        if (k === Qt.Key_Up || k === Qt.Key_K) {
            body.kbdIndex = Math.max(0, body.kbdIndex - 1);
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            if (body.kbdIndex < 4) body.setLayout(["scrolling","dwindle","master","monocle"][body.kbdIndex]);
            else if (body.kbdIndex === 4) body.editConfig();
            return true;
        }
        return false;
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 6
        spacing: 6

        Repeater {
            model: ["scrolling", "dwindle", "master", "monocle"]
            delegate: QuickButton {
                required property string modelData
                required property int index
                root: body.root
                label: modelData.toUpperCase()
                selected: body.nav.hyprlandLayout === modelData
                onClicked: body.setLayout(modelData)
            }
        }

        Separator { root: body.root }

        QuickButton {
            root: body.root
            label: "EDIT CONFIG"
            onClicked: body.editConfig()
        }
    }
}
