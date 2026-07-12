import QtQuick
import Quickshell
import Quickshell.Io
import "Palette.js" as Palette

Item {
	id: theme

	readonly property string colorsPath: Quickshell.env("HOME") + "/.config/aether/theme/colors.toml"

	property color paper: "#121212"
	property color ink: "#ffffff"
	property color seal: "#4faa50"

	readonly property color bg: Qt.rgba(paper.r, paper.g, paper.b, 0.95)
	readonly property color fg: ink
	readonly property color accent: seal
	readonly property color sep: Qt.rgba(ink.r, ink.g, ink.b, 0.18)

	readonly property string mono: "JetBrainsMono Nerd Font"

	readonly property color inkDeep: Qt.rgba(ink.r, ink.g, ink.b, 0.55)
	readonly property int cornerRadius: 10

	FileView {
		id: pf
		path: theme.colorsPath
		watchChanges: true
		onLoaded: Palette.apply(theme, Palette.parse(pf.text()))
		onFileChanged: Palette.apply(theme, Palette.parse(pf.text()))
	}
}
