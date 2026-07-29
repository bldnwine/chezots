import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: cell

    required property var root

    property string text: ""
    property string glyph: ""
    property string imageSource: ""
    property string tooltip: ""
    property color ink: root.ink
    property bool active: false
    property bool present: true
    property bool strong: false
    property bool borderless: false
    property color accentColor: root.ink
    property string fontFamily: root.mono
    property string iconFamily: root.mono
    property int fontSize: 11
    property int iconSize: fontSize + 1
    property int iconYOffset: -1
    property int textYOffset: 0
    property int minWidth: 24
    property int maxWidth: 180

    readonly property bool hasIcon: glyph !== "" || imageSource !== ""
    readonly property bool hasImageIcon: img.status === Image.Ready && imageSource !== ""
    readonly property int iconSlotWidth: hasIcon ? Math.max(iconSize, 12) : 0
    readonly property int iconGap: hasIcon && text.length > 0 ? 5 : 0
    readonly property real contentImplicitWidth: iconSlotWidth + iconGap + (text.length > 0 ? label.implicitWidth : 0)

    readonly property color bg: root.bg
    readonly property color muted: root.inkDeep
    readonly property color activeAccent: root.ink
    readonly property color strongAccent: accentColor
    readonly property color line: root.sep
    readonly property color hoverFill: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
    readonly property color activeFill: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
    readonly property color displayColor: active ? activeAccent : (strong ? strongAccent : (present ? ink : muted))

    signal activated()
    signal middleActivated()
    signal rightActivated()

    Layout.alignment: root.isHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter
    Layout.preferredWidth: root.isHorizontal
                           ? Math.min(maxWidth, Math.max(minWidth, contentImplicitWidth + 14))
                           : root.barHeight
    Layout.preferredHeight: root.isHorizontal ? root.barHeight : minWidth

    Timer {
        id: tipDelay
        interval: 320
        onTriggered: {
            if (!cell.tooltip) return;
            const p = cell.mapToItem(null, cell.width / 2, cell.height / 2);
            cell.root.showTooltip(cell.tooltip, p.x, p.y);
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 0
        visible: !cell.borderless
        color: cell.active ? cell.activeFill
              : (mouse.containsMouse ? cell.hoverFill : "transparent")
        border.width: cell.active || mouse.containsMouse || cell.strong ? 1 : 0
        border.color: cell.active ? cell.activeAccent : (cell.strong ? cell.strongAccent : cell.line)
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Row {
        anchors.centerIn: parent
        height: parent.height
        spacing: cell.iconGap

        Item {
            width: cell.iconSlotWidth
            height: parent.height
            visible: cell.hasIcon

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: cell.iconYOffset
                visible: cell.glyph !== "" && !cell.hasImageIcon
                text: cell.glyph
                color: cell.displayColor
                opacity: cell.present ? 1.0 : 0.55
                font.family: cell.iconFamily
                font.pixelSize: cell.iconSize
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            Image {
                id: img
                anchors.centerIn: parent
                width: cell.iconSize
                height: cell.iconSize
                visible: false
                source: cell.imageSource
                sourceSize.width: cell.iconSize * 2
                sourceSize.height: cell.iconSize * 2
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
                cache: true
                layer.enabled: cell.hasImageIcon
            }
            MultiEffect {
                anchors.fill: img
                visible: cell.hasImageIcon
                source: img
                colorization: 1.0
                colorizationColor: cell.displayColor
                opacity: cell.present ? 1.0 : 0.55
                Behavior on colorizationColor { ColorAnimation { duration: 120 } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }

        Item {
            width: cell.text.length > 0
                   ? Math.min(label.implicitWidth, Math.max(0, cell.width - 14 - cell.iconSlotWidth - cell.iconGap))
                   : 0
            height: parent.height
            visible: cell.text.length > 0

            Text {
                id: label
                anchors.centerIn: parent
                anchors.verticalCenterOffset: cell.textYOffset
                width: parent.width
                text: cell.text
                color: cell.displayColor
                opacity: cell.present ? 1.0 : 0.55
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: cell.fontFamily
                font.pixelSize: cell.fontSize
                font.weight: cell.active || cell.strong ? Font.Medium : Font.Normal
                font.letterSpacing: cell.strong ? 1.2 : 0.4
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onEntered: if (cell.tooltip) tipDelay.restart()
        onExited: {
            tipDelay.stop();
            cell.root.hideTooltip(cell.tooltip);
        }
        onClicked: (e) => {
            tipDelay.stop();
            cell.root.hideTooltip(cell.tooltip);
            if (e.button === Qt.RightButton) cell.rightActivated();
            else if (e.button === Qt.MiddleButton) cell.middleActivated();
            else cell.activated();
        }
    }
}
