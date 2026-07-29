import QtQuick
import QtQuick.Layouts

Item {
    id: wsCell
    visible: active || present
    required property var root

    property int wsId: 0
    property string label: ""
    property bool active: false
    property bool present: false
    signal activated()

    Layout.alignment: root.isHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter
    Layout.preferredWidth:  root.isHorizontal ? 20 : root.barHeight
    Layout.preferredHeight: root.isHorizontal ? root.barHeight : 20

    onActiveChanged: {
        if (active && root.lastDirection !== 0) {
            slideHome.stop();
            if (root.isHorizontal) {
                kanji.slideX = root.lastDirection * 2;
                kanji.slideY = 0;
            } else {
                kanji.slideY = root.lastDirection * 2;
                kanji.slideX = 0;
            }
            slideHome.start();
        }
    }

    NumberAnimation {
        id: slideHome
        target: kanji
        properties: "slideX,slideY"
        to: 0
        duration: 180
        easing.type: Easing.OutCubic
    }

    Bloom { id: bloom; root: wsCell.root }

    // Circle dot for the focused workspace
    Rectangle {
        anchors.centerIn: parent
        width: 6
        height: 6
        radius: 3
        color: wsCell.root.seal
        opacity: wsCell.active ? 1.0 : 0
        scale: wsCell.active ? 1.0 : 0.3
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 120 } }
    }

    Text {
        id: kanji
        property real slideX: 0
        property real slideY: 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: slideX
        anchors.verticalCenter: parent.verticalCenter
        // -1 lift matches Module.qml so kanji optically align with icons.
        anchors.verticalCenterOffset: slideY - 1
        text: wsCell.label
        color: wsCell.root.ink
        opacity: wsCell.active ? 0 : 0.95
        font.family: wsCell.root.serif
        font.pixelSize: 12
        font.weight: Font.DemiBold
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    MouseArea {
        // Reach 2px into the 4px grid gap on every side so there are no dead
        // strips between adjacent numbers — each kanji owns the space up to
        // the midpoint between it and its neighbour, making clicks forgiving.
        anchors.fill: parent
        anchors.margins: -2
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: { console.log("[WS-DIAG hover] ws=" + wsCell.wsId); bloom.fire(mouseX, mouseY); }
        onClicked: { console.log("[WS-DIAG click] ws=" + wsCell.wsId); wsCell.activated(); }
    }
}
