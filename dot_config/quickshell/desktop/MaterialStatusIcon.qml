import QtQuick
import QtQuick.Window

// Zen's AI and WARP badges, independent of the shared legacy icon types.
MaterialIcon {
    id: icon

    property string badge: "" // "working", "finished", "warning"
    property color badgeColor: "#c4746e"
    property color badgeInk: "#181616"
    readonly property bool hostVisible: visible && (!Window.window || Window.window.visible)

    Rectangle {
        visible: icon.badge === "working"
        width: Math.max(4, icon.size * 0.32)
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -1
        anchors.bottomMargin: -1
        color: icon.badgeColor

        SequentialAnimation on opacity {
            running: icon.hostVisible && icon.badge === "working"
            loops: Animation.Infinite
            NumberAnimation { from: 0.3; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 1.0; to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
        }
    }

    Rectangle {
        visible: icon.badge === "finished" || icon.badge === "warning"
        width: Math.max(8, icon.size * 0.58)
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -1
        anchors.bottomMargin: -1
        color: icon.badgeColor
        border.color: icon.badgeInk
        border.width: 1

        MaterialIcon {
            anchors.centerIn: parent
            name: icon.badge === "finished" ? "check" : "priority_high"
            filled: true
            size: parent.width - 2
            color: icon.badgeInk
        }
    }
}
