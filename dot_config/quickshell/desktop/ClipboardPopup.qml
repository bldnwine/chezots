import QtQuick
import Quickshell
import "ClipboardHistory.js" as ClipboardHistory

// Clipboard manager popup. Always-on capture lives in Navbar (wl-paste
// watchers + history file); this card is a lazy-loaded viewer/editor over
// root.clipboardHistory. Enter re-copies the selected entry, Alt+Enter
// opens it, typing filters history-as-you-type.
CardWindow {
    id: popup
    required property var root

    theme: root
    plain: true
    revealed: root.clipboardVisible
    cardWidth: 880
    layerNamespace: "omarchy-clipboard"
    title: "CLIPBOARD"
    subtitle: root.clipboardHistory.length + " ENTRIES" + (popup.filterText ? " · “" + popup.filterText + "”" : "")
    footer: "↵ COPY · ALT+↵ OPEN · DEL REMOVE · SHIFT+DEL CLEAR"
    escDismiss: false

    readonly property string copyScript:  Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/clipboard-copy"
    readonly property string openScript:  Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/clipboard-open"

    property string filterText: ""
    property int selectedIndex: 0
    property bool cursorActive: true
    property bool pointerArmed: false

    ListModel { id: displayModel }

    Component.onCompleted: {
        popup.filterText = "";
        popup.selectedIndex = 0;
        popup.disarmPointer();
        popup.rebuildDisplay();
        armTimer.restart();
    }

    Connections {
        target: root
        function onClipboardHistoryChanged() {
            if (popup.revealed) popup.rebuildDisplay();
        }
    }

    function rebuildDisplay() {
        const rows = ClipboardHistory.displayRows(root.clipboardHistory, popup.filterText, 50);
        displayModel.clear();
        for (let i = 0; i < rows.length; i++) {
            const row = rows[i];
            displayModel.append({
                entryType: row.entryType,
                fullText: row.fullText,
                previewText: row.previewText,
                previewImage: row.previewImage ? "file://" + row.previewImage : "",
                path: row.path,
                mime: row.mime,
                historyIndex: row.index
            });
        }
        if (displayModel.count === 0) popup.selectedIndex = 0;
        else if (popup.selectedIndex >= displayModel.count) popup.selectedIndex = displayModel.count - 1;
        else if (popup.selectedIndex < 0) popup.selectedIndex = 0;
        Qt.callLater(function() {
            if (displayModel.count > 0) resultList.positionViewAtIndex(popup.selectedIndex, ListView.Contain);
        });
    }

    function select(delta) {
        if (displayModel.count === 0) return;
        popup.disarmPointer();
        if (!popup.cursorActive) {
            popup.cursorActive = true;
            popup.selectedIndex = delta < 0 ? displayModel.count - 1 : 0;
        } else {
            popup.selectedIndex = (popup.selectedIndex + delta + displayModel.count) % displayModel.count;
        }
        resultList.positionViewAtIndex(popup.selectedIndex, ListView.Contain);
    }

    function selectAbsolute(index) {
        if (displayModel.count === 0) return;
        popup.disarmPointer();
        popup.cursorActive = true;
        popup.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1));
        resultList.positionViewAtIndex(popup.selectedIndex, ListView.Contain);
    }

    function setFilter(next) {
        popup.filterText = next;
        popup.selectedIndex = 0;
        popup.cursorActive = true;
        popup.disarmPointer();
        popup.rebuildDisplay();
    }

    function disarmPointer() {
        popup.pointerArmed = false;
        armTimer.restart();
    }

    function selectFromPointer(index, mouse) {
        if (!popup.pointerArmed) return;
        popup.cursorActive = true;
        popup.selectedIndex = index;
    }

    function activate(index) {
        if (index < 0 || index >= displayModel.count) return;
        popup.copyRow(displayModel.get(index));
    }

    function copyRow(row) {
        if (!row) return;
        popup.root.clipboardVisible = false;
        Quickshell.execDetached([popup.copyScript, String(row.historyIndex)]);
    }

    function openRow(row) {
        if (!row) return;
        popup.root.clipboardVisible = false;
        Quickshell.execDetached([popup.openScript, String(row.historyIndex)]);
    }

    function removeIndex(index) {
        if (index < 0 || index >= displayModel.count) return;
        const row = displayModel.get(index);
        root.clipboardRemoveAt(row.historyIndex);
        if (displayModel.count <= 1) {
            popup.selectedIndex = 0;
            popup.cursorActive = false;
        } else if (popup.selectedIndex >= displayModel.count - 1) {
            popup.selectedIndex = displayModel.count - 2;
        }
        popup.disarmPointer();
        popup.rebuildDisplay();
    }

    function clearAll() {
        root.clipboardClearAll();
        popup.selectedIndex = 0;
        popup.cursorActive = false;
        popup.disarmPointer();
        popup.rebuildDisplay();
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            if (popup.filterText) popup.setFilter("");
            else popup.root.clipboardVisible = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            if (popup.filterText.length > 0) popup.setFilter(popup.filterText.slice(0, -1));
            event.accepted = true;
        } else if (event.key === Qt.Key_Delete) {
            if (event.modifiers & Qt.ShiftModifier) popup.clearAll();
            else popup.removeIndex(popup.selectedIndex);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            popup.select(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            popup.select(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageUp) {
            popup.select(-6);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageDown) {
            popup.select(6);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home) {
            popup.selectAbsolute(0);
            event.accepted = true;
        } else if (event.key === Qt.Key_End) {
            popup.selectAbsolute(displayModel.count - 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (popup.cursorActive && (event.modifiers & Qt.AltModifier)) popup.openRow(displayModel.get(popup.selectedIndex));
            else if (popup.cursorActive) popup.activate(popup.selectedIndex);
            else popup.cursorActive = true;
            event.accepted = true;
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            popup.setFilter(popup.filterText + event.text);
            event.accepted = true;
        }
    }

    onRevealedChanged: if (popup.revealed) {
        popup.selectedIndex = 0;
        popup.cursorActive = true;
        popup.disarmPointer();
        popup.rebuildDisplay();
    }

    onDismiss: root.clipboardVisible = false
    onKeyPressed: (event) => popup.handleKey(event)

    Timer { id: armTimer; interval: 350; onTriggered: popup.pointerArmed = true }

    Item {
        width: parent.width
        height: 440

        Row {
            anchors.fill: parent
            spacing: 0

            Item {
                width: parent.width / 2
                height: parent.height
                clip: true

                ListView {
                    id: resultList
                    anchors.fill: parent
                    anchors.rightMargin: 8
                    model: displayModel
                    clip: true
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: row
                        required property int index
                        required property string entryType
                        required property string previewText
                        required property string fullText
                        required property string previewImage

                        readonly property bool hasCursor: popup.cursorActive && index === popup.selectedIndex

                        width: ListView.view.width
                        height: 48
                        radius: root.cornerRadius
                        color: hasCursor ? root.rowSel : "transparent"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.topMargin: 7
                            anchors.bottomMargin: 7
                            spacing: 10

                            Image {
                                visible: parent.parent.previewImage.length > 0
                                width: visible ? parent.height : 0
                                height: parent.height
                                source: parent.parent.previewImage
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                            }

                            Text {
                                width: parent.width - (parent.parent.previewImage.length > 0 ? parent.height + parent.spacing : 0)
                                height: parent.height
                                text: parent.parent.previewText
                                color: parent.parent.hasCursor ? root.ink : root.fg
                                font.family: root.mono
                                font.pixelSize: 13
                                opacity: parent.parent.entryType === "image" || parent.parent.entryType === "file" ? 0.72 : 1.0
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: (mouse) => popup.selectFromPointer(index, mouse)
                            onClicked: {
                                popup.cursorActive = true;
                                popup.selectedIndex = index;
                                popup.activate(index);
                            }
                        }
                    }
                }
            }

            Item {
                width: parent.width / 2
                height: parent.height
                clip: true

                property var activeRow: displayModel.count > 0 && popup.selectedIndex >= 0 && popup.selectedIndex < displayModel.count ? displayModel.get(popup.selectedIndex) : null

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: Qt.rgba(root.sep.r, root.sep.g, root.sep.b, 0.6)
                }

                Text {
                    visible: parent.activeRow && !parent.activeRow.previewImage
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.topMargin: 2
                    text: parent.activeRow ? parent.activeRow.fullText : ""
                    color: root.inkDeep
                    font.family: root.mono
                    font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignTop
                }

                Image {
                    visible: parent.activeRow && parent.activeRow.previewImage
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.topMargin: 2
                    source: parent.activeRow ? parent.activeRow.previewImage : ""
                    fillMode: Image.PreserveAspectFit
                    verticalAlignment: Image.AlignTop
                    asynchronous: true
                    smooth: true
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8
            visible: displayModel.count === 0

            Text {
                text: "󰅌"
                color: root.rowSel
                font.family: root.mono
                font.pixelSize: 44
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }

            Text {
                text: root.clipboardHistory.length === 0 ? "Clipboard is empty" : "No matches for “" + popup.filterText + "”"
                color: root.inkDeep
                opacity: 0.7
                font.family: root.mono
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
            }
        }
    }
}
