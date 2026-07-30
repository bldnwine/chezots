import QtQuick
import Quickshell

CardWindow {
    id: popup
    required property var root

    theme: root
    revealed: root.hyprlandVisible
    cardWidth: 170
    layerNamespace: "omarchy-hyprland"
    title: "HYPRLAND"
    subtitle: "LAYOUT"

    onDismiss: popup.root.hyprlandVisible = false

    onKeyPressed: function(event) {
        const k = event.key;
        if (k === Qt.Key_Escape || k === Qt.Key_Q) {
            popup.root.hyprlandVisible = false;
        } else if (k === Qt.Key_1) { setLayout("scrolling"); }
        else if (k === Qt.Key_2) { setLayout("dwindle"); }
        else if (k === Qt.Key_3) { setLayout("master"); }
        else if (k === Qt.Key_4) { setLayout("monocle"); }
        else if (k === Qt.Key_E) { editConfig(); }
        else { return; }
        event.accepted = true;
    }

    function setLayout(name) {
        popup.root.run("hyprctl eval \"hl.config({ general = { layout = '" + name + "' } })\"");
    }

    function editConfig() {
        popup.root.run("ghostty -e nvim ~/.config/hypr/hyprland.lua");
        popup.root.hyprlandVisible = false;
    }

    Column {
        width: parent.width
        spacing: 8
        padding: 4

        Grid {
            width: parent.width
            columns: 1
            rowSpacing: 6
            columnSpacing: 6

            Repeater {
                model: ["scrolling", "dwindle", "master", "monocle"]
                delegate: QuickButton {
                    required property string modelData
                    root: popup.root
                    label: modelData.toUpperCase()
                    selected: popup.root.hyprlandLayout === modelData
                    onClicked: popup.setLayout(modelData)
                }
            }
        }

        Separator { root: popup.root }

        QuickButton {
            root: popup.root
            label: "EDIT CONFIG"
            onClicked: popup.editConfig()
        }
    }
}
