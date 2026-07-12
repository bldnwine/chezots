import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

PanelWindow {
	id: bar
	required property var root

	anchors.top: true; anchors.left: true; anchors.right: true
	exclusionMode: ExclusionMode.Normal
	exclusiveZone: 28
	implicitHeight: 28
	color: root.bg

	Item {
		anchors.fill: parent
		anchors.leftMargin: 10; anchors.rightMargin: 10

		// ===== LEFT: WORKSPACES =====
		Row {
			anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
			spacing: 0
			Repeater {
				model: 10
				delegate: Workspace {
					required property int index
					root: bar.root
					wsId: index + 1
					label: String(index + 1)
					active: bar.root.activeWs === (index + 1)
					present: bar.root.existingWs.indexOf(index + 1) !== -1
					onActivated: bar.root.run("hyprctl dispatch workspace " + (index + 1))
				}
			}
		}

		// ===== CENTER: RECORDING, CLOCK, KEYBOARD =====
		Row {
			anchors.centerIn: parent
			spacing: 6

			Text {
				id: recIcon
				visible: root.recordingActive
				text: "\uf03d"
				color: root.seal
				font.family: root.mono; font.pixelSize: 10
				anchors.verticalCenter: parent.verticalCenter
			}

			Text {
				id: clockText
				text: root.dow + " " + root.dd + "  " + root.hh + ":" + root.mm
				color: root.ink
				font.family: root.mono; font.pixelSize: 11
				MouseArea {
					anchors.fill: parent
					onClicked: root.run("gsimplecal")
				}
			}
		}

		// ===== RIGHT: MPRIS + MODULES =====
		Row {
			anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
			spacing: 8

			// MPRIS + VOLUME
			Item {
				id: mprisGroup
				width: 90; height: 28
				anchors.verticalCenter: parent.verticalCenter
				Row {
					anchors.centerIn: parent; spacing: 0
					Text {
						id: mprisLabel
						visible: root.mprisPlayer !== null && root.mprisPlayer.isPlaying
						text: "\u25B6 " + (root.musicArtist ? root.musicArtist + " - " : "") + root.musicTitle
						color: root.paper; font.family: root.mono; elide: Text.ElideRight
						verticalAlignment: Text.AlignVCenter
						leftPadding: 10; rightPadding: 6; font.pixelSize: 11
						Rectangle { z: -1; anchors.fill: parent; color: root.seal; radius: 10 }
						MouseArea {
							anchors.fill: parent
							onClicked: { if (root.mprisPlayer) root.mprisPlayer.togglePlaying() }
						}
					}
					Item {
						width: 80; height: 18
						anchors.verticalCenter: parent.verticalCenter
						opacity: mvArea.containsMouse ? 1 : 0
						Behavior on opacity { NumberAnimation { duration: 300 } }
						Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 6; radius: 3; color: root.paper }
						Rectangle {
							anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
							width: parent.width * (root.activeSink && root.activeSink.audio ? root.activeSink.audio.volume : (root.audioVol / 100))
							height: 6; radius: 3; color: root.ink
						}
						MouseArea {
							anchors.fill: parent
							onClicked: {
								if (root.activeSink && root.activeSink.audio)
									root.activeSink.audio.volume = Math.max(0, Math.min(1, mouse.x / width))
							}
						}
					}
				}
				MouseArea { id: mvArea; anchors.fill: parent; hoverEnabled: true }
			}

			Module { root: bar.root; glyph: "󰍛"; fontSize: 16
				tooltip: "CPU " + Math.round(root.cpuVal) + "%  RAM " + Math.round(root.memVal) + "%"
				color: root.cpuVal > 80 ? root.seal : root.ink
				onActivated: root.run("ghostty -e btop") }

			Module { root: bar.root; glyph: root.netIcon
				tooltip: root.netKind === 0 ? "Offline" : "Wi-Fi · " + root.wifiSignal + "%"
				color: root.ink; fontSize: 14
				onActivated: root.run("ghostty --title=impala -e impala")
				onRightActivated: root.run("bash /home/bldnwine/.config/waybar/scripts/proton-vpn.sh --menu") }

			Module { root: bar.root; glyph: root.audioIcon
				tooltip: root.audioMuted
					? "Muted"
					: root.audioVol + "%"
				color: root.ink; fontSize: 14
				onActivated: root.run("pavucontrol")
				onRightActivated: root.run("pamixer -t") }

			Module { root: bar.root; visible: root.protonConnected; glyph: "\uf084"
				tooltip: "VPN connected"; color: root.seal; fontSize: 13
				onActivated: root.run("bash /home/bldnwine/.config/waybar/scripts/proton-vpn.sh --menu") }

			Module { root: bar.root; visible: root.batteryIcon().length > 0; glyph: root.batteryIcon()
				tooltip: "Battery " + root.batVal + "%" + (root.batState.length > 0 ? " · " + root.batState : "")
				color: root.batVal <= 10 ? root.seal : root.batVal <= 20 ? root.accent : root.ink; fontSize: 12 }
		}
	}
}
