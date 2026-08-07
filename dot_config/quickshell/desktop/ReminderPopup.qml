import QtQuick
import Quickshell
import Quickshell.Io

CardWindow {
    id: reminderPopup
    required property var root

    theme: root
    plain: true
    revealed: root.reminderVisible
    cardWidth: 380
    layerNamespace: "omarchy-reminder"
    title: "REMINDER"
    subtitle: "SET TIMER OR ALARM"
    footer: "ENTER SET · TAB/ARROWS NAV · ESC CLOSE"

    anchorEdge: reminderPopup.root.barEdge
    anchorBarX: reminderPopup.root.popupAnchorX
    anchorBarY: reminderPopup.root.popupAnchorY

    property string minutesText: "5"
    property string noteText: ""
    property var activeReminders: []

    // 0..4 = Presets, 5 = Mins, 6 = Note, 7 = SET btn, 8..8+N-1 = Active rows
    property int kbdIndex: 6
    readonly property int presetCount: 5
    readonly property int kbdMax: 8 + activeReminders.length

    function refreshReminders() {
        reminderProbe.running = false;
        reminderProbe.running = true;
    }

    function setReminder(mins, msg) {
        const m = parseInt(mins) || 0;
        if (m <= 0) return;
        const script = Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/reminder";
        const args = msg && msg.length > 0 ? [script, String(m), msg] : [script, String(m)];
        Quickshell.execDetached(args);
        reminderPopup.noteText = "";
        reminderPopup.refreshReminders();
    }

    function clearAllReminders() {
        const script = Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/reminder";
        Quickshell.execDetached([script, "clear"]);
        reminderPopup.refreshReminders();
    }

    function clearSingleReminder(unit) {
        if (!unit) return;
        const script = Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/reminder";
        Quickshell.execDetached([script, "clear", unit]);
        reminderPopup.refreshReminders();
    }

    function activateAt(idx) {
        if (idx >= 0 && idx < 5) {
            const mins = [5, 10, 15, 30, 60][idx];
            reminderPopup.setReminder(mins, reminderPopup.noteText);
        } else if (idx === 7) {
            reminderPopup.setReminder(reminderPopup.minutesText, reminderPopup.noteText);
        } else if (idx >= 8) {
            const item = reminderPopup.activeReminders[idx - 8];
            if (item) reminderPopup.clearSingleReminder(item.unit);
        }
    }

    function updateFocusForIndex(idx) {
        reminderPopup.kbdIndex = idx;
        if (idx === 5) {
            minsInput.forceActiveFocus();
        } else if (idx === 6) {
            noteInput.forceActiveFocus();
        } else {
            col.forceActiveFocus();
        }
    }

    Process {
        id: reminderProbe
        running: false
        command: [Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/reminder", "show", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text.trim());
                    reminderPopup.activeReminders = data.reminders || [];
                } catch (e) {
                    reminderPopup.activeReminders = [];
                }
            }
        }
    }

    Timer {
        interval: 3000
        running: reminderPopup.revealed
        repeat: true
        triggeredOnStart: true
        onTriggered: reminderPopup.refreshReminders()
    }

    Component.onCompleted: reminderPopup.refreshReminders()
    onDismiss: root.reminderVisible = false

    onRevealedChanged: {
        if (reminderPopup.revealed) {
            reminderPopup.kbdIndex = 6;
            Qt.callLater(() => {
                noteInput.forceActiveFocus();
            });
            reminderPopup.refreshReminders();
        }
    }

    onKeyPressed: (event) => {
        const k = event.key;

        if (k === Qt.Key_Escape) {
            root.reminderVisible = false;
            event.accepted = true;
            return;
        }

        if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            let next = (k === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier))
                ? (reminderPopup.kbdIndex - 1 + reminderPopup.kbdMax) % Math.max(1, reminderPopup.kbdMax)
                : (reminderPopup.kbdIndex + 1) % Math.max(1, reminderPopup.kbdMax);
            reminderPopup.updateFocusForIndex(next);
            event.accepted = true;
            return;
        }

        // If in text input fields (minsInput or noteInput), allow Left/Right arrows & characters to work natively
        if (reminderPopup.kbdIndex === 5 || reminderPopup.kbdIndex === 6) {
            if (k === Qt.Key_Up) {
                reminderPopup.updateFocusForIndex(2); // Jump to preset chips
                event.accepted = true;
            } else if (k === Qt.Key_Down) {
                reminderPopup.updateFocusForIndex(reminderPopup.activeReminders.length > 0 ? 8 : 7);
                event.accepted = true;
            } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                reminderPopup.setReminder(reminderPopup.minutesText, reminderPopup.noteText);
                event.accepted = true;
            }
            return;
        }

        // For non-input controls (Presets, SET button, Active rows), arrows navigate
        if (k === Qt.Key_Right) {
            reminderPopup.updateFocusForIndex((reminderPopup.kbdIndex + 1) % Math.max(1, reminderPopup.kbdMax));
            event.accepted = true;
        } else if (k === Qt.Key_Left) {
            reminderPopup.updateFocusForIndex((reminderPopup.kbdIndex - 1 + reminderPopup.kbdMax) % Math.max(1, reminderPopup.kbdMax));
            event.accepted = true;
        } else if (k === Qt.Key_Down) {
            if (reminderPopup.kbdIndex < 5) reminderPopup.updateFocusForIndex(6);
            else if (reminderPopup.kbdIndex === 7) reminderPopup.updateFocusForIndex(reminderPopup.activeReminders.length > 0 ? 8 : 6);
            else if (reminderPopup.kbdIndex >= 8 && reminderPopup.kbdIndex < reminderPopup.kbdMax - 1) reminderPopup.updateFocusForIndex(reminderPopup.kbdIndex + 1);
            event.accepted = true;
        } else if (k === Qt.Key_Up) {
            if (reminderPopup.kbdIndex >= 8) reminderPopup.updateFocusForIndex(6);
            else if (reminderPopup.kbdIndex < 5) reminderPopup.updateFocusForIndex(6);
            event.accepted = true;
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            reminderPopup.activateAt(reminderPopup.kbdIndex);
            event.accepted = true;
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 12

        // Section: Presets
        Text {
            text: "QUICK PRESETS"
            color: root.inkDeep
            font.family: root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
        }

        Row {
            width: parent.width
            spacing: 6

            Repeater {
                model: [
                    { label: "+5m", mins: 5 },
                    { label: "+10m", mins: 10 },
                    { label: "+15m", mins: 15 },
                    { label: "+30m", mins: 30 },
                    { label: "+1h", mins: 60 }
                ]
                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property bool focused: reminderPopup.kbdIndex === index

                    width: (col.width - 24) / 5
                    height: 28
                    radius: root.cornerRadius
                    color: focused || presetMouse.containsMouse ? root.rowHi : root.rowSel
                    border.color: focused || presetMouse.containsMouse ? root.seal : root.sep
                    border.width: focused ? 2 : 1

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: focused ? root.seal : root.ink
                        font.family: root.mono
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: presetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            reminderPopup.kbdIndex = index;
                            reminderPopup.setReminder(modelData.mins, reminderPopup.noteText);
                        }
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: root.sep }

        // Section: Custom Entry
        Text {
            text: "CUSTOM TIMER"
            color: root.inkDeep
            font.family: root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
        }

        Row {
            width: parent.width
            spacing: 8

            // Minutes Input Box
            Rectangle {
                width: 70
                height: 32
                radius: root.cornerRadius
                color: reminderPopup.kbdIndex === 5 ? root.rowHi : "transparent"
                border.color: reminderPopup.kbdIndex === 5 ? root.seal : root.sep
                border.width: reminderPopup.kbdIndex === 5 ? 2 : 1

                TextInput {
                    id: minsInput
                    anchors.fill: parent
                    anchors.margins: 6
                    focus: reminderPopup.kbdIndex === 5
                    activeFocusOnTab: true
                    text: reminderPopup.minutesText
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 12
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    selectByMouse: true
                    onTextChanged: reminderPopup.minutesText = text
                    onActiveFocusChanged: {
                        if (activeFocus) reminderPopup.kbdIndex = 5;
                    }
                    Keys.onReturnPressed: (event) => { reminderPopup.setReminder(reminderPopup.minutesText, reminderPopup.noteText); event.accepted = true; }
                    Keys.onEnterPressed:  (event) => { reminderPopup.setReminder(reminderPopup.minutesText, reminderPopup.noteText); event.accepted = true; }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "min"
                color: root.inkDeep
                font.family: root.mono
                font.pixelSize: 11
            }

            // Note / Message Input Box
            Rectangle {
                width: parent.width - 70 - 8 - 30 - 8 - 70
                height: 32
                radius: root.cornerRadius
                color: reminderPopup.kbdIndex === 6 ? root.rowHi : "transparent"
                border.color: reminderPopup.kbdIndex === 6 ? root.seal : root.sep
                border.width: reminderPopup.kbdIndex === 6 ? 2 : 1

                TextInput {
                    id: noteInput
                    anchors.fill: parent
                    anchors.margins: 6
                    focus: reminderPopup.kbdIndex === 6
                    activeFocusOnTab: true
                    text: reminderPopup.noteText
                    color: root.ink
                    font.family: root.mono
                    font.pixelSize: 11
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    onTextChanged: reminderPopup.noteText = text
                    onActiveFocusChanged: {
                        if (activeFocus) reminderPopup.kbdIndex = 6;
                    }
                    Keys.onReturnPressed: (event) => { reminderPopup.setReminder(reminderPopup.minutesText, reminderPopup.noteText); event.accepted = true; }
                    Keys.onEnterPressed:  (event) => { reminderPopup.setReminder(reminderPopup.minutesText, reminderPopup.noteText); event.accepted = true; }

                    Text {
                        visible: noteInput.text.length === 0
                        anchors.fill: parent
                        text: "Note (optional)..."
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 11
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            // Set Button
            Rectangle {
                width: 60
                height: 32
                radius: root.cornerRadius
                color: reminderPopup.kbdIndex === 7 || setBtnMouse.containsMouse ? root.rowHi : root.rowSel
                border.color: root.seal
                border.width: reminderPopup.kbdIndex === 7 ? 2 : 1

                Text {
                    anchors.centerIn: parent
                    text: "SET"
                    color: root.seal
                    font.family: root.mono
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                MouseArea {
                    id: setBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        reminderPopup.kbdIndex = 7;
                        reminderPopup.setReminder(reminderPopup.minutesText, reminderPopup.noteText);
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: root.sep }

        // Section: Active Reminders Header
        Item {
            width: parent.width
            height: 20

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "ACTIVE REMINDERS (" + reminderPopup.activeReminders.length + ")"
                color: root.inkDeep
                font.family: root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
            }

            Text {
                visible: reminderPopup.activeReminders.length > 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "CLEAR ALL"
                color: clearAllMouse.containsMouse ? root.seal : root.inkDeep
                font.family: root.mono
                font.pixelSize: 10
                font.letterSpacing: 1

                MouseArea {
                    id: clearAllMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: reminderPopup.clearAllReminders()
                }
            }
        }

        // Active Reminders List
        Repeater {
            model: reminderPopup.activeReminders
            delegate: Rectangle {
                required property var modelData
                required property int index

                readonly property bool focused: reminderPopup.kbdIndex === (8 + index)

                width: col.width
                height: 34
                radius: root.cornerRadius
                color: focused || rowMouse.containsMouse ? root.rowHi : "transparent"
                border.color: focused ? root.seal : root.sep
                border.width: focused ? 2 : 1

                Row {
                    anchors.left: parent.left
                    anchors.right: delBtn.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰔛"
                        color: root.seal
                        font.family: root.mono
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: root.ink
                        font.family: root.mono
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        width: parent.width - 20 - 70 - 16
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.remaining
                        color: root.inkDeep
                        font.family: root.mono
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }
                }

                Rectangle {
                    id: delBtn
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    radius: root.cornerRadius
                    color: delMouse.containsMouse ? root.rowHi : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: delMouse.containsMouse ? root.seal : root.inkDeep
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: delMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: reminderPopup.clearSingleReminder(modelData.unit)
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: reminderPopup.kbdIndex = 8 + index
                }
            }
        }

        Text {
            visible: reminderPopup.activeReminders.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "NO PENDING REMINDERS"
            color: root.inkDeep
            font.family: root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
        }
    }
}
