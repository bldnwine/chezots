import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

CardWindow {
    id: managePopup
    required property var root

    theme: root
    plain: true
    revealed: root.trayManageVisible
    cardWidth: 400
    layerNamespace: "omarchy-tray-manage"
    title: "SYSTEM TRAY"
    subtitle: {
        const count = root.trayAllItems ? root.trayAllItems.length : 0;
        return count === 1 ? "1 APP REPORTING" : count + " APPS REPORTING";
    }
    footer: "PIN STAYS VISIBLE · HIDE SUPPRESSES ICONS"

    anchorEdge: managePopup.root.trayAnchorItem ? managePopup.root.barEdge : ""
    anchorBarX: managePopup.root.popupAnchorX
    anchorBarY: managePopup.root.popupAnchorY

    onDismiss: managePopup.root.trayManageVisible = false
    onKeyPressed: function(event) {
        if (event.key === Qt.Key_Q || event.key === Qt.Key_Escape) {
            managePopup.root.trayManageVisible = false;
            event.accepted = true;
        }
    }

    Column {
        width: parent.width
        spacing: 8

        Text {
            visible: !root.trayAllItems || root.trayAllItems.length === 0
            width: parent.width
            text: "No system tray applications reporting."
            color: root.inkDeep
            font.family: root.mono
            font.pixelSize: 11
            font.letterSpacing: 1
            font.italic: true
            horizontalAlignment: Text.AlignHCenter
            topPadding: 12
            bottomPadding: 12
        }

        Repeater {
            model: root.trayAllItems || []

            delegate: Rectangle {
                id: rowRoot
                required property var modelData
                required property int index

                width: parent.width
                height: 36
                radius: root.cornerRadius
                color: rowMouse.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05) : "transparent"

                readonly property string itemId: String(modelData.id || "")
                readonly property string displayName: {
                    const t = String(modelData.title || "").trim();
                    if (t) return t;
                    const tt = String(modelData.tooltipTitle || "").trim();
                    if (tt) return tt;
                    const id = String(modelData.id || "");
                    const slash = id.lastIndexOf("/");
                    return slash !== -1 ? id.substring(slash + 1) : (id || "Unknown");
                }
                readonly property bool isPinned: root.trayPinnedIds.indexOf(itemId) !== -1
                readonly property bool isHidden: root.trayHiddenIds.indexOf(itemId) !== -1

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8
                    Layout.alignment: Qt.AlignVCenter

                    IconImage {
                        id: rowIcon
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 18
                        width: 18
                        height: 18
                        source: root.trayIconSource(rowRoot.modelData ? (rowRoot.modelData.icon || rowRoot.modelData.iconName) : "")
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: rowRoot.width - 200
                        text: rowRoot.displayName
                        color: root.ink
                        font.family: root.mono
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    Item { Layout.fillWidth: true }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        QuickButton {
                            root: managePopup.root
                            label: rowRoot.isPinned ? "PINNED" : "PIN"
                            selected: rowRoot.isPinned
                            padH: 8
                            onClicked: managePopup.root.toggleTrayPin(rowRoot.itemId)
                        }

                        QuickButton {
                            root: managePopup.root
                            label: rowRoot.isHidden ? "HIDDEN" : "HIDE"
                            selected: rowRoot.isHidden
                            padH: 8
                            onClicked: managePopup.root.toggleTrayHide(rowRoot.itemId)
                        }
                    }
                }
            }
        }
    }
}
