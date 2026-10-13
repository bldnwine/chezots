import QtQuick
import QtQuick.Controls
import Quickshell.Services.Pipewire

// Device controls use Navbar's probes; application playback uses native PipeWire nodes.
CardWindow {
    id: audioPopup
    required property var root

    property bool eqExpanded: false

    theme: root
    revealed: root.audioVisible
    cardWidth: eqExpanded ? 890 : 390
    layerNamespace: "omarchy-audio"
    title: eqExpanded ? "AUDIO & EQUALIZER" : "AUDIO"
    subtitle: root.audioMuted
              ? "MUTED"
              : (root.audioSinkDesc ? root.audioSinkDesc + " · " : "")
                + root.audioVol + "%"
    footer: eqExpanded ? "M MUTE · E TOGGLE EQ · B MIXER · ENTER ACT" : "M MUTE · E EQ · B MIXER · ENTER ACT"

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

    // Bind candidates before inspecting properties. Filtering the tracker itself by
    // bound properties would unbind hidden nodes and create a binding loop.
    readonly property var playbackCandidates: audioPopup.revealed
        ? Pipewire.nodes.values.filter(n => n && n.type === PwNodeType.AudioOutStream)
        : []
    PwObjectTracker { objects: audioPopup.playbackCandidates }
    readonly property var playbackNodes: audioPopup.playbackCandidates.filter(n => {
        if (!n.ready || !n.audio || n.audio.channels.length === 0) return false;
        const props = n.properties;
        const role = String(props["media.role"] || "").toLowerCase();
        return role !== "event" && role !== "notification"
            && !props["event.id"] && !n.name.startsWith("effect_");
    }).sort((a, b) => a.id - b.id)
    // Keep long device/stream lists compact while still fitting smaller screens.
    readonly property real maxDeckHeight: Math.max(100, Math.min(480,
        audioPopup.height - audioPopup.root.barOffset - 2 * audioPopup.anchorGap - 210))

    component AudioScrollBar: ScrollBar {
        id: audioScrollBar
        policy: ScrollBar.AsNeeded
        minimumSize: 0.08
        implicitWidth: 5
        padding: 0
        contentItem: Rectangle {
            implicitWidth: 5
            implicitHeight: 20
            radius: 2
            color: audioPopup.root.seal
            opacity: audioScrollBar.active ? 1 : 0.6
        }
        background: Rectangle {
            radius: 2
            color: audioPopup.root.sep
            opacity: 0.4
        }
    }

    function playbackName(node) {
        return node.properties["application.name"] || node.description || node.name || "Application";
    }
    function playbackLabel(node) {
        const label = node.properties["media.name"] || "";
        return label !== audioPopup.playbackName(node) ? label : "";
    }
    function setPlaybackVolume(node, pct) {
        if (audioPopup.revealed && node && node.ready && node.audio)
            node.audio.volume = Math.max(0, Math.min(100, Math.round(pct))) / 100;
    }
    function togglePlaybackMute(node) {
        if (audioPopup.revealed && node && node.ready && node.audio)
            node.audio.muted = !node.audio.muted;
    }

    // ---------- Keyboard cursor: flat row model ----------
    property string kbdSelection: "outSlider"
    property int kbdFallbackIndex: 1
    readonly property var kbdRows: {
        const rows = [];
        rows.push({ type: "hero", key: "hero" });
        rows.push({ type: "outSlider", key: "outSlider" });
        for (const s of audioPopup.displaySinks)
            rows.push({ type: "sink", sink: s, key: "sink:" + s.id + ":" + s.port });
        for (const n of audioPopup.playbackNodes)
            rows.push({ type: "playback", node: n, key: "playback:" + n.id });
        if (audioPopup.inputVisible) {
            rows.push({ type: "inSlider", key: "inSlider" });
            for (const s of audioPopup.displaySources)
                rows.push({ type: "source", source: s, key: "source:" + s.id + ":" + s.port });
        }
        return rows;
    }
    readonly property int kbdIndex: Math.max(0,
        audioPopup.kbdRows.findIndex(r => r.key === audioPopup.kbdSelection))
    readonly property var kbdRow: audioPopup.focusedRow()

    function focusedRow() {
        return audioPopup.kbdRows.find(r => r.key === audioPopup.kbdSelection) || {};
    }
    function selectKbd(index) {
        const rows = audioPopup.kbdRows || [];
        const target = Math.max(0, Math.min(index, rows.length - 1));
        audioPopup.kbdFallbackIndex = target;
        audioPopup.kbdSelection = rows[target] ? rows[target].key : "hero";
    }

    readonly property int _sourceKbdBase: 2 + audioPopup.displaySinks.length
                                          + audioPopup.playbackNodes.length
                                          + (audioPopup.inputVisible ? 1 : 0)
    function sinkKbd(i)   { return 2 + i; }
    function sourceKbd(i) { return audioPopup._sourceKbdBase + i; }
    function sinkFocused(i)   { return audioPopup.kbdRow.type === "sink"   && audioPopup.kbdIndex === audioPopup.sinkKbd(i); }
    function sourceFocused(i) { return audioPopup.kbdRow.type === "source" && audioPopup.kbdIndex === audioPopup.sourceKbd(i); }
    function playbackKbd(i) { return 2 + audioPopup.displaySinks.length + i; }

    function ensureFocusVisible() {
        const deck = audioPopup.eqExpanded ? rightDeck : normalDeck;
        if (deck.item) deck.item.ensureFocusVisible();
    }

    function clampKbd() {
        if (!audioPopup.kbdRows) return;
        const found = audioPopup.kbdRows.findIndex(r => r.key === audioPopup.kbdSelection);
        if (found >= 0) audioPopup.kbdFallbackIndex = found;
        else audioPopup.selectKbd(audioPopup.kbdFallbackIndex);
    }
    onKbdRowsChanged: audioPopup.clampKbd()
    onKbdSelectionChanged: Qt.callLater(audioPopup.ensureFocusVisible)

    onRevealedChanged: {
        audioPopup.selectKbd(audioPopup.revealed ? 1 : 0);
    }
    Component.onCompleted: audioPopup.selectKbd(audioPopup.revealed ? 1 : 0)

    // ---------- Actions ----------
    function deviceGlyph(name, kind) {
        const blob = String(name || "").toLowerCase();
        if (blob.indexOf("equalizer") !== -1 || blob.indexOf("effect_") !== -1) return "󰓃";
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
        const row = audioPopup.focusedRow();
        if (row.type === "outSlider") audioPopup.setOutputVolume(audioPopup.outputVolume + delta);
        else if (row.type === "inSlider") audioPopup.setInputVolume(audioPopup.inputVolume + delta);
        else if (row.type === "playback" && row.node && row.node.ready)
            audioPopup.setPlaybackVolume(row.node, row.node.audio.volume * 100 + delta);
    }
    function activateFocused() {
        const row = audioPopup.focusedRow();
        if (row.type === "hero") audioPopup.toggleOutputMute();
        else if (row.type === "outSlider") audioPopup.toggleOutputMute();
        else if (row.type === "inSlider") audioPopup.toggleInputMute();
        else if (row.type === "sink") audioPopup.setDefaultSink(row.sink.id, row.sink.port);
        else if (row.type === "source") audioPopup.setDefaultSource(row.source.id, row.source.port);
        else if (row.type === "playback") audioPopup.togglePlaybackMute(row.node);
    }
    function muteFocused() {
        const row = audioPopup.focusedRow();
        if (row.type === "inSlider") audioPopup.toggleInputMute();
        else if (row.type === "playback") audioPopup.togglePlaybackMute(row.node);
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
        } else if (k === Qt.Key_E) {
            audioPopup.eqExpanded = !audioPopup.eqExpanded;
        } else if (k === Qt.Key_Down || k === Qt.Key_J) {
            audioPopup.selectKbd(audioPopup.kbdIndex + 1);
        } else if (k === Qt.Key_Up || k === Qt.Key_K) {
            audioPopup.selectKbd(audioPopup.kbdIndex - 1);
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

    // Live input level. Binds a node ref directly.
    PwNodePeakMonitor {
        id: inputPeak
        node: Pipewire.defaultAudioSource
        enabled: audioPopup.revealed
    }

    // Component for the standard Audio Control Pane (Volume, Sinks, Sources, Pavucontrol)
    Component {
        id: audioControlsComponent

        Flickable {
            id: controlsScroll
            implicitHeight: Math.min(controlsColumn.implicitHeight, audioPopup.maxDeckHeight)
            height: implicitHeight
            contentWidth: width
            contentHeight: controlsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            ScrollBar.vertical: AudioScrollBar {}

            function ensureFocusVisible() {
                const row = audioPopup.focusedRow();
                let item = null;
                if (row.type === "outSlider") item = outputSlider;
                else if (row.type === "sink") item = sinkRows.itemAt(audioPopup.kbdIndex - 2);
                else if (row.type === "playback")
                    item = playbackRows.itemAt(audioPopup.kbdIndex - audioPopup.playbackKbd(0));
                else if (row.type === "inSlider") item = inputSlider;
                else if (row.type === "source")
                    item = sourceRows.itemAt(audioPopup.kbdIndex - audioPopup._sourceKbdBase);
                if (row.type === "hero") contentY = 0;
                if (!item) return;
                const top = item.mapToItem(controlsColumn, 0, 0).y;
                let target = contentY;
                if (top < target) target = top;
                else if (top + item.height > target + height) target = top + item.height - height;
                contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), target));
            }
            Component.onCompleted: Qt.callLater(audioPopup.ensureFocusVisible)
            onHeightChanged: Qt.callLater(audioPopup.ensureFocusVisible)
            onContentHeightChanged: contentY = Math.max(0,
                Math.min(contentY, Math.max(0, contentHeight - height)))

            Column {
                id: controlsColumn
                // Reserve the gutter even before overflow so rows don't resize
                // when an application starts or stops playback.
                width: controlsScroll.width - 12
                spacing: 8

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
                        id: outputSlider
                        root: audioPopup.root
                        width: parent.width
                        value: audioPopup.outputVolume
                        minV: 0
                        maxV: 100
                        unit: "%"
                        selected: audioPopup.kbdRow.type === "outSlider"
                        onFocusRequested: audioPopup.selectKbd(1)
                        onCommit: (v) => audioPopup.setOutputVolume(v)
                    }
                    Repeater {
                        id: sinkRows
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
                                onClicked: {
                                    audioPopup.selectKbd(audioPopup.sinkKbd(index));
                                    audioPopup.setDefaultSink(modelData.id, modelData.port);
                                }
                            }
                        }
                    }
                }

                // ---------- APPLICATION PLAYBACK ----------
                Column {
                    width: parent.width
                    spacing: 6
                    Rectangle { width: parent.width; height: 1; color: audioPopup.root.sep }
                    Text {
                        text: "PLAYBACK"
                        color: audioPopup.root.inkDeep
                        font.family: audioPopup.root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }
                    Text {
                        width: parent.width
                        visible: audioPopup.playbackNodes.length === 0
                        text: Pipewire.ready ? "No application playback" : "Playback unavailable"
                        color: audioPopup.root.inkDeep
                        font.family: audioPopup.root.mono
                        font.pixelSize: 11
                    }
                    Repeater {
                        id: playbackRows
                        model: audioPopup.playbackNodes
                        delegate: Rectangle {
                            id: playbackRow
                            required property var modelData
                            required property int index
                            readonly property var node: modelData
                            readonly property bool focused: audioPopup.kbdRow.type === "playback"
                                && audioPopup.kbdRow.node === node
                            readonly property string mediaLabel: node ? audioPopup.playbackLabel(node) : ""
                            width: controlsColumn.width
                            height: playbackContent.implicitHeight + 16
                            radius: audioPopup.root.cornerRadius
                            color: focused ? audioPopup.root.rowSel : "transparent"
                            border.color: focused ? audioPopup.root.seal : audioPopup.root.sep
                            border.width: focused ? 2 : 1
                            enabled: node !== null && node.ready && node.audio !== null

                            MouseArea {
                                anchors.fill: parent
                                onClicked: audioPopup.selectKbd(audioPopup.playbackKbd(playbackRow.index))
                            }
                            Column {
                                id: playbackContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                spacing: 6
                                Item {
                                    width: parent.width
                                    height: Math.max(28, streamLabels.implicitHeight)
                                    Column {
                                        id: streamLabels
                                        anchors.left: parent.left
                                        anchors.right: streamMute.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2
                                        Text {
                                            width: parent.width
                                            text: playbackRow.node ? audioPopup.playbackName(playbackRow.node) : ""
                                            elide: Text.ElideRight
                                            color: audioPopup.root.fg
                                            font.family: audioPopup.root.mono
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            width: parent.width
                                            visible: text.length > 0
                                            text: playbackRow.mediaLabel
                                            elide: Text.ElideRight
                                            color: audioPopup.root.inkDeep
                                            font.family: audioPopup.root.mono
                                            font.pixelSize: 10
                                        }
                                    }
                                    QuickButton {
                                        id: streamMute
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        root: audioPopup.root
                                        padH: 8
                                        label: playbackRow.node && playbackRow.node.audio.muted ? "UNMUTE" : "MUTE"
                                        selected: playbackRow.node && playbackRow.node.audio.muted
                                        onClicked: {
                                            audioPopup.selectKbd(audioPopup.playbackKbd(playbackRow.index));
                                            audioPopup.togglePlaybackMute(playbackRow.node);
                                        }
                                    }
                                }
                                DisplaySlider {
                                    root: audioPopup.root
                                    width: parent.width
                                    minV: 0
                                    maxV: 100
                                    unit: "%"
                                    value: playbackRow.node ? playbackRow.node.audio.volume * 100 : 0
                                    selected: playbackRow.focused
                                    onFocusRequested: audioPopup.selectKbd(audioPopup.playbackKbd(playbackRow.index))
                                    onCommit: v => audioPopup.setPlaybackVolume(playbackRow.node, v)
                                }
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
                        id: inputSlider
                        root: audioPopup.root
                        width: parent.width
                        value: audioPopup.inputVolume
                        minV: 0
                        maxV: 100
                        unit: "%"
                        selected: audioPopup.kbdRow.type === "inSlider"
                        onFocusRequested: audioPopup.selectKbd(audioPopup._sourceKbdBase - 1)
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
                        id: sourceRows
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
                                onClicked: {
                                    audioPopup.selectKbd(audioPopup.sourceKbd(index));
                                    audioPopup.setDefaultSource(modelData.id, modelData.port);
                                }
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
    }

    Column {
        width: parent.width
        spacing: 8

        // ---------- Hero: output glyph + EQ toggle + master mute ----------
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

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                QuickButton {
                    root: audioPopup.root
                    label: audioPopup.eqExpanded ? "HIDE EQ" : "EQ"
                    glyph: "󰓃"
                    selected: audioPopup.eqExpanded
                    onClicked: audioPopup.eqExpanded = !audioPopup.eqExpanded
                }

                QuickButton {
                    root: audioPopup.root
                    label: audioPopup.outputMuted ? "UNMUTE" : "MUTE"
                    selected: audioPopup.kbdRow.type === "hero"
                    onClicked: audioPopup.toggleOutputMute()
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: audioPopup.root.sep }

        // ---------- Content Deck (Single Column vs 2-Column Split when EQ Expanded) ----------
        Item {
            width: parent.width
            height: audioPopup.eqExpanded
                    ? Math.max(eqScroll.implicitHeight, rightDeck.implicitHeight)
                    : normalDeck.implicitHeight

            // Expanded Mode: Split Row
            Row {
                id: splitRow
                visible: audioPopup.eqExpanded
                anchors.fill: parent
                spacing: 14

                readonly property real totalDividerW: splitRow.spacing * 2 + 1
                readonly property real availPaneW: parent.width - totalDividerW
                readonly property real leftPaneW: Math.floor(availPaneW / 2)
                readonly property real rightPaneW: availPaneW - leftPaneW

                // Left Pane: Equalizer Deck
                Flickable {
                    id: eqScroll
                    width: splitRow.leftPaneW
                    height: parent.height
                    implicitHeight: Math.min(eqDeck.implicitHeight, audioPopup.maxDeckHeight)
                    contentWidth: width
                    contentHeight: eqDeck.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    ScrollBar.vertical: AudioScrollBar {}
                    EqPanel {
                        id: eqDeck
                        root: audioPopup.root
                        width: eqScroll.width - 12
                    }
                }

                // Center Divider
                Rectangle {
                    width: 1
                    height: parent.height
                    color: audioPopup.root.sep
                }

                // Right Pane: Standard Audio Controls
                Loader {
                    id: rightDeck
                    active: audioPopup.eqExpanded
                    width: splitRow.rightPaneW
                    sourceComponent: audioControlsComponent
                    onLoaded: Qt.callLater(audioPopup.ensureFocusVisible)
                }
            }

            // Compact Mode: Single Column
            Loader {
                id: normalDeck
                active: !audioPopup.eqExpanded
                visible: !audioPopup.eqExpanded
                anchors.fill: parent
                sourceComponent: audioControlsComponent
                onLoaded: Qt.callLater(audioPopup.ensureFocusVisible)
            }
        }
    }
}
