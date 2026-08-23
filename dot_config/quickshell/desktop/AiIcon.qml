import QtQuick

Item {
    id: root

    property real iconSize: 14
    property color color: "#c5c9c5"
    property color badgeColor: "#c4746e"
    property color successColor: "#87a987"
    property string state: "idle" // "working" | "finished" | "action_needed" | "idle"
    property string fontFamily: "IoskeleyMono Nerd Font"
    property int glyphYOffset: -1

    width: iconSize
    height: iconSize
    implicitWidth: iconSize
    implicitHeight: iconSize

    // Robot glyph from Nerd Font (󰚩 = U+F06A9)
    Text {
        id: robotGlyph
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.glyphYOffset
        text: "󰚩"
        color: root.color
        font.family: root.fontFamily
        font.pixelSize: root.iconSize
        antialiasing: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // Working pulse badge (small pulsing accent dot)
    Rectangle {
        id: workingBadge
        visible: root.state === "working"
        width: Math.max(4, root.iconSize * 0.32)
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -1
        anchors.bottomMargin: -1 + root.glyphYOffset
        color: root.successColor

        SequentialAnimation on opacity {
            running: root.state === "working"
            loops: Animation.Infinite
            NumberAnimation { from: 0.3; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 1.0; to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
        }
    }

    // Finished tick/checkmark badge
    Rectangle {
        id: finishedBadge
        visible: root.state === "finished"
        width: Math.max(8, root.iconSize * 0.58)
        height: width
        radius: width / 2
        color: root.successColor
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -2
        anchors.bottomMargin: -2 + root.glyphYOffset
        border.color: "#181616"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: "✓"
            color: "#181616"
            font.family: root.fontFamily
            font.pixelSize: Math.max(6, parent.height * 0.72)
            font.bold: true
        }
    }

    // Action needed exclamation mark badge
    Rectangle {
        id: actionBadge
        visible: root.state === "action_needed"
        width: Math.max(8, root.iconSize * 0.58)
        height: width
        radius: width / 2
        color: root.badgeColor
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -2
        anchors.bottomMargin: -2 + root.glyphYOffset
        border.color: "#181616"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: "!"
            color: "#181616"
            font.family: root.fontFamily
            font.pixelSize: Math.max(6, parent.height * 0.72)
            font.bold: true
        }
    }
}
