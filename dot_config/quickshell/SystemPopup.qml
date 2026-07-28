import QtQuick

CardWindow {
    id: systemPopup
    required property var root

    theme: root
    plain: true
    revealed: root.systemVisible
    cardWidth: 320
    layerNamespace: "omarchy-system"
    title: "SYSTEM"
    subtitle: "CPU " + Math.round(root.cpuVal) + "% - MEM " + Math.round(root.memVal) + "%"
    footer: "B OPEN BTOP - ESC"

    anchorEdge: systemPopup.root.systemAnchorItem ? systemPopup.root.barEdge : ""
    anchorBarX: systemPopup.root.popupAnchorX
    anchorBarY: systemPopup.root.popupAnchorY

    function openBtop() {
        systemPopup.root.run("omarchy-launch-or-focus-tui btop");
        systemPopup.root.systemVisible = false;
    }

    onDismiss: systemPopup.root.systemVisible = false
    onKeyPressed: function(event) {
        if (event.key === Qt.Key_Q) {
            systemPopup.root.systemVisible = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_B) {
            systemPopup.openBtop();
            event.accepted = true;
        }
    }

    Column {
        width: parent.width
        spacing: 10

        Repeater {
            model: [
                { label: "CPU", value: Math.round(systemPopup.root.cpuVal) },
                { label: "MEM", value: Math.round(systemPopup.root.memVal) }
            ]

            delegate: Item {
                required property var modelData
                width: parent.width
                height: 32

                Text {
                    id: lineLabel
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: modelData.label
                    color: systemPopup.root.inkDeep
                    font.family: systemPopup.root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }

                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: modelData.value + "%"
                    color: systemPopup.root.ink
                    font.family: systemPopup.root.mono
                    font.pixelSize: 11
                    font.letterSpacing: 1
                    font.weight: Font.Medium
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 22
                    height: 3
                    color: Qt.rgba(systemPopup.root.ink.r, systemPopup.root.ink.g, systemPopup.root.ink.b, 0.14)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * Math.max(0, Math.min(1, modelData.value / 100))
                        color: systemPopup.root.ink
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: systemPopup.root.sep }

        Item {
            width: parent.width
            height: 30

            Rectangle {
                anchors.fill: parent
                color: actionMouse.containsMouse
                       ? Qt.rgba(systemPopup.root.ink.r, systemPopup.root.ink.g, systemPopup.root.ink.b, 0.06)
                       : "transparent"
                border.width: 1
                border.color: actionMouse.containsMouse ? systemPopup.root.ink : systemPopup.root.sep
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: "OPEN BTOP"
                color: systemPopup.root.ink
                font.family: systemPopup.root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
                font.weight: Font.Medium
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: "DETAIL PROCESS VIEW"
                color: systemPopup.root.inkDeep
                font.family: systemPopup.root.mono
                font.pixelSize: 10
                font.letterSpacing: 1.2
            }

            MouseArea {
                id: actionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: systemPopup.openBtop()
            }
        }
    }
}
