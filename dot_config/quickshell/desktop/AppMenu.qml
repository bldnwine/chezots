import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Item {
    id: root

    required property var navbar

    readonly property color bg:      navbar.bg
    readonly property color ink:     navbar.ink
    readonly property color inkDeep: navbar.inkDeep
    readonly property color seal:    navbar.seal
    readonly property color sep:     navbar.sep
    readonly property color rowHi:   navbar.rowHi
    readonly property color rowSel:  navbar.rowSel
    readonly property string mono:   navbar.mono
    readonly property int cornerRadius: navbar.cornerRadius

    property string query: ""
    property int selectedIndex: 0

    AppScan { id: appScan }

    readonly property var filteredApps: {
        const q = root.query.trim().toLowerCase();
        const apps = appScan.apps;
        if (q.length === 0) return apps;
        return apps.filter(a => a._t.includes(q) || a._k.includes(q));
    }

    onFilteredAppsChanged: {
        if (root.selectedIndex >= root.filteredApps.length)
            root.selectedIndex = Math.max(0, root.filteredApps.length - 1);
    }
    onSelectedIndexChanged: {
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }

    function close() { navbar.appMenuVisible = false; }

    function launch(item) {
        if (!item) return;
        const cmd = item.tui ? item.tui + " " + item.exec : item.exec;
        navbar.run("setsid -f uwsm-app -- bash -c " + JSON.stringify(cmd) + " >/dev/null 2>&1");
        root.close();
    }

    PanelWindow {
        id: panel
        visible: navbar.appMenuVisible || _reveal > 0.001
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "appmenu"
        WlrLayershell.keyboardFocus: navbar.appMenuVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        property real _reveal: navbar.appMenuVisible ? 1 : 0

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.5 * panel._reveal)
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.18
            width: 640
            height: Math.min(parent.height * 0.72, bodyCol.implicitHeight + 20)
            color: root.bg
            border.color: root.sep
            border.width: 1
            radius: root.cornerRadius
            transformOrigin: Item.Center
            scale: panel._reveal

            MouseArea { anchors.fill: parent }

            focus: navbar.appMenuVisible
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    if (root.query.length > 0) { root.query = ""; root.selectedIndex = 0; }
                    else root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backspace) {
                    root.query = root.query.slice(0, -1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                    root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                    root.selectedIndex = Math.min(root.filteredApps.length - 1, root.selectedIndex + 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    const it = root.filteredApps[root.selectedIndex];
                    root.launch(it);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Home) {
                    root.selectedIndex = 0;
                    event.accepted = true;
                } else if (event.key === Qt.Key_End) {
                    root.selectedIndex = Math.max(0, root.filteredApps.length - 1);
                    event.accepted = true;
                } else if (event.text && event.text.length === 1) {
                    const ch = event.text;
                    if (ch.charCodeAt(0) >= 32 && ch.charCodeAt(0) !== 127) {
                        root.query += ch;
                        root.selectedIndex = 0;
                        event.accepted = true;
                    }
                }
            }

            Column {
                id: bodyCol
                anchors.fill: parent
                anchors.margins: 0
                spacing: 0

                Item { width: 1; height: 10 }

                // Search row
                Item {
                    width: parent.width
                    height: 34

                    Text {
                        id: searchPrompt
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰍉"
                        color: root.seal
                        font.family: root.mono
                        font.pixelSize: 16
                    }

                    Text {
                        id: queryText
                        anchors.left: searchPrompt.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.query.length > 0 ? root.query : "Type to search apps…"
                        color: root.query.length === 0 ? root.inkDeep : root.ink
                        opacity: root.query.length === 0 ? 0.5 : 1.0
                        font.family: root.mono
                        font.pixelSize: 14
                        font.letterSpacing: 1
                    }

                    Rectangle {
                        width: 2
                        height: 16
                        color: root.seal
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.query.length === 0
                           ? searchPrompt.x + searchPrompt.width + 10
                           : queryText.x + queryText.contentWidth + 2
                        visible: navbar.appMenuVisible
                        SequentialAnimation on opacity {
                            running: navbar.appMenuVisible
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.2; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.2; to: 1; duration: 600; easing.type: Easing.InOutSine }
                        }
                    }
                }

                Item { width: 1; height: 8 }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: root.sep
                }

                // Result list
                ListView {
                    id: resultList
                    clip: true
                    width: parent.width
                    height: Math.min(root.filteredApps.length * 38, Math.max(60, card.height - 55))
                    model: root.filteredApps
                    currentIndex: root.selectedIndex
                    highlightFollowsCurrentItem: false
                    boundsBehavior: Flickable.StopAtBounds
                    pixelAligned: true

                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 38

                        readonly property bool isSelected: root.selectedIndex === index

                        Rectangle {
                            anchors.fill: parent
                            color: isSelected ? root.rowSel
                                              : mouse.containsMouse ? root.rowHi
                                                                     : "transparent"
                            Behavior on color { ColorAnimation { duration: 40 } }
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 2
                            color: root.seal
                            visible: isSelected
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedIndex = index;
                                root.launch(modelData);
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.title
                            color: isSelected ? root.seal : root.ink
                            font.family: root.mono
                            font.pixelSize: 14
                            font.letterSpacing: 1
                            font.weight: isSelected ? Font.Medium : Font.Normal
                            elide: Text.ElideRight
                            width: parent.width - 40
                        }
                    }
                }

            }
        }
    }
}
