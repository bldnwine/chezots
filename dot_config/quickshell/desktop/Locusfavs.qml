import QtQuick
import Quickshell

CardWindow {
    id: popup
    required property var root

    theme: root
    revealed: root.locusfavsVisible
    cardWidth: 175
    layerNamespace: "omarchy-locusfavs"
    title: "QUICK NAV"

    onDismiss: popup.root.locusfavsVisible = false

    property int kbdIndex: 0
    property string searchQuery: ""

    onRevealedChanged: if (!revealed) popup.searchQuery = ""

    readonly property var folders: [
        { name: "Documents", path: "~/Docs" },
        { name: "Projects",  path: "~/Projects" },
        { name: "Videos",    path: "~/Videos" },
        { name: "Pictures",  path: "~/Pictures" },
        { name: "Music",     path: "~/Music" },
        { name: "Downloads", path: "~/Downloads" },
        { name: "sr",        path: "~/Videos/sr" },
        { name: "ss",        path: "~/Pictures/ss" },
        { name: ".config",   path: "~/.config" },
        { name: ".local",    path: "~/.local" },
    ]

    readonly property var filteredFolders: {
        const q = popup.searchQuery.toLowerCase();
        return q.length === 0
            ? popup.folders
            : popup.folders.filter(f => f.name.toLowerCase().includes(q));
    }

    onFilteredFoldersChanged: {
        if (popup.kbdIndex >= popup.filteredFolders.length)
            popup.kbdIndex = Math.max(0, popup.filteredFolders.length - 1);
    }

    subtitle: popup.searchQuery.length > 0
        ? "SEARCH: " + popup.searchQuery : ""

    onKeyPressed: function(event) {
        const k = event.key;
        const t = event.text;
        if (k === Qt.Key_Escape || k === Qt.Key_Q) {
            if (popup.searchQuery.length > 0)
                popup.searchQuery = "";
            else
                popup.root.locusfavsVisible = false;
        } else if (k === Qt.Key_Backspace) {
            popup.searchQuery = popup.searchQuery.slice(0, -1);
        } else if (k === Qt.Key_Up || k === Qt.Key_K) {
            popup.kbdIndex = Math.max(0, popup.kbdIndex - 1);
        } else if (k === Qt.Key_Down || k === Qt.Key_J) {
            popup.kbdIndex = Math.min(popup.filteredFolders.length - 1, popup.kbdIndex + 1);
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            const f = popup.filteredFolders[popup.kbdIndex];
            if (f) (event.modifiers & Qt.AltModifier) ? popup.openNemo(f) : popup.openYazi(f);
        } else if (t.length === 1 && t.charCodeAt(0) >= 32) {
            popup.searchQuery += t;
        } else { return; }
        event.accepted = true;
    }

    function openYazi(f) {
        popup.root.run("ghostty -e yazi " + f.path);
        popup.root.locusfavsVisible = false;
    }
    function openNemo(f) {
        popup.root.run("nemo " + f.path);
        popup.root.locusfavsVisible = false;
    }

    Column {
        width: parent.width
        spacing: 6
        padding: 4

        Repeater {
            model: popup.filteredFolders

            delegate: QuickButton {
                required property var modelData
                required property int index
                root: popup.root
                label: modelData.name
                selected: popup.kbdIndex === index
                onClicked: popup.openYazi(modelData)
                onRightClicked: popup.openNemo(modelData)
            }
        }
    }
}
