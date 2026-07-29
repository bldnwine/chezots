import QtQuick
import Quickshell
import Quickshell.Io

CardWindow {
    id: popup
    required property var root

    theme: root
    revealed: root.screenRecordVisible
    cardWidth: 280
    layerNamespace: "omarchy-screenrecord"
    title: "SCREEN RECORD"

    readonly property bool isRecording: recordingProbe.ready
        ? recordingProbe.stdout.trim() === "active" : false

    subtitle: popup.isRecording ? "RECORDING" : ""

    onDismiss: popup.root.screenRecordVisible = false
    onRevealedChanged: if (revealed) {
        recordingProbe.running = false;
        recordingProbe.running = true;
    }

    onKeyPressed: function(event) {
        const k = event.key;
        if (k === Qt.Key_Escape || k === Qt.Key_Q) {
            popup.root.screenRecordVisible = false;
        } else if (popup.isRecording) {
            if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || k === Qt.Key_S)
                popup.stopRecording();
        } else if (k === Qt.Key_1 || k === Qt.Key_D) { runOption(0); }
        else if (k === Qt.Key_2 || k === Qt.Key_M) { runOption(1); }
        else if (k === Qt.Key_3 || k === Qt.Key_F) { runOption(2); }
        else if (k === Qt.Key_4) { runOption(3); }
        else if (k === Qt.Key_5 || k === Qt.Key_W) { runOption(4); }
        else { return; }
        event.accepted = true;
    }

    Process {
        id: recordingProbe
        running: false
        command: ["sh", "-c", "pgrep -f '^gpu-screen-recorder' >/dev/null && echo active || echo idle"]
        stdout: StdioCollector {}
    }

    function runOption(index) {
        var cmds = [
            "~/.local/bin/capture-screenrecording --with-desktop-audio",
            "~/.local/bin/capture-screenrecording --with-desktop-audio --with-microphone-audio",
            "~/.local/bin/capture-screenrecording --fullscreen --with-desktop-audio",
            "~/.local/bin/capture-screenrecording --fullscreen --with-desktop-audio --with-microphone-audio",
            "~/.local/bin/capture-screenrecording --with-desktop-audio --with-webcam"
        ];
        popup.root.run(cmds[index]);
        popup.root.screenRecordVisible = false;
    }

    function stopRecording() {
        popup.root.run("~/.local/bin/capture-screenrecording --stop-recording");
        popup.root.screenRecordVisible = false;
    }

    Column {
        width: parent.width
        spacing: 8
        padding: 4

        Grid {
            width: parent.width
            columns: 1
            rowSpacing: 6
            columnSpacing: 6

            Repeater {
                model: popup.isRecording
                    ? ["Stop Recording"]
                    : [
                        "Desktop audio only",
                        "Desktop + microphone",
                        "Fullscreen + desktop audio",
                        "Fullscreen + desktop + mic",
                        "Webcam + desktop audio"
                      ]
                delegate: QuickButton {
                    required property string modelData
                    required property int index
                    root: popup.root
                    label: modelData.toUpperCase()
                    selected: false
                    onClicked: {
                        if (popup.isRecording) popup.stopRecording();
                        else popup.runOption(index);
                    }
                }
            }
        }
    }
}
