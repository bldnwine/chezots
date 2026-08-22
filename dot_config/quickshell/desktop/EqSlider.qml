import QtQuick

// Vertical parametric EQ band slider with zero-center fill, drag, and mouse wheel support.
Item {
    id: eqSlider
    required property var root

    property real freq: 1000
    property real gain: 0.0
    property real minGain: -12.0
    property real maxGain: 12.0
    property real qVal: 1.0
    property string filterType: "peaking"
    property bool selected: false

    signal valueModified(real newGain)

    readonly property bool dragging: sliderMouse.pressed
    property real pendingGain: gain

    function formatFreq(f) {
        if (f >= 1000) {
            const k = f / 1000;
            return (k % 1 === 0 ? k.toFixed(0) : k.toFixed(1)) + "k";
        }
        return Math.round(f).toString();
    }

    function formatGain(g) {
        const val = eqSlider.dragging ? eqSlider.pendingGain : g;
        if (Math.abs(val) < 0.05) return "0.0";
        return (val > 0 ? "+" : "") + val.toFixed(1);
    }

    function gainFromY(yPos) {
        const trackH = track.height;
        if (trackH <= 0) return 0.0;
        // y = 0 is top (maxGain), y = trackH is bottom (minGain)
        const ratio = 1.0 - Math.max(0, Math.min(1, yPos / trackH));
        const raw = eqSlider.minGain + ratio * (eqSlider.maxGain - eqSlider.minGain);
        // snap to 0.5 dB
        return Math.round(raw * 2) / 2;
    }

    function yFromGain(g) {
        const span = eqSlider.maxGain - eqSlider.minGain;
        if (span <= 0) return track.height / 2;
        const norm = (g - eqSlider.minGain) / span;
        // Top is 1.0 norm (maxGain), bottom is 0.0 norm (minGain)
        return (1.0 - Math.max(0, Math.min(1, norm))) * track.height;
    }

    implicitWidth: 32
    implicitHeight: 160

    Column {
        anchors.fill: parent
        spacing: 4

        // Gain readout (top)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: eqSlider.formatGain(eqSlider.gain)
            color: Math.abs(eqSlider.dragging ? eqSlider.pendingGain : eqSlider.gain) > 0.05
                   ? (eqSlider.selected ? eqSlider.root.ink : eqSlider.root.seal)
                   : eqSlider.root.inkDeep
            font.family: eqSlider.root.mono
            font.pixelSize: 9
            font.weight: Font.Medium
        }

        // Vertical Track area
        Item {
            id: trackContainer
            width: parent.width
            height: 122

            Rectangle {
                id: track
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 3
                radius: 1
                color: Qt.rgba(eqSlider.root.ink.r, eqSlider.root.ink.g, eqSlider.root.ink.b, 0.14)

                // 0 dB center reference line
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 1
                    color: eqSlider.root.sep
                }

                // Dynamic vertical fill from center (0dB) to current thumb position
                Rectangle {
                    readonly property real curY: eqSlider.yFromGain(eqSlider.dragging ? eqSlider.pendingGain : eqSlider.gain)
                    readonly property real centerY: track.height / 2

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.min(curY, centerY)
                    height: Math.max(1, Math.abs(curY - centerY))
                    width: 3
                    color: eqSlider.root.seal
                    opacity: eqSlider.selected ? 1.0 : 0.8
                }

                // Thumb handle
                Rectangle {
                    readonly property real curY: eqSlider.yFromGain(eqSlider.dragging ? eqSlider.pendingGain : eqSlider.gain)
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.max(0, Math.min(track.height - height, curY - height / 2))
                    width: 12
                    height: 4
                    radius: 1
                    color: sliderMouse.containsMouse || eqSlider.dragging ? eqSlider.root.ink : eqSlider.root.seal
                    border.color: eqSlider.root.bg
                    border.width: 1
                }
            }

            MouseArea {
                id: sliderMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onPressed: (e) => {
                    eqSlider.pendingGain = eqSlider.gainFromY(e.y);
                    eqSlider.valueModified(eqSlider.pendingGain);
                }
                onPositionChanged: (e) => {
                    if (!pressed) return;
                    eqSlider.pendingGain = eqSlider.gainFromY(e.y);
                    eqSlider.valueModified(eqSlider.pendingGain);
                }
                onReleased: {
                    eqSlider.valueModified(eqSlider.pendingGain);
                }
                onWheel: (wheel) => {
                    const step = (wheel.angleDelta.y > 0 ? 0.5 : -0.5);
                    const nextG = Math.max(eqSlider.minGain, Math.min(eqSlider.maxGain, eqSlider.gain + step));
                    eqSlider.valueModified(nextG);
                }
                onDoubleClicked: {
                    eqSlider.valueModified(0.0);
                }
            }
        }

        // Frequency Label (bottom)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: eqSlider.formatFreq(eqSlider.freq)
            color: eqSlider.selected ? eqSlider.root.ink : eqSlider.root.inkDeep
            font.family: eqSlider.root.mono
            font.pixelSize: 9
            font.letterSpacing: 1
        }
    }
}
