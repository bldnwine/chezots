import QtQuick
import Quickshell

// Background alpha and a bounded compositor request. This item never captures
// the desktop or renders a shader; text and controls keep their own opacity.
Item {
    id: effects
    visible: false
    required property Item targetSurface
    property color background: "transparent"
    property var opacityOverride: null
    property bool blurEnabled: false
    property bool shown: true
    property real cornerRadius: 0
    // Region.item does not observe QQuickTransform animations. Describe the
    // reveal transform explicitly so the native region follows every frame.
    property real scaleFactor: targetSurface.scale
    property point scaleOrigin: Qt.point(targetSurface.width / 2, targetSurface.height / 2)
    property point translation: Qt.point(0, 0)
    readonly property point surfacePosition: {
        const parent = targetSurface.parent;
        return parent ? parent.mapToItem(null, targetSurface.x, targetSurface.y)
            : Qt.point(targetSurface.x, targetSurface.y);
    }
    readonly property rect bounds: Qt.rect(
        surfacePosition.x + scaleOrigin.x * (1 - scaleFactor) + translation.x,
        surfacePosition.y + scaleOrigin.y * (1 - scaleFactor) + translation.y,
        targetSurface.width * scaleFactor, targetSurface.height * scaleFactor)
    readonly property color fill: Qt.rgba(background.r, background.g, background.b,
        typeof opacityOverride === "number" && isFinite(opacityOverride)
            ? Math.max(0, Math.min(1, opacityOverride)) : background.a)
    readonly property bool requestingBlur: shown && blurEnabled && fill.a < 1
        && targetSurface.width > 0 && targetSurface.height > 0
    readonly property var blurRegion: requestingBlur ? regionSpec : null

    Region {
        id: regionSpec
        x: Math.ceil(effects.bounds.x)
        y: Math.ceil(effects.bounds.y)
        width: Math.max(0, Math.floor(effects.bounds.x + effects.bounds.width) - x)
        height: Math.max(0, Math.floor(effects.bounds.y + effects.bounds.height) - y)
        radius: Math.round(effects.cornerRadius * effects.scaleFactor)
    }
}
