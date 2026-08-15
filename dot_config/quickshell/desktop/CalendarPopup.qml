import QtQuick
import Quickshell
import Quickshell.Io
import "CalendarModel.js" as CalendarModel

CardWindow {
    id: calendarPopup
    required property var root

    readonly property string eventsPath: Quickshell.env("HOME") + "/.local/state/omarchy/calendar-events.json"
    readonly property string actionScript: Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/calendar-sync/action.py"

    property var eventDoc: null
    property var eventIndex: ({})
    property var allEvents: []

    property date today: new Date()
    readonly property string todayKey: CalendarModel.keyForDate(today)

    // Month offset driven by chevrons / navbar
    property int monthOffset: root.calendarMonthOffset || 0
    readonly property date viewDate: {
        var d = new Date(today.getFullYear(), today.getMonth() + monthOffset, 1);
        return d;
    }
    readonly property int viewYear: viewDate.getFullYear()
    readonly property int viewMonth: viewDate.getMonth()

    property string selectedDateKey: todayKey
    readonly property var selectedEvents: CalendarModel.eventsForDateKey(eventIndex, selectedDateKey)
    readonly property date selectedDateObj: CalendarModel.dateFromKey(selectedDateKey, today)

    // Next upcoming meeting today
    property real nowMs: Date.now()
    readonly property var upcomingEvent: CalendarModel.nextEvent(allEvents, nowMs)
    readonly property string countdownPhrase: upcomingEvent ? CalendarModel.formatCountdown(CalendarModel.millisUntil(upcomingEvent, nowMs)) : ""

    // CRUD State
    property bool creatingEvent: false
    property string editingEventId: ""

    function submitNewEvent() {
        var t = newTitleInput.text.trim();
        if (!t) return;
        calendarPopup.createEvent(
            t,
            calendarPopup.selectedDateKey,
            startTimeInput.text.trim(),
            endTimeInput.text.trim(),
            allDayToggle.checked,
            ""
        );
        newTitleInput.text = "";
    }

    function createEvent(title, dateKey, start, end, allDay, location) {
        var tempId = "local-" + Date.now();
        var ev = {
            id: tempId,
            calendarId: "primary",
            calendarName: "Personal",
            color: calendarPopup.root.indigo,
            dateKey: dateKey,
            start: allDay ? dateKey : dateKey + "T" + start + ":00",
            end: allDay ? dateKey : dateKey + "T" + end + ":00",
            allDay: allDay,
            title: title,
            location: location || "",
            meetingUrl: "",
            eventUrl: ""
        };
        var evList = calendarPopup.allEvents.slice();
        evList.push(ev);
        calendarPopup.allEvents = evList;
        calendarPopup.eventIndex = CalendarModel.indexEventsByDate(evList);
        calendarPopup.creatingEvent = false;

        var cmd = ["python3", calendarPopup.actionScript, "create", "--calendar", "primary", "--title", title, "--date", dateKey];
        if (allDay) {
            cmd.push("--all-day");
        } else {
            cmd.push("--start", start, "--end", end);
        }
        if (location) cmd.push("--location", location);
        actionProcess.command = cmd;
        actionProcess.running = false;
        actionProcess.running = true;
    }

    function deleteEvent(calId, eventId) {
        var evList = calendarPopup.allEvents.filter(function(e) { return e.id !== eventId; });
        calendarPopup.allEvents = evList;
        calendarPopup.eventIndex = CalendarModel.indexEventsByDate(evList);

        actionProcess.command = ["python3", calendarPopup.actionScript, "delete", "--calendar", calId || "primary", "--id", eventId];
        actionProcess.running = false;
        actionProcess.running = true;
    }

    function editEvent(calId, eventId, title, dateKey, start, end, allDay) {
        var evList = calendarPopup.allEvents.map(function(e) {
            if (e.id === eventId) {
                var copy = Object.assign({}, e);
                copy.title = title;
                if (allDay) {
                    copy.allDay = true;
                    copy.start = dateKey;
                    copy.end = dateKey;
                } else if (start && end) {
                    copy.allDay = false;
                    copy.start = dateKey + "T" + start + ":00";
                    copy.end = dateKey + "T" + end + ":00";
                }
                return copy;
            }
            return e;
        });
        calendarPopup.allEvents = evList;
        calendarPopup.eventIndex = CalendarModel.indexEventsByDate(evList);
        calendarPopup.editingEventId = "";

        var cmd = ["python3", calendarPopup.actionScript, "edit", "--calendar", calId || "primary", "--id", eventId, "--title", title];
        if (allDay) cmd.push("--all-day");
        else if (start && end) cmd.push("--start", start, "--end", end);
        actionProcess.command = cmd;
        actionProcess.running = false;
        actionProcess.running = true;
    }

    property bool syncing: syncProcess.running || actionProcess.running

    function syncNow() {
        if (syncProcess.running) return;
        syncProcess.running = true;
    }

    Process {
        id: syncProcess
        command: ["systemctl", "--user", "start", "omarchy-calendar-sync.service"]
        running: false
        onExited: function(code) {
            eventsFile.reload();
        }
    }

    Process {
        id: actionProcess
        running: false
        onExited: function(code) {
            eventsFile.reload();
        }
    }

    function openUrl(url) {
        var safe = CalendarModel.safeUrl(url);
        if (!safe) return;
        urlOpener.command = ["xdg-open", safe];
        urlOpener.running = false;
        urlOpener.running = true;
    }

    Process {
        id: urlOpener
        running: false
    }

    FileView {
        id: eventsFile
        path: calendarPopup.eventsPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                var doc = JSON.parse(text());
                calendarPopup.eventDoc = doc;
                calendarPopup.allEvents = (doc && doc.events) ? doc.events : [];
                calendarPopup.eventIndex = CalendarModel.indexEventsByDate(calendarPopup.allEvents);
            } catch (e) {
                calendarPopup.eventDoc = null;
                calendarPopup.allEvents = [];
                calendarPopup.eventIndex = ({});
            }
        }
        onLoadFailed: {
            calendarPopup.eventDoc = null;
            calendarPopup.allEvents = [];
            calendarPopup.eventIndex = ({});
        }
        onFileChanged: reload()
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            calendarPopup.today = new Date();
            calendarPopup.nowMs = Date.now();
        }
    }

    theme: root
    revealed: root.calendarVisible
    cardWidth: 380
    cardHeight: -1
    layerNamespace: "omarchy-calendar"

    title: Qt.locale().standaloneMonthName(viewMonth, Locale.LongFormat).toUpperCase()
    subtitle: upcomingEvent
        ? "NEXT: " + upcomingEvent.title.toUpperCase() + " (" + countdownPhrase + ")"
        : String(viewYear)

    anchorEdge: calendarPopup.root.barEdge
    anchorBarX: calendarPopup.root.popupAnchorX
    anchorBarY: calendarPopup.root.popupAnchorY

    headerRight: Row {
        spacing: 8

        Item {
            width: 22
            height: 22
            CalendarChevron {
                anchors.centerIn: parent
                root: calendarPopup.root
                text: String.fromCodePoint(0xf104)
                hotColor: calendarPopup.root.seal
                font.pixelSize: 18
                onTriggered: {
                    calendarPopup.root.calendarMonthOffset--;
                    calendarPopup.root.calendarTick++;
                }
            }
        }

        Item {
            width: 22
            height: 22
            CalendarChevron {
                anchors.centerIn: parent
                root: calendarPopup.root
                text: "•"
                restColor: calendarPopup.root.inkDeep
                hotColor: calendarPopup.root.seal
                font.pixelSize: 16
                onTriggered: {
                    calendarPopup.root.calendarMonthOffset = 0;
                    calendarPopup.root.calendarTick++;
                    calendarPopup.selectedDateKey = calendarPopup.todayKey;
                }
            }
        }

        Item {
            width: 22
            height: 22
            CalendarChevron {
                anchors.centerIn: parent
                root: calendarPopup.root
                text: String.fromCodePoint(0xf105)
                hotColor: calendarPopup.root.seal
                font.pixelSize: 18
                onTriggered: {
                    calendarPopup.root.calendarMonthOffset++;
                    calendarPopup.root.calendarTick++;
                }
            }
        }

        Item {
            width: 22
            height: 22
            CalendarChevron {
                id: syncBtn
                anchors.centerIn: parent
                root: calendarPopup.root
                text: calendarPopup.root.icoRefresh
                restColor: calendarPopup.syncing ? calendarPopup.root.seal : calendarPopup.root.inkDeep
                hotColor: calendarPopup.root.seal
                font.pixelSize: 18
                opacity: calendarPopup.syncing ? 0.7 : 1.0
                onTriggered: calendarPopup.syncNow()

                RotationAnimator on rotation {
                    from: 0
                    to: 360
                    duration: 800
                    loops: Animation.Infinite
                    running: calendarPopup.syncing
                }
            }
        }
    }

    onDismiss: {
        calendarPopup.root.calendarVisible = false;
        calendarPopup.creatingEvent = false;
        calendarPopup.editingEventId = "";
    }

    onKeyPressed: function(event) {
        var k = event.key;
        if (k === Qt.Key_Q || k === Qt.Key_Escape) {
            if (calendarPopup.creatingEvent || calendarPopup.editingEventId !== "") {
                calendarPopup.creatingEvent = false;
                calendarPopup.editingEventId = "";
            } else {
                calendarPopup.root.calendarVisible = false;
            }
            event.accepted = true;
            return;
        }
        if (calendarPopup.creatingEvent || calendarPopup.editingEventId !== "") {
            return;
        }
        if (k === Qt.Key_PageUp) {
            calendarPopup.root.calendarMonthOffset--;
            calendarPopup.root.calendarTick++;
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_PageDown) {
            calendarPopup.root.calendarMonthOffset++;
            calendarPopup.root.calendarTick++;
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_Home) {
            calendarPopup.root.calendarMonthOffset = 0;
            calendarPopup.root.calendarTick++;
            calendarPopup.selectedDateKey = calendarPopup.todayKey;
            event.accepted = true;
            return;
        }
        if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down) {
            var curDate = CalendarModel.dateFromKey(calendarPopup.selectedDateKey, calendarPopup.today);
            var delta = 0;
            if (k === Qt.Key_Left) delta = -1;
            else if (k === Qt.Key_Right) delta = 1;
            else if (k === Qt.Key_Up) delta = -7;
            else if (k === Qt.Key_Down) delta = 7;
            curDate.setDate(curDate.getDate() + delta);
            calendarPopup.selectedDateKey = CalendarModel.keyForDate(curDate);
            event.accepted = true;
            return;
        }
    }

    Column {
        width: parent.width
        spacing: 12

        // Weekday header row
        Row {
            width: parent.width
            spacing: 0

            Repeater {
                model: ["MO","TU","WE","TH","FR","SA","SU"]
                delegate: Item {
                    required property string modelData
                    required property int index
                    width: parent.width / 7
                    height: 20
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: index >= 5 ? calendarPopup.root.seal : calendarPopup.root.inkDeep
                        opacity: index >= 5 ? 0.85 : 0.65
                        font.family: calendarPopup.root.mono
                        font.pixelSize: 11
                        font.letterSpacing: 1.5
                    }
                }
            }
        }

        // 6-Row Month Grid
        Column {
            width: parent.width
            spacing: 2

            Repeater {
                id: weekRepeater
                model: CalendarModel.monthGrid(calendarPopup.viewYear, calendarPopup.viewMonth, 1, calendarPopup.todayKey, calendarPopup.eventIndex)

                Row {
                    required property var modelData
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: modelData.days

                        Item {
                            id: dayCell
                            required property var modelData
                            width: parent.width / 7
                            height: 34

                            readonly property bool isToday: modelData.today
                            readonly property bool isSelected: modelData.key === calendarPopup.selectedDateKey
                            readonly property bool inMonth: modelData.inMonth
                            readonly property bool isWeekend: modelData.weekend
                            readonly property var dots: modelData.dots || []

                            // Today background circle
                            Rectangle {
                                anchors.centerIn: parent
                                width: 28
                                height: 28
                                radius: 14
                                color: calendarPopup.root.seal
                                visible: dayCell.isToday
                                antialiasing: true
                            }

                            // Selection outline
                            Rectangle {
                                anchors.centerIn: parent
                                width: 28
                                height: 28
                                radius: 14
                                color: dayMouse.containsMouse && !dayCell.isToday
                                    ? Qt.rgba(calendarPopup.root.ink.r, calendarPopup.root.ink.g, calendarPopup.root.ink.b, 0.08)
                                    : "transparent"
                                border.color: dayCell.isSelected && !dayCell.isToday ? calendarPopup.root.ink : "transparent"
                                border.width: 1
                                antialiasing: true
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 1

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: dayCell.modelData.day
                                    color: dayCell.isToday
                                        ? (calendarPopup.root.seal.hsvValue < 0.5 ? calendarPopup.root.ink : calendarPopup.root.paper)
                                        : (dayCell.inMonth
                                            ? (dayCell.isWeekend ? calendarPopup.root.seal : calendarPopup.root.ink)
                                            : calendarPopup.root.sumi)
                                    opacity: dayCell.inMonth ? 1.0 : 0.3
                                    font.family: calendarPopup.root.mono
                                    font.pixelSize: 13
                                    font.weight: dayCell.isToday || dayCell.isSelected ? Font.Medium : Font.Normal
                                }

                                // Event indicator dots
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    spacing: 2
                                    visible: dayCell.dots.length > 0

                                    Repeater {
                                        model: dayCell.dots
                                        Rectangle {
                                            required property var modelData
                                            width: 4
                                            height: 4
                                            radius: 2
                                            color: modelData
                                            opacity: dayCell.isToday ? 0.9 : 1.0
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: dayMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    calendarPopup.selectedDateKey = dayCell.modelData.key;
                                    calendarPopup.creatingEvent = false;
                                    calendarPopup.editingEventId = "";
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: calendarPopup.root.sep
        }

        // Agenda Section for Selected Date
        Column {
            width: parent.width
            spacing: 8

            // Section Header with Date and Add (+) Button
            Item {
                width: parent.width
                height: 20

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        text: Qt.formatDate(calendarPopup.selectedDateObj, "d MMMM yyyy").toUpperCase()
                        color: calendarPopup.root.ink
                        font.family: calendarPopup.root.mono
                        font.pixelSize: 11
                        font.letterSpacing: 2
                        font.weight: Font.Medium
                    }

                    Text {
                        text: calendarPopup.selectedEvents.length > 0
                            ? "·  " + calendarPopup.selectedEvents.length + " EVENT" + (calendarPopup.selectedEvents.length === 1 ? "" : "S")
                            : ""
                        color: calendarPopup.root.inkDeep
                        font.family: calendarPopup.root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 1.5
                        opacity: 0.8
                    }
                }

                // Add Event (+) Button matching Date Header font size
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: calendarPopup.creatingEvent ? "✕" : "+"
                    color: addMouse.containsMouse || calendarPopup.creatingEvent ? calendarPopup.root.seal : calendarPopup.root.ink
                    font.family: calendarPopup.root.mono
                    font.pixelSize: 11
                    font.letterSpacing: 2
                    font.weight: Font.Medium

                    MouseArea {
                        id: addMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            calendarPopup.creatingEvent = !calendarPopup.creatingEvent;
                            calendarPopup.editingEventId = "";
                            if (calendarPopup.creatingEvent) {
                                newTitleInput.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // Inline Add Event Form Card
            Rectangle {
                visible: calendarPopup.creatingEvent
                width: parent.width
                implicitHeight: addFormCol.implicitHeight + 16
                radius: calendarPopup.root.cornerRadius
                color: Qt.rgba(calendarPopup.root.ink.r, calendarPopup.root.ink.g, calendarPopup.root.ink.b, 0.04)
                border.color: calendarPopup.root.sep
                border.width: 1

                Column {
                    id: addFormCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 8

                    // Title Input
                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: calendarPopup.root.cornerRadius
                        color: Qt.rgba(calendarPopup.root.bg.r, calendarPopup.root.bg.g, calendarPopup.root.bg.b, 0.6)
                        border.color: newTitleInput.activeFocus ? calendarPopup.root.seal : calendarPopup.root.sep
                        border.width: 1

                        TextInput {
                            id: newTitleInput
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            color: calendarPopup.root.ink
                            font.family: calendarPopup.root.mono
                            font.pixelSize: 11
                            clip: true
                            onAccepted: calendarPopup.submitNewEvent()

                            Text {
                                visible: !newTitleInput.text && !newTitleInput.activeFocus
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "Event title..."
                                color: calendarPopup.root.sumi
                                font.family: calendarPopup.root.mono
                                font.pixelSize: 11
                                opacity: 0.6
                            }
                        }
                    }

                    // Times & All-Day Toggle
                    Row {
                        width: parent.width
                        spacing: 8
                        visible: !allDayToggle.checked

                        Rectangle {
                            width: 60
                            height: 24
                            radius: calendarPopup.root.cornerRadius
                            color: Qt.rgba(calendarPopup.root.bg.r, calendarPopup.root.bg.g, calendarPopup.root.bg.b, 0.6)
                            border.color: startTimeInput.activeFocus ? calendarPopup.root.seal : calendarPopup.root.sep
                            border.width: 1

                            TextInput {
                                id: startTimeInput
                                anchors.fill: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: "09:00"
                                color: calendarPopup.root.ink
                                font.family: calendarPopup.root.mono
                                font.pixelSize: 11
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "to"
                            color: calendarPopup.root.inkDeep
                            font.family: calendarPopup.root.mono
                            font.pixelSize: 10
                        }

                        Rectangle {
                            width: 60
                            height: 24
                            radius: calendarPopup.root.cornerRadius
                            color: Qt.rgba(calendarPopup.root.bg.r, calendarPopup.root.bg.g, calendarPopup.root.bg.b, 0.6)
                            border.color: endTimeInput.activeFocus ? calendarPopup.root.seal : calendarPopup.root.sep
                            border.width: 1

                            TextInput {
                                id: endTimeInput
                                anchors.fill: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: "10:00"
                                color: calendarPopup.root.ink
                                font.family: calendarPopup.root.mono
                                font.pixelSize: 11
                            }
                        }
                    }

                    // Bottom Row: All-Day and Save/Cancel Actions
                    Row {
                        width: parent.width

                        Item {
                            width: parent.width - actionBtnRow.width
                            height: 24

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Rectangle {
                                    id: allDayToggle
                                    property bool checked: false
                                    width: 14
                                    height: 14
                                    radius: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: checked ? calendarPopup.root.seal : "transparent"
                                    border.color: calendarPopup.root.seal
                                    border.width: 1

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: allDayToggle.checked = !allDayToggle.checked
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "ALL DAY"
                                    color: calendarPopup.root.inkDeep
                                    font.family: calendarPopup.root.mono
                                    font.pixelSize: 9
                                    font.letterSpacing: 1
                                }
                            }
                        }

                        Row {
                            id: actionBtnRow
                            spacing: 6

                            Rectangle {
                                width: 56
                                height: 24
                                radius: calendarPopup.root.cornerRadius
                                color: cancelBtnMouse.containsMouse
                                    ? Qt.rgba(calendarPopup.root.ink.r, calendarPopup.root.ink.g, calendarPopup.root.ink.b, 0.1)
                                    : "transparent"
                                border.color: calendarPopup.root.sep
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "CANCEL"
                                    color: calendarPopup.root.inkDeep
                                    font.family: calendarPopup.root.mono
                                    font.pixelSize: 9
                                    font.letterSpacing: 1
                                }

                                MouseArea {
                                    id: cancelBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        calendarPopup.creatingEvent = false;
                                        newTitleInput.text = "";
                                    }
                                }
                            }

                            Rectangle {
                                width: 48
                                height: 24
                                radius: calendarPopup.root.cornerRadius
                                color: saveBtnMouse.containsMouse ? calendarPopup.root.seal : calendarPopup.root.indigo

                                Text {
                                    anchors.centerIn: parent
                                    text: "SAVE"
                                    color: calendarPopup.root.paper
                                    font.family: calendarPopup.root.mono
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1
                                }

                                MouseArea {
                                    id: saveBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: calendarPopup.submitNewEvent()
                                }
                            }
                        }
                    }
                }
            }

            // Empty State
            Text {
                visible: calendarPopup.selectedEvents.length === 0 && !calendarPopup.creatingEvent
                width: parent.width
                text: "No events scheduled"
                color: calendarPopup.root.sumi
                font.family: calendarPopup.root.mono
                font.pixelSize: 11
                font.letterSpacing: 1
                opacity: 0.6
                topPadding: 4
                bottomPadding: 4
            }

            // Event Rows
            Repeater {
                model: calendarPopup.selectedEvents

                Rectangle {
                    id: eventRow
                    required property var modelData
                    width: parent.width
                    height: calendarPopup.editingEventId === eventRow.modelData.id ? editFormCol.implicitHeight + 16 : 44
                    radius: calendarPopup.root.cornerRadius
                    color: eventRow.isHovered || calendarPopup.editingEventId === eventRow.modelData.id
                        ? Qt.rgba(calendarPopup.root.ink.r, calendarPopup.root.ink.g, calendarPopup.root.ink.b, 0.05)
                        : "transparent"

                    readonly property bool isHovered: rowMouse.containsMouse
                        || editBtnMouse.containsMouse
                        || deleteBtnMouse.containsMouse
                        || (joinBtn.visible && joinMouse.containsMouse)

                    // Full-row background click area for opening meeting/event URL
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: eventRow.modelData.eventUrl ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (eventRow.modelData.eventUrl) calendarPopup.openUrl(eventRow.modelData.eventUrl);
                        }
                    }

                    // Left Calendar Indicator Bar
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 4
                        anchors.bottomMargin: 4
                        width: 3
                        radius: 1.5
                        color: eventRow.modelData.color || calendarPopup.root.indigo
                    }

                    // Standard Display View
                    Item {
                        visible: calendarPopup.editingEventId !== eventRow.modelData.id
                        anchors.fill: parent

                        // Text column with fixed right margin so geometry is rock-solid
                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: (eventRow.modelData.meetingUrl ? 116 : 64)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: eventRow.modelData.title || "(No title)"
                                color: calendarPopup.root.ink
                                font.family: calendarPopup.root.mono
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: CalendarModel.formatTimeRange(eventRow.modelData.start, eventRow.modelData.end, eventRow.modelData.allDay)
                                      + (eventRow.modelData.location ? "  ·  " + eventRow.modelData.location : "")
                                color: calendarPopup.root.inkDeep
                                font.family: calendarPopup.root.mono
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                opacity: 0.8
                            }
                        }

                        // Action Buttons: Edit, Delete, Join (layered on top with z: 2)
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            z: 2

                            // Edit Icon Button with smooth fade
                            Rectangle {
                                width: 22
                                height: 22
                                radius: calendarPopup.root.cornerRadius
                                opacity: eventRow.isHovered ? 1.0 : 0.0
                                enabled: eventRow.isHovered
                                color: editBtnMouse.containsMouse
                                    ? Qt.rgba(calendarPopup.root.ink.r, calendarPopup.root.ink.g, calendarPopup.root.ink.b, 0.12)
                                    : "transparent"

                                Behavior on opacity {
                                    NumberAnimation { duration: 120 }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(0xf044)
                                    color: editBtnMouse.containsMouse ? calendarPopup.root.seal : calendarPopup.root.inkDeep
                                    font.family: calendarPopup.root.mono
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: editBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        calendarPopup.editingEventId = eventRow.modelData.id;
                                        editTitleInput.text = eventRow.modelData.title || "";
                                    }
                                }
                            }

                            // Delete Icon Button with smooth fade
                            Rectangle {
                                width: 22
                                height: 22
                                radius: calendarPopup.root.cornerRadius
                                opacity: eventRow.isHovered ? 1.0 : 0.0
                                enabled: eventRow.isHovered
                                color: deleteBtnMouse.containsMouse
                                    ? Qt.rgba(calendarPopup.root.seal.r, calendarPopup.root.seal.g, calendarPopup.root.seal.b, 0.2)
                                    : "transparent"

                                Behavior on opacity {
                                    NumberAnimation { duration: 120 }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(0xf1f8)
                                    color: deleteBtnMouse.containsMouse ? calendarPopup.root.seal : calendarPopup.root.inkDeep
                                    font.family: calendarPopup.root.mono
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    id: deleteBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: calendarPopup.deleteEvent(eventRow.modelData.calendarId || "primary", eventRow.modelData.id)
                                }
                            }

                            // One-click Join Button
                            Rectangle {
                                id: joinBtn
                                visible: !!eventRow.modelData.meetingUrl
                                width: 48
                                height: 22
                                radius: calendarPopup.root.cornerRadius
                                color: joinMouse.containsMouse
                                    ? calendarPopup.root.indigo
                                    : Qt.rgba(calendarPopup.root.indigo.r, calendarPopup.root.indigo.g, calendarPopup.root.indigo.b, 0.2)
                                border.color: calendarPopup.root.indigo
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "JOIN"
                                    color: joinMouse.containsMouse ? calendarPopup.root.paper : calendarPopup.root.indigo
                                    font.family: calendarPopup.root.mono
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1
                                }

                                MouseArea {
                                    id: joinMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: calendarPopup.openUrl(eventRow.modelData.meetingUrl)
                                }
                            }
                        }
                    }

                    // Inline Edit Mode View
                    Column {
                        id: editFormCol
                        visible: calendarPopup.editingEventId === eventRow.modelData.id
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        anchors.leftMargin: 12
                        spacing: 6
                        z: 3

                        Rectangle {
                            width: parent.width
                            height: 26
                            radius: calendarPopup.root.cornerRadius
                            color: Qt.rgba(calendarPopup.root.bg.r, calendarPopup.root.bg.g, calendarPopup.root.bg.b, 0.6)
                            border.color: editTitleInput.activeFocus ? calendarPopup.root.seal : calendarPopup.root.sep
                            border.width: 1

                            TextInput {
                                id: editTitleInput
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                verticalAlignment: Text.AlignVCenter
                                color: calendarPopup.root.ink
                                font.family: calendarPopup.root.mono
                                font.pixelSize: 11
                                text: eventRow.modelData.title || ""
                            }
                        }

                        Row {
                            spacing: 6
                            anchors.right: parent.right

                            Rectangle {
                                width: 50
                                height: 22
                                radius: calendarPopup.root.cornerRadius
                                color: "transparent"
                                border.color: calendarPopup.root.sep
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "CANCEL"
                                    color: calendarPopup.root.inkDeep
                                    font.family: calendarPopup.root.mono
                                    font.pixelSize: 9
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: calendarPopup.editingEventId = ""
                                }
                            }

                            Rectangle {
                                width: 44
                                height: 22
                                radius: calendarPopup.root.cornerRadius
                                color: calendarPopup.root.seal

                                Text {
                                    anchors.centerIn: parent
                                    text: "SAVE"
                                    color: calendarPopup.root.paper
                                    font.family: calendarPopup.root.mono
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        calendarPopup.editEvent(
                                            eventRow.modelData.calendarId || "primary",
                                            eventRow.modelData.id,
                                            editTitleInput.text.trim(),
                                            eventRow.modelData.dateKey,
                                            "",
                                            "",
                                            eventRow.modelData.allDay
                                        );
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
