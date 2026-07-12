import QtQuick

Item {
	required property var root
	width: 9; height: 12
	Rectangle { anchors.centerIn: parent; width: 1; height: 12; color: root.sep }
}
