import QtQuick

// Pill-shaped click target used by presets and the action row.
Item {
    id: chip
    required property var root
    property real panelScale: 1
    property real panelTextScale: 1
    readonly property real fontScale: panelScale * panelTextScale
    readonly property real rowScale: panelScale * Math.max(1, panelTextScale)

    property string label: ""
    property bool selected: false
    signal activated()

    implicitWidth: chipText.implicitWidth + 18 * chip.panelScale
    implicitHeight: 22 * chip.rowScale

    Rectangle {
        anchors.fill: parent
        color: chipMouse.containsMouse
               ? Qt.rgba(chip.root.ink.r, chip.root.ink.g, chip.root.ink.b, 0.10)
               : Qt.rgba(chip.root.ink.r, chip.root.ink.g, chip.root.ink.b, 0.04)
        border.color: chip.selected ? chip.root.seal : chip.root.sep
        border.width: 1
        radius: chip.root.cornerRadius
        antialiasing: true
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
    }

    Text {
        id: chipText
        anchors.centerIn: parent
        text: chip.label
        color: chip.selected ? chip.root.ink : chip.root.inkDeep
        font.family: chip.root.mono
        font.pixelSize: 10 * chip.fontScale
        font.letterSpacing: 2 * chip.fontScale
    }

    MouseArea {
        id: chipMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.activated()
    }
}
