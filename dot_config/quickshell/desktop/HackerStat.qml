import QtQuick
import QtQuick.Layouts

// One tactical readout for the hackerman bar: an optional leading glyph, a
// dim all-caps label, a mono value, and an optional 5-segment gauge. Lives
// as a child of a RowLayout (horizontal bar) and sizes to its content.
//
// Interaction is deliberately the same as Module.qml — hover wash, cursor
// bloom, delayed tooltip, left/right click — so switching bar faces never
// changes how a cell *behaves*, only how it reads.
Item {
    id: cell
    required property var root

    property string glyph: ""
    property string label: ""
    property string value: ""
    property color  valueColor: root.ink
    property color  labelColor: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.45)
    property real   gauge: -1                 // < 0 hides the bar; otherwise 0..100
    property color  gaugeColor: valueColor
    property bool   blink: false              // pulses the whole cell (e.g. an alert)
    property string tooltip: ""

    signal activated()
    signal middleActivated()
    signal rightActivated()

    readonly property int pad: 5

    Layout.alignment: Qt.AlignVCenter
    Layout.preferredHeight: root.barHeight
    Layout.preferredWidth: row.implicitWidth + 2 * cell.pad

    // Hover wash, matched to Module.qml's 0.08 ink tint and 150ms fade.
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        color: mouse.containsMouse
               ? Qt.rgba(cell.root.ink.r, cell.root.ink.g, cell.root.ink.b, 0.08)
               : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Bloom { id: bloom; root: cell.root }

    Row {
        id: row
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -1
        spacing: 5
        // Driven by the blinker below; left at 1.0 when blink is off.
        property real pulse: 1.0
        opacity: cell.blink ? pulse : 1.0

        Text {
            visible: cell.glyph.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: cell.glyph
            color: cell.valueColor
            font.family: cell.root.mono
            font.pixelSize: 12
        }
        Text {
            visible: cell.label.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: cell.label
            color: cell.labelColor
            font.family: cell.root.mono
            font.pixelSize: 9
            font.letterSpacing: 1
            font.weight: Font.Medium
        }
        Text {
            visible: cell.value.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: cell.value
            color: cell.valueColor
            font.family: cell.root.mono
            font.pixelSize: 11
            font.weight: Font.Medium
        }
        // 5-segment gauge. A segment lights once the gauge passes its
        // midpoint, so 0% leaves all five dark and 100% lights them all.
        Row {
            visible: cell.gauge >= 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Repeater {
                model: 5
                delegate: Rectangle {
                    required property int index
                    width: 3
                    height: 8
                    readonly property bool lit: cell.gauge >= (index + 0.5) * 20
                    color: lit ? cell.gaugeColor
                               : Qt.rgba(cell.root.ink.r, cell.root.ink.g, cell.root.ink.b, 0.16)
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }
        }
    }

    SequentialAnimation {
        id: blinker
        running: cell.blink
        loops: Animation.Infinite
        NumberAnimation { target: row; property: "pulse"; to: 0.25; duration: 520; easing.type: Easing.InOutQuad }
        NumberAnimation { target: row; property: "pulse"; to: 1.0;  duration: 520; easing.type: Easing.InOutQuad }
    }

    Timer {
        id: tipDelay
        interval: 320
        onTriggered: {
            if (!cell.tooltip) return;
            const p = cell.mapToItem(null, cell.width / 2, cell.height / 2);
            cell.root.showTooltip(cell.tooltip, p.x, p.y);
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onEntered: { bloom.fire(mouseX, mouseY); if (cell.tooltip) tipDelay.restart(); }
        onExited:  { tipDelay.stop(); cell.root.hideTooltip(cell.tooltip); }
        onClicked: (e) => {
            tipDelay.stop();
            cell.root.hideTooltip(cell.tooltip);
            if (e.button === Qt.RightButton) cell.rightActivated();
            else if (e.button === Qt.MiddleButton) cell.middleActivated();
            else cell.activated();
        }
    }
}
