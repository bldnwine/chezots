import QtQuick
import QtQuick.Layouts

Item {
    id: sepItem
    required property var root

    Layout.alignment: root.isHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter
    Layout.preferredWidth:  root.isHorizontal ? 9 : root.barHeight
    Layout.preferredHeight: root.isHorizontal ? root.barHeight : 9

    Rectangle {
        anchors.centerIn: parent
        width:  sepItem.root.isHorizontal ? 1  : 12
        height: sepItem.root.isHorizontal ? 12 : 1
        color: sepItem.root.sep
    }
}
