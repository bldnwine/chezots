import QtQuick
import QtQuick.Window
import QtQuick.Effects
import "MaterialMetrics.js" as Metrics

// Local Google Material Symbols Rounded, weight 400 / grade 0 / opsz 20.
Item {
    id: icon

    property string name: ""
    property bool filled: false
    property real size: 16
    property real paintedSize: size * 0.75
    property color color: "#c5c9c5"
    readonly property var inkBounds: Metrics.bounds(name)
    readonly property real renderSize: paintedSize / Math.max(inkBounds[2], inkBounds[3])
    readonly property real paintedWidth: inkBounds[2] * renderSize
    readonly property real paintedHeight: inkBounds[3] * renderSize
    readonly property real artworkOffsetX: (0.5 - inkBounds[0] - inkBounds[2] / 2) * renderSize
    readonly property real artworkOffsetY: (0.5 - inkBounds[1] - inkBounds[3] / 2) * renderSize
    readonly property int rasterSize: Math.ceil(renderSize * Math.max(2, Screen.devicePixelRatio))
    readonly property alias status: image.status
    readonly property url source: name.length > 0
        ? Qt.resolvedUrl("icons/material-rounded/" + name + (filled ? "_fill1" : "") + "_20px.svg")
        : ""

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Image {
        id: image
        width: icon.renderSize
        height: icon.renderSize
        x: (parent.width - width) / 2 + icon.artworkOffsetX
        y: (parent.height - height) / 2 + icon.artworkOffsetY
        visible: false
        source: icon.source
        sourceSize.width: icon.rasterSize
        sourceSize.height: icon.rasterSize
        fillMode: Image.PreserveAspectFit
        smooth: true
        cache: true
    }

    MultiEffect {
        anchors.fill: image
        source: image
        visible: image.status === Image.Ready
        autoPaddingEnabled: false
        // Google's unmodified SVGs have black paths. Lift the mask to white
        // before colorization so the output matches the theme color exactly.
        brightness: 1.0
        colorization: 1.0
        colorizationColor: Qt.rgba(icon.color.r, icon.color.g, icon.color.b, 1)
        opacity: icon.color.a
    }
}
