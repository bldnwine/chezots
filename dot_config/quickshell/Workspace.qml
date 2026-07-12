import QtQuick

Item {
	id: wsCell
	required property var root

	property int wsId: 0
	property string label: ""
	property bool active: false
	property bool present: false
	signal activated()

	width: 20; height: 28

	onActiveChanged: {
		if (active && root.lastDirection !== 0) {
			slideHome.stop();
			kanji.slideX = root.lastDirection * 2;
			kanji.slideY = 0;
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

	Text {
		id: kanji
		property real slideX: 0
		property real slideY: 0
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.horizontalCenterOffset: slideX
		anchors.verticalCenter: parent.verticalCenter
		anchors.verticalCenterOffset: slideY - 1
		text: wsCell.label
		color: wsCell.active ? wsCell.root.seal : (wsCell.present ? wsCell.root.ink : wsCell.root.ink)
		opacity: wsCell.active ? 1.0 : (wsCell.present ? 0.75 : 0.35)
		font.family: wsCell.root.mono
		font.pixelSize: wsCell.active ? 13 : 11
		font.weight: Font.Medium
		Behavior on color { ColorAnimation { duration: 120 } }
		Behavior on opacity { NumberAnimation { duration: 120 } }
		Behavior on font.pixelSize { NumberAnimation { duration: 120 } }
	}

	MouseArea {
		anchors.fill: parent
		anchors.margins: -2
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: wsCell.activated()
	}
}
