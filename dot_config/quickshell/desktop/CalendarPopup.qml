import QtQuick

CardWindow {
    id: calendarPopup
    required property var root
    readonly property bool isWhiterose: root.barVariant === "whiterose"
    readonly property int wrGap: 4

    function cleanDetail(text) {
        return String(text || "").replace(" · ", " - ");
    }

    theme: root
    plain: calendarPopup.isWhiterose
    revealed: root.calendarVisible
    cardWidth: calendarPopup.isWhiterose ? 344 : 322
    layerNamespace: "omarchy-calendar"
    title: calendarPopup.root.calendarMonthName
    subtitle: calendarPopup.root.calendarYear

    anchorEdge: calendarPopup.root.barEdge
    anchorBarX: calendarPopup.root.popupAnchorX
    anchorBarY: calendarPopup.root.popupAnchorY

    headerRight: Row {
        spacing: calendarPopup.isWhiterose ? 10 : 12
        CalendarChevron {
            root: calendarPopup.root
            text: calendarPopup.isWhiterose ? "<" : "‹"
            hotColor: calendarPopup.isWhiterose ? calendarPopup.root.ink : calendarPopup.root.seal
            font.pixelSize: calendarPopup.isWhiterose ? 14 : 24
            onTriggered: { calendarPopup.root.calendarMonthOffset--; calendarPopup.root.calendarTick++; calendarPopup.root.selectedDay = 0; }
        }
        CalendarChevron {
            root: calendarPopup.root
            text: calendarPopup.isWhiterose ? "TODAY" : "•"
            restColor: calendarPopup.root.inkDeep
            hotColor: calendarPopup.isWhiterose ? calendarPopup.root.ink : calendarPopup.root.seal
            font.pixelSize: calendarPopup.isWhiterose ? 10 : 19
            font.letterSpacing: calendarPopup.isWhiterose ? 2 : 0
            onTriggered: { calendarPopup.root.calendarMonthOffset = 0; calendarPopup.root.calendarTick++; calendarPopup.root.selectedDay = (new Date()).getDate(); }
        }
        CalendarChevron {
            root: calendarPopup.root
            text: calendarPopup.isWhiterose ? ">" : "›"
            hotColor: calendarPopup.isWhiterose ? calendarPopup.root.ink : calendarPopup.root.seal
            font.pixelSize: calendarPopup.isWhiterose ? 14 : 24
            onTriggered: { calendarPopup.root.calendarMonthOffset++; calendarPopup.root.calendarTick++; calendarPopup.root.selectedDay = 0; }
        }
    }

    onDismiss: calendarPopup.root.calendarVisible = false
    onKeyPressed: function(event) {
        if (event.key === Qt.Key_Q) {
            calendarPopup.root.calendarVisible = false;
            event.accepted = true;
        }
    }

    Column {
        width: parent.width
        spacing: calendarPopup.isWhiterose ? 10 : 12

        Rectangle {
            width: parent.width
            height: calendarPopup.isWhiterose ? 2 : 1
            color: calendarPopup.root.sep
        }

        Row {
            width: parent.width
            spacing: 0

            Repeater {
                model: ["MO","TU","WE","TH","FR","SA","SU"]
                delegate: Item {
                    required property string modelData
                    required property int index
                    width: parent.width / 7
                    height: calendarPopup.isWhiterose ? 18 : 22
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: calendarPopup.isWhiterose
                               ? calendarPopup.root.inkDeep
                               : (index >= 5 ? calendarPopup.root.seal : calendarPopup.root.inkDeep)
                        opacity: calendarPopup.isWhiterose ? 0.8 : (index >= 5 ? 0.85 : 0.7)
                        font.family: calendarPopup.root.mono
                        font.pixelSize: calendarPopup.isWhiterose ? 10 : 12
                        font.letterSpacing: calendarPopup.isWhiterose ? 1.5 : 2
                    }
                }
            }
        }

        Grid {
            columns: 7
            rowSpacing: calendarPopup.isWhiterose ? calendarPopup.wrGap : 2
            columnSpacing: calendarPopup.isWhiterose ? calendarPopup.wrGap : 0
            width: parent.width

            Repeater {
                model: calendarPopup.root.calendarCells
                delegate: Item {
                    id: dayCell
                    required property var modelData
                    required property int index
                    width: calendarPopup.isWhiterose
                           ? (parent.width - 6 * calendarPopup.wrGap) / 7
                           : parent.width / 7
                    height: calendarPopup.isWhiterose ? 36 : 34

                    readonly property int  dayOfWeek: index % 7
                    readonly property bool isWeekend: dayOfWeek >= 5
                    readonly property bool isCurrentMonth: modelData.day !== 0
                    readonly property bool isToday: modelData.today
                    readonly property bool isHoliday: modelData.holiday !== ""
                    readonly property bool isSelected: isCurrentMonth && calendarPopup.root.selectedDay === modelData.day

                    readonly property color textColor: {
                        if (calendarPopup.isWhiterose && isToday) return calendarPopup.root.bg;
                        if (isToday) return calendarPopup.root.seal.hsvValue < 0.5 ? calendarPopup.root.ink : calendarPopup.root.paper;
                        if (!isCurrentMonth) return calendarPopup.root.inkDeep;
                        if (calendarPopup.isWhiterose) return (isWeekend || isHoliday) ? calendarPopup.root.inkDeep : calendarPopup.root.ink;
                        return (isWeekend || isHoliday) ? calendarPopup.root.seal : calendarPopup.root.ink;
                    }

                    Rectangle {
                        visible: calendarPopup.isWhiterose && dayCell.isCurrentMonth
                        anchors.fill: parent
                        color: dayCell.isToday ? calendarPopup.root.ink
                              : (dayCell.isSelected || dayMouse.containsMouse
                                 ? Qt.rgba(calendarPopup.root.ink.r, calendarPopup.root.ink.g, calendarPopup.root.ink.b, 0.06)
                                 : "transparent")
                        border.width: dayCell.isToday || dayCell.isSelected ? 2 : 1
                        border.color: dayCell.isToday || dayCell.isSelected ? calendarPopup.root.ink : calendarPopup.root.sep
                    }

                    Rectangle {
                        visible: calendarPopup.isWhiterose && dayCell.isHoliday && dayCell.isCurrentMonth && !dayCell.isToday
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 5
                        anchors.rightMargin: 5
                        anchors.bottomMargin: 5
                        height: 2
                        color: calendarPopup.root.sep
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: calendarPopup.isWhiterose ? 32 : 29
                        height: calendarPopup.isWhiterose ? 28 : 29
                        radius: calendarPopup.isWhiterose ? 0 : 14
                        color: calendarPopup.isWhiterose ? calendarPopup.root.ink : calendarPopup.root.seal
                        visible: !calendarPopup.isWhiterose && dayCell.isToday
                        antialiasing: true
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: calendarPopup.isWhiterose ? 32 : 29
                        height: calendarPopup.isWhiterose ? 28 : 29
                        radius: calendarPopup.isWhiterose ? 0 : 14
                        color: Qt.rgba(calendarPopup.root.ink.r, calendarPopup.root.ink.g, calendarPopup.root.ink.b, calendarPopup.isWhiterose ? 0.06 : 0.08)
                        visible: !calendarPopup.isWhiterose && dayMouse.containsMouse && !dayCell.isToday && dayCell.isCurrentMonth
                        antialiasing: true
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: calendarPopup.isWhiterose ? 32 : 29
                        height: calendarPopup.isWhiterose ? 28 : 29
                        radius: calendarPopup.isWhiterose ? 0 : 14
                        color: "transparent"
                        border.color: calendarPopup.isWhiterose ? calendarPopup.root.ink : calendarPopup.root.seal
                        border.width: 1
                        visible: !calendarPopup.isWhiterose && dayCell.isSelected && !dayCell.isToday
                        antialiasing: true
                    }

                    Text {
                        anchors.centerIn: parent
                        text: dayCell.modelData.day === 0 ? "" : dayCell.modelData.day
                        color: dayCell.textColor
                        opacity: dayCell.isCurrentMonth ? 1.0 : 0.35
                        font.family: calendarPopup.root.mono
                        font.pixelSize: calendarPopup.isWhiterose ? 13 : 15
                        font.weight: dayCell.isToday || (calendarPopup.isWhiterose && dayCell.isSelected) ? Font.Medium : Font.Light
                    }

                    MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: dayCell.isCurrentMonth
                        enabled: dayCell.isCurrentMonth
                        cursorShape: dayCell.isCurrentMonth
                                     ? Qt.PointingHandCursor
                                     : Qt.ArrowCursor
                        onClicked: calendarPopup.root.selectedDay = dayCell.modelData.day
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: calendarPopup.isWhiterose ? 2 : 1
            color: calendarPopup.root.sep
            visible: calendarPopup.root.selectedDay > 0
        }

        Item {
            width: parent.width
            height: calendarPopup.isWhiterose
                    ? (calendarPopup.root.selectedDayHoliday.length > 0 ? 48 : 30)
                    : selectedDetailText.implicitHeight
            visible: calendarPopup.root.selectedDay > 0

            Rectangle {
                visible: calendarPopup.isWhiterose
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: calendarPopup.root.sep
            }

            Text {
                id: selectedDetailText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: calendarPopup.isWhiterose && calendarPopup.root.selectedDayHoliday.length > 0 ? parent.top : undefined
                anchors.topMargin: calendarPopup.isWhiterose && calendarPopup.root.selectedDayHoliday.length > 0 ? 8 : 0
                anchors.verticalCenter: calendarPopup.isWhiterose && calendarPopup.root.selectedDayHoliday.length > 0 ? undefined : parent.verticalCenter
                anchors.leftMargin: calendarPopup.isWhiterose ? 9 : 0
                anchors.rightMargin: calendarPopup.isWhiterose ? 9 : 0
                text: calendarPopup.isWhiterose
                      ? calendarPopup.cleanDetail(calendarPopup.root.selectedDayDetail)
                      : calendarPopup.root.selectedDayDetail
                color: calendarPopup.root.ink
                elide: Text.ElideRight
                font.family: calendarPopup.root.mono
                font.pixelSize: calendarPopup.isWhiterose ? 10 : 11
                font.letterSpacing: calendarPopup.isWhiterose ? 1.5 : 2
                font.weight: calendarPopup.isWhiterose ? Font.Medium : Font.Normal
            }

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                visible: calendarPopup.isWhiterose && calendarPopup.root.selectedDayHoliday.length > 0
                text: calendarPopup.root.selectedDayHoliday.toUpperCase()
                color: calendarPopup.root.inkDeep
                elide: Text.ElideRight
                font.family: calendarPopup.root.mono
                font.pixelSize: 10
                font.letterSpacing: 1.4
            }
        }

        Text {
            width: parent.width
            visible: calendarPopup.root.selectedDayHoliday.length > 0 && !calendarPopup.isWhiterose
            text: calendarPopup.root.selectedDayHoliday.toUpperCase()
            color: calendarPopup.isWhiterose ? calendarPopup.root.ink : calendarPopup.root.seal
            font.family: calendarPopup.root.mono
            font.pixelSize: 11
            font.letterSpacing: 2
        }
    }
}
