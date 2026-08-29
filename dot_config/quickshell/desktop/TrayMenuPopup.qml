import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: trayMenu
    required property var root

    visible: root.trayMenuVisible
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-tray-menu"

    QsMenuOpener {
        id: menuOpener
        menu: root.activeTrayItem ? root.activeTrayItem.menu : null
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.trayMenuVisible = false
    }

    Rectangle {
        id: menuCard
        width: Math.max(160, Math.min(280, menuCol.implicitWidth + 24))
        height: menuCol.implicitHeight + 16
        radius: root.cornerRadius
        color: root.bg
        border.color: root.sep
        border.width: 1

        x: {
            const rawX = root.popupAnchorX - width / 2;
            return Math.max(8, Math.min(parent.width - width - 8, rawX));
        }
        y: {
            if (root.barEdge === "top") return root.barOffset + 6;
            if (root.barEdge === "bottom") return parent.height - root.barOffset - height - 6;
            const rawY = root.popupAnchorY - height / 2;
            return Math.max(8, Math.min(parent.height - height - 8, rawY));
        }

        // Swallow clicks inside the card
        MouseArea { anchors.fill: parent }

        Column {
            id: menuCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            Repeater {
                model: menuOpener.children

                delegate: Item {
                    id: menuRow
                    required property var modelData
                    required property int index

                    readonly property string rowText: String(modelData.text || "")
                    readonly property bool isSep: modelData.isSeparator
                    readonly property bool isItemEnabled: modelData.enabled

                    width: menuCol.width
                    implicitHeight: isSep ? 7 : 26

                    Rectangle {
                        visible: menuRow.isSep
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: menuRow.modelData ? root.sep : "transparent"
                    }

                    Rectangle {
                        visible: !menuRow.isSep
                        anchors.fill: parent
                        radius: Math.max(2, root.cornerRadius - 2)
                        color: itemMouse.containsMouse && menuRow.isItemEnabled
                               ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
                               : "transparent"
                    }

                    Row {
                        visible: !menuRow.isSep
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 6
                        opacity: menuRow.isItemEnabled ? 1.0 : 0.4

                        Text {
                            visible: menuRow.modelData.buttonType !== QsMenuButtonType.None
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            horizontalAlignment: Text.AlignHCenter
                            text: menuRow.modelData.checkState === Qt.Checked ? "✓" : ""
                            color: root.ink
                            font.family: root.mono
                            font.pixelSize: 10
                        }

                        IconImage {
                            id: itemIcon
                            visible: String(menuRow.modelData.icon || "") !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 14
                            width: 14
                            height: 14
                            source: menuRow.modelData.icon || ""
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: menuRow.width - (itemIcon.visible ? 20 : 0) - (menuRow.modelData.hasChildren ? 20 : 0) - (menuRow.modelData.buttonType !== QsMenuButtonType.None ? 20 : 0) - 16
                            text: menuRow.rowText
                            color: root.ink
                            font.family: root.mono
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            visible: menuRow.modelData.hasChildren
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"
                            color: root.inkDeep
                            font.family: root.mono
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !menuRow.isSep && menuRow.isItemEnabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (menuRow.modelData.hasChildren) {
                                const point = menuRow.QsWindow.contentItem.mapFromItem(menuRow, menuRow.width, menuRow.height / 2);
                                menuRow.modelData.display(menuRow.QsWindow.window, point.x, point.y);
                            } else {
                                menuRow.modelData.triggered();
                                root.trayMenuVisible = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
