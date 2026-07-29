import QtQuick
import QtQuick.Layouts

// System detail - concise CPU/memory guidance with btop as the deeper view.
Item {
    id: body
    required property var root
    required property var nav
    width: parent ? parent.width : 0

    signal close()

    implicitHeight: col.implicitHeight + 8

    // Only one focusable thing (the BTOP button). Keep the contract so
    // OmniMenu's forwarder doesn't think the body refuses to handle keys.
    property int kbdIndex: 0
    readonly property int _kbdMax: 1

    function kbdHandle(event) {
        const k = event.key;
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || k === Qt.Key_B) {
            body._launch();
            return true;
        }
        return false;
    }
    function _launch() {
        if (body.nav) body.nav.run("omarchy-launch-or-focus-tui btop");
        body.close();
    }
    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 6
        spacing: 10

        Repeater {
            model: [
                { label: "CPU", value: body.nav ? Math.round(body.nav.cpuVal) : 0 },
                { label: "MEM", value: body.nav ? Math.round(body.nav.memVal) : 0 }
            ]
            delegate: Item {
                required property var modelData
                width: col.width
                height: 32

                Text {
                    id: lbl
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: modelData.label
                    color: body.root.inkDeep
                    font.family: body.root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 22
                    height: 3
                    color: Qt.rgba(body.root.ink.r, body.root.ink.g, body.root.ink.b, 0.14)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * Math.max(0, Math.min(1, modelData.value / 100))
                        color: body.root.ink
                        Behavior on width { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    id: valLbl
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: Math.round(modelData.value) + "%"
                    color: body.root.ink
                    font.family: body.root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 1.5
                    font.weight: Font.Medium
                }
            }
        }

        Item {
            width: parent.width
            height: 30

            Rectangle {
                anchors.fill: parent
                color: actionMouse.containsMouse || body.kbdIndex === 0
                       ? Qt.rgba(body.root.ink.r, body.root.ink.g, body.root.ink.b, 0.06)
                       : "transparent"
                border.width: 1
                border.color: actionMouse.containsMouse || body.kbdIndex === 0 ? body.root.ink : body.root.sep
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: "OPEN BTOP"
                color: body.root.ink
                font.family: body.root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
                font.weight: Font.Medium
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: "DETAIL PROCESS VIEW"
                color: body.root.inkDeep
                font.family: body.root.mono
                font.pixelSize: 10
                font.letterSpacing: 1.2
            }
            MouseArea {
                id: actionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: body._launch()
            }
        }
    }
}
