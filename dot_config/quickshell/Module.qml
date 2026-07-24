import QtQuick

Item {
	id: mod
	required property var root

	property string glyph: ""
	property string tooltip: ""
	property color color: root.ink
	property string fontFamily: root.mono
	property int fontSize: 12
	property int glyphYOffset: -1

	signal activated()
	signal rightActivated()

	property bool tooltipHovered: mouse.containsMouse

	width: 24; height: 28

	Rectangle {
		anchors.fill: parent
		anchors.margins: 3
		radius: 4
		color: mouse.containsMouse ? Qt.rgba(mod.root.ink.r, mod.root.ink.g, mod.root.ink.b, 0.08) : "transparent"
		Behavior on color { ColorAnimation { duration: 180 } }
	}

	Text {
		anchors.centerIn: parent
		anchors.verticalCenterOffset: mod.glyphYOffset
		text: mod.glyph
		color: mod.color
		font.family: mod.fontFamily
		font.pixelSize: mod.fontSize
	}

	MouseArea {
		id: mouse
		anchors.fill: parent
		hoverEnabled: true
		acceptedButtons: Qt.LeftButton | Qt.RightButton
		cursorShape: Qt.PointingHandCursor
		property bool tooltipHovered: mouse.containsMouse
		onEntered: { if (mod.tooltip) mod.root.showTooltip(mod, mod.tooltip) }
		onExited: { mod.root.hideTooltip(mod) }
		onClicked: (e) => {
			mod.root.hideTooltip(mod);
			if (e.button === Qt.RightButton) mod.rightActivated();
			else mod.activated();
		}
	}
}
