import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

ShellRoot {
	id: shell

	Theme { id: theme }
	Navbar {
		id: nav
		theme: theme
	}

	IpcHandler {
		target: "dnd"
		function toggleDnd() { nav.dnd = !nav.dnd }
		function setDnd(v: bool) { nav.dnd = v }
	}

	NotificationServer {
		id: notifServer
		bodySupported: true
		bodyMarkupSupported: true
		actionsSupported: true
		persistenceSupported: true
	}

	PanelWindow {
		id: notifWindow
		visible: !nav.dnd
		anchors.top: true; anchors.right: true
		margins.top: 28; margins.right: 8
		exclusionMode: ExclusionMode.Ignore
		implicitWidth: 380; color: "transparent"

		ColumnLayout {
			anchors.top: parent.top; anchors.right: parent.right
			anchors.topMargin: 4; spacing: 6

			Repeater {
				model: notifServer.trackedNotifications

				delegate: Item {
					implicitWidth: 360; implicitHeight: card.implicitHeight
					Layout.alignment: Qt.AlignRight

					Rectangle {
						id: card
						width: parent.width
						height: content.implicitHeight + 20
						color: nav.paper
						border.color: nav.seal
						border.width: 2; radius: 12

						ColumnLayout {
							id: content
							anchors.fill: parent; anchors.margins: 10; spacing: 2

							Text {
								text: modelData.appName
								color: nav.seal
								font.pixelSize: 9; font.weight: Font.Bold
							}
							Text {
								text: modelData.summary
								color: nav.ink
								font.pixelSize: 11; font.weight: Font.Bold
								wrapMode: Text.WordWrap
								visible: modelData.summary.length > 0
							}
							Text {
								text: modelData.body
								color: nav.ink
								font.pixelSize: 10
								wrapMode: Text.WordWrap
								visible: modelData.body.length > 0
							}
						}

						MouseArea {
							anchors.fill: parent
							onClicked: modelData.dismiss()
						}
					}

					Timer {
						interval: Math.min(modelData.expireTimeout > 0 ? modelData.expireTimeout : 5000, 30000)
						running: true; onTriggered: modelData.dismiss()
					}
				}
			}
		}
	}
}
