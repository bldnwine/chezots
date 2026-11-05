import QtQuick
import QtQuick.VectorImage
import QtQuick.Shapes
import "BarIconMetrics.js" as Metrics

// Size describes the visible artwork frame, excluding the SVG's blank padding.
Item {
    id: icon
    property url source: ""
    property real size: 14
    property color color: "#c5c9c5"
    readonly property alias status: image.status
    readonly property string iconName: source.toString().split("/").pop().replace(/\.svg$/, "")
    readonly property var inkBounds: Metrics.bounds(iconName)
    readonly property real renderSize: size / Math.max(inkBounds[2], inkBounds[3])
    readonly property real artworkX: (width - renderSize) / 2 + (0.5 - inkBounds[0] - inkBounds[2] / 2) * renderSize
    readonly property real artworkY: (height - renderSize) / 2 + (0.5 - inkBounds[1] - inkBounds[3] / 2) * renderSize
    readonly property real paintedWidth: inkBounds[2] * renderSize
    readonly property real paintedHeight: inkBounds[3] * renderSize

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    // Bind native path colors once per asset load. Theme changes then update
    // the paths directly, without a bitmap or an offscreen tinting layer.
    function tintPaths(item) {
        if (!item) return;
        if (item instanceof Shape) {
            for (let path of item.data) {
                if (!(path instanceof ShapePath)) continue;
                const fillAlpha = path.fillColor.a;
                const strokeAlpha = path.strokeColor.a;
                if (fillAlpha > 0) path.fillColor = Qt.binding(function() {
                    return Qt.rgba(icon.color.r, icon.color.g, icon.color.b, icon.color.a * fillAlpha);
                });
                if (strokeAlpha > 0) path.strokeColor = Qt.binding(function() {
                    return Qt.rgba(icon.color.r, icon.color.g, icon.color.b, icon.color.a * strokeAlpha);
                });
            }
        }
        for (let child of item.children) tintPaths(child);
    }

    VectorImage {
        id: image
        x: icon.artworkX
        y: icon.artworkY
        width: icon.renderSize
        height: icon.renderSize
        source: icon.source
        fillMode: VectorImage.PreserveAspectFit
        preferredRendererType: VectorImage.CurveRenderer
        onStatusChanged: if (status === VectorImage.Ready) icon.tintPaths(generatedItem)
    }
}
