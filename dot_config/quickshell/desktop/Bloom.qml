import QtQuick
import QtQuick.Window

// Hover bloom: a soft accent-tinted halo that radiates from the cursor's
// entry point and fades inside the item rect. Single-beat sibling of
// clipboard-ripple. Clipped to the host bounds so neighbours don't get
// splashed.
Item {
    id: bloomRoot
    required property var root
    anchors.fill: parent
    visible: bloomAnim.running
    clip: bloomAnim.running

    // Observe the host, not this item's animation-driven visibility. A
    // hidden bar window also needs to stop its children's animations.
    readonly property bool hostVisible: parent && parent.visible
        && (!Window.window || Window.window.visible)
    onHostVisibleChanged: if (!hostVisible) bloomAnim.stop()

    property real ox: 0
    property real oy: 0
    property real haloRadius: 1

    function fire(x, y) {
        if (!bloomRoot.hostVisible || width <= 0 || height <= 0) return;
        bloomAnim.stop();
        bloomRoot.ox = x;
        bloomRoot.oy = y;
        bloomRoot.haloRadius = Math.max(width, height) * 0.9;
        bloomAnim.restart();
    }

    Rectangle {
        id: halo
        // Build the circle once per hover; only its transform and opacity
        // change during the animation.
        width: bloomRoot.haloRadius * 2
        height: width
        radius: bloomRoot.haloRadius
        x: bloomRoot.ox - bloomRoot.haloRadius
        y: bloomRoot.oy - bloomRoot.haloRadius
        color: Qt.lighter(bloomRoot.root.accent, 1.35)
        scale: 0
        opacity: 0
        antialiasing: true
    }

    ParallelAnimation {
        id: bloomAnim
        onStopped: { halo.scale = 0; halo.opacity = 0; }
        NumberAnimation {
            target: halo; property: "scale"
            from: 2 / bloomRoot.haloRadius; to: 1
            duration: 250
            easing.type: Easing.OutCubic
        }
        SequentialAnimation {
            NumberAnimation { target: halo; property: "opacity"; from: 0; to: 0.22; duration: 80; easing.type: Easing.OutQuad }
            NumberAnimation { target: halo; property: "opacity"; to: 0; duration: 170; easing.type: Easing.InCubic }
        }
    }
}
