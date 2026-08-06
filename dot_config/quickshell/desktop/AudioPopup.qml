import QtQuick
import Quickshell.Services.Pipewire

// Audio popup — volume slider + output/input device pickers. Data comes
// from Navbar's wpctl/pactl probes (the same source the bar icon uses), so
// labels are readable and there's no dependency on PwNode metadata that
// quickshell 0.3.0 doesn't populate. The only Pipewire service use left is
// the input peak meter, which reads a node ref directly.
CardWindow {
    id: audioPopup
    required property var root

    theme: root
    revealed: root.audioVisible
    cardWidth: 390
    layerNamespace: "omarchy-audio"
    title: "AUDIO"
    subtitle: root.audioMuted
              ? "MUTED"
              : (root.audioSinkDesc ? root.audioSinkDesc + " · " : "")
                + root.audioVol + "%"
    footer: "M MUTE · B MIXER · ENTER ACT · ESC CLOSE"

    anchorEdge: audioPopup.root.barEdge
    anchorBarX: audioPopup.root.popupAnchorX
    anchorBarY: audioPopup.root.popupAnchorY

    onDismiss: audioPopup.root.audioVisible = false

    // ---------- Data from Navbar probes ----------
    readonly property var displaySinks:   audioPopup.root.audioSinks
    readonly property var displaySources: audioPopup.root.audioSources
    readonly property bool inputVisible:   audioPopup.displaySources.length > 0
    readonly property int  outputVolume:   audioPopup.root.audioVol
    readonly property bool outputMuted:    audioPopup.root.audioMuted
    readonly property int  inputVolume:    audioPopup.root.audioInputVol
    readonly property bool inputMuted:     audioPopup.root.audioInputMuted

    // ---------- Keyboard cursor: flat row model ----------
    property int kbdIndex: 0
    readonly property var kbdRows: {
        const rows = [];
        rows.push({ type: "hero" });
        rows.push({ type: "outSlider" });
        for (const s of audioPopup.displaySinks) rows.push({ type: "sink", sink: s });
        if (audioPopup.inputVisible) {
            rows.push({ type: "inSlider" });
            for (const s of audioPopup.displaySources) rows.push({ type: "source", source: s });
        }
        return rows;
    }
    readonly property var kbdRow: audioPopup.kbdRows[audioPopup.kbdIndex] || {}

    readonly property int _sourceKbdBase: 2 + audioPopup.displaySinks.length
                                          + (audioPopup.inputVisible ? 1 : 0)
    function sinkKbd(i)   { return 2 + i; }
    function sourceKbd(i) { return audioPopup._sourceKbdBase + i; }
    function sinkFocused(i)   { return audioPopup.kbdRow.type === "sink"   && audioPopup.kbdIndex === audioPopup.sinkKbd(i); }
    function sourceFocused(i) { return audioPopup.kbdRow.type === "source" && audioPopup.kbdIndex === audioPopup.sourceKbd(i); }

    function clampKbd() {
        if (audioPopup.kbdIndex >= audioPopup.kbdRows.length)
            audioPopup.kbdIndex = Math.max(0, audioPopup.kbdRows.length - 1);
    }
    onKbdRowsChanged: audioPopup.clampKbd()

    onRevealedChanged: {
        if (audioPopup.revealed) audioPopup.kbdIndex = 1;   // land on the output slider
        else audioPopup.kbdIndex = 0;
    }

    // ---------- Actions ----------
    function deviceGlyph(name, kind) {
        const blob = String(name || "").toLowerCase();
        if (blob.indexOf("bluetooth") !== -1) return "󰂯";
        if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹";
        if (blob.indexOf("headset") !== -1 || blob.indexOf("headphone") !== -1) return "󰋋";
        return kind === "source" ? "󰍬" : "󰓃";
    }
    function outputIcon() {
        if (audioPopup.outputMuted) return "";
        const v = audioPopup.outputVolume;
        if (v >= 67) return "";
        if (v >= 34) return "";
        if (v > 0) return "";
        return "";
    }
    function setOutputVolume(pct) {
        audioPopup.root.setAudioVolume(pct);
    }
    function setInputVolume(pct) {
        audioPopup.root.setInputVolume(pct);
    }
    function toggleOutputMute() {
        audioPopup.root.toggleAudioMute();
    }
    function toggleInputMute() {
        audioPopup.root.toggleInputMute();
    }
    function setDefaultSink(id, port) {
        if (id) audioPopup.root.setDefaultSink(id, port);
    }
    function setDefaultSource(id, port) {
        if (id) audioPopup.root.setDefaultSource(id, port);
    }
    function adjustFocused(delta) {
        const row = audioPopup.kbdRow;
        if (row.type === "outSlider") audioPopup.setOutputVolume(audioPopup.outputVolume + delta);
        else if (row.type === "inSlider") audioPopup.setInputVolume(audioPopup.inputVolume + delta);
    }
    function activateFocused() {
        const row = audioPopup.kbdRow;
        if (row.type === "hero") audioPopup.toggleOutputMute();
        else if (row.type === "outSlider") audioPopup.toggleOutputMute();
        else if (row.type === "inSlider") audioPopup.toggleInputMute();
        else if (row.type === "sink") audioPopup.setDefaultSink(row.sink.id, row.sink.port);
        else if (row.type === "source") audioPopup.setDefaultSource(row.source.id, row.source.port);
    }
    function muteFocused() {
        const row = audioPopup.kbdRow;
        if (row.type === "inSlider") audioPopup.toggleInputMute();
        else audioPopup.toggleOutputMute();
    }
    function openMixer() {
        audioPopup.root.run("pavucontrol");
        audioPopup.root.audioVisible = false;
    }

    onKeyPressed: function(event) {
        const k = event.key;
        if (k === Qt.Key_Q) {
            audioPopup.root.audioVisible = false;
        } else if (k === Qt.Key_Down || k === Qt.Key_J) {
            audioPopup.kbdIndex = Math.min(audioPopup.kbdRows.length - 1, audioPopup.kbdIndex + 1);
        } else if (k === Qt.Key_Up || k === Qt.Key_K) {
            audioPopup.kbdIndex = Math.max(0, audioPopup.kbdIndex - 1);
        } else if (k === Qt.Key_Left || k === Qt.Key_H) {
            audioPopup.adjustFocused(-5);
        } else if (k === Qt.Key_Right || k === Qt.Key_L) {
            audioPopup.adjustFocused(5);
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            audioPopup.activateFocused();
        } else if (k === Qt.Key_M) {
            audioPopup.muteFocused();
        } else if (k === Qt.Key_B) {
            audioPopup.openMixer();
        } else {
            return;
        }
        event.accepted = true;
    }

    // Live input level. Binds a node ref directly, so it works even though
    // PwNode metadata is empty on this quickshell version.
    PwNodePeakMonitor {
        id: inputPeak
        node: Pipewire.defaultAudioSource
        enabled: audioPopup.revealed
    }

    Column {
        width: parent.width
        spacing: 8

        // ---------- Hero: output glyph + master mute ----------
        Item {
            width: parent.width
            height: 30

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: audioPopup.outputIcon()
                color: audioPopup.root.ink
                font.family: audioPopup.root.mono
                font.pixelSize: 15
                opacity: audioPopup.outputMuted ? 0.5 : 1.0
            }
            QuickButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                root: audioPopup.root
                label: audioPopup.outputMuted ? "UNMUTE" : "MUTE"
                selected: audioPopup.kbdRow.type === "hero"
                onClicked: audioPopup.toggleOutputMute()
            }
        }

        Rectangle { width: parent.width; height: 1; color: audioPopup.root.sep }

        // ---------- OUTPUT ----------
        Column {
            width: parent.width
            spacing: 6

            Item {
                width: parent.width
                height: 18
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "OUTPUT"
                    color: audioPopup.root.inkDeep
                    font.family: audioPopup.root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }
            }
            DisplaySlider {
                root: audioPopup.root
                width: parent.width
                value: audioPopup.outputVolume
                minV: 0
                maxV: 100
                unit: "%"
                selected: audioPopup.kbdRow.type === "outSlider"
                onCommit: (v) => audioPopup.setOutputVolume(v)
            }
            Repeater {
                model: audioPopup.displaySinks
                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property bool active: modelData.isActive
                    readonly property bool focused: audioPopup.sinkFocused(index)

                    width: parent.width
                    height: 32
                    radius: audioPopup.root.cornerRadius
                    color: active || focused
                           ? audioPopup.root.rowSel
                           : sinkMouse.containsMouse ? audioPopup.root.rowHi : "transparent"
                    border.color: active || focused ? audioPopup.root.seal : audioPopup.root.sep
                    border.width: focused ? 2 : 1
                    Behavior on color        { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                    Behavior on border.width { NumberAnimation { duration: 120 } }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: audioPopup.deviceGlyph(modelData.name + " " + modelData.portLabel, "sink")
                            color: active ? audioPopup.root.seal : audioPopup.root.ink
                            font.family: audioPopup.root.mono
                            font.pixelSize: 13
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.portLabel ? modelData.name + " · " + modelData.portLabel : modelData.name
                            elide: Text.ElideRight
                            width: parent.width - 21 - 8
                            color: active ? audioPopup.root.ink : audioPopup.root.fg
                            font.family: audioPopup.root.mono
                            font.pixelSize: 11
                            font.weight: active ? Font.Medium : Font.Normal
                        }
                    }
                    MouseArea {
                        id: sinkMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: audioPopup.setDefaultSink(modelData.id, modelData.port)
                    }
                }
            }
        }

        // ---------- INPUT ----------
        Column {
            width: parent.width
            spacing: 6
            visible: audioPopup.inputVisible

            Rectangle {
                width: parent.width
                height: 1
                color: audioPopup.root.sep
            }
            Item {
                width: parent.width
                height: 18
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "INPUT"
                    color: audioPopup.root.inkDeep
                    font.family: audioPopup.root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                }
            }
            DisplaySlider {
                root: audioPopup.root
                width: parent.width
                value: audioPopup.inputVolume
                minV: 0
                maxV: 100
                unit: "%"
                selected: audioPopup.kbdRow.type === "inSlider"
                onCommit: (v) => audioPopup.setInputVolume(v)
            }
            Rectangle {
                width: parent.width
                height: 4
                radius: 1
                color: Qt.rgba(audioPopup.root.ink.r, audioPopup.root.ink.g, audioPopup.root.ink.b, 0.12)
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, Math.min(1, inputPeak.peak))
                    color: audioPopup.inputMuted ? audioPopup.root.fg : audioPopup.root.seal
                    Behavior on width { NumberAnimation { duration: 70 } }
                }
            }
            Repeater {
                model: audioPopup.displaySources
                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property bool active: modelData.isActive
                    readonly property bool focused: audioPopup.sourceFocused(index)

                    width: parent.width
                    height: 32
                    radius: audioPopup.root.cornerRadius
                    color: active || focused
                           ? audioPopup.root.rowSel
                           : sourceMouse.containsMouse ? audioPopup.root.rowHi : "transparent"
                    border.color: active || focused ? audioPopup.root.seal : audioPopup.root.sep
                    border.width: focused ? 2 : 1
                    Behavior on color        { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                    Behavior on border.width { NumberAnimation { duration: 120 } }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: audioPopup.deviceGlyph(modelData.name + " " + modelData.portLabel, "source")
                            color: active ? audioPopup.root.seal : audioPopup.root.ink
                            font.family: audioPopup.root.mono
                            font.pixelSize: 13
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.portLabel ? modelData.name + " · " + modelData.portLabel : modelData.name
                            elide: Text.ElideRight
                            width: parent.width - 21 - 8
                            color: active ? audioPopup.root.ink : audioPopup.root.fg
                            font.family: audioPopup.root.mono
                            font.pixelSize: 11
                            font.weight: active ? Font.Medium : Font.Normal
                        }
                    }
                    MouseArea {
                        id: sourceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: audioPopup.setDefaultSource(modelData.id, modelData.port)
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: audioPopup.root.sep }

        Item {
            width: parent.width
            height: 30

            Rectangle {
                anchors.fill: parent
                color: mixerMouse.containsMouse
                       ? Qt.rgba(audioPopup.root.ink.r, audioPopup.root.ink.g, audioPopup.root.ink.b, 0.06)
                       : "transparent"
                border.width: 1
                border.color: mixerMouse.containsMouse ? audioPopup.root.ink : audioPopup.root.sep
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: "OPEN PAVUCONTROL"
                color: audioPopup.root.ink
                font.family: audioPopup.root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
                font.weight: Font.Medium
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: "DETAIL AUDIO MIXER"
                color: audioPopup.root.inkDeep
                font.family: audioPopup.root.mono
                font.pixelSize: 10
                font.letterSpacing: 1.2
            }

            MouseArea {
                id: mixerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: audioPopup.openMixer()
            }
        }
    }
}
