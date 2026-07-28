import QtQuick

CardWindow {
    id: screenshotsPopup
    required property var root

    theme: root
    revealed: root.screenshotsVisible
    cardWidth: 566
    layerNamespace: "omarchy-screenshots"
    title: "SCREENSHOTS"
    subtitle: screenshotsPopup.root.screenshotFiles.length === 0
              ? "NO RECENT CAPTURES"
              : "PAGE " + (screenshotsPopup.root.screenshotPage + 1) + " / " + screenshotsPopup.root.screenshotPageCount
                + "  ·  " + screenshotsPopup.root.screenshotFiles.length + " TOTAL"

    headerRight: Row {
        spacing: 12
        CalendarChevron {
            root: screenshotsPopup.root
            text: "‹"
            opacity: screenshotsPopup.root.screenshotPage > 0 ? 1.0 : 0.3
            onTriggered: {
                if (screenshotsPopup.root.screenshotPage > 0) {
                    screenshotsPopup.root.screenshotPage--;
                    screenshotsPopup.root.selectedScreenshot = 0;
                }
            }
        }
        CalendarChevron {
            root: screenshotsPopup.root
            text: screenshotsPopup.root.icoRefresh
            restColor: screenshotsPopup.root.inkDeep
            font.pixelSize: 24
            onTriggered: screenshotsPopup.root.refreshScreenshots()
        }
        CalendarChevron {
            root: screenshotsPopup.root
            text: "›"
            opacity: screenshotsPopup.root.screenshotPage < screenshotsPopup.root.screenshotPageCount - 1 ? 1.0 : 0.3
            onTriggered: {
                if (screenshotsPopup.root.screenshotPage < screenshotsPopup.root.screenshotPageCount - 1) {
                    screenshotsPopup.root.screenshotPage++;
                    screenshotsPopup.root.selectedScreenshot = 0;
                }
            }
        }
    }

    onDismiss: screenshotsPopup.root.screenshotsVisible = false
    onKeyPressed: function(event) {
        const r = screenshotsPopup.root;
        const k = event.key;
        if (k === Qt.Key_Q) {
            r.screenshotsVisible = false;
        } else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_Tab) {
            r.moveScreenshotSelection(1);
        } else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_Backtab) {
            r.moveScreenshotSelection(-1);
        } else if (k === Qt.Key_Down || k === Qt.Key_J) {
            r.moveScreenshotRow(1);
        } else if (k === Qt.Key_Up || k === Qt.Key_K) {
            r.moveScreenshotRow(-1);
        } else if (k === Qt.Key_N) {
            r.pageScreenshots(1);
        } else if (k === Qt.Key_P) {
            r.pageScreenshots(-1);
        } else if (k === Qt.Key_O || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            const e = r.selectedScreenshotEntry;
            if (e) {
                r.run("xdg-open " + JSON.stringify(e.path));
                r.screenshotsVisible = false;
            }
        } else if (k === Qt.Key_C) {
            const e = r.selectedScreenshotEntry;
            if (e) r.copyScreenshotToClipboard(e.path);
        } else {
            return;
        }
        event.accepted = true;
    }

    Column {
        id: shotCol
        width: parent.width
        spacing: 12

        Text {
            width: parent.width
            height: 248
            visible: screenshotsPopup.root.screenshotFiles.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "~/Pictures/screenshot-*.png"
            color: screenshotsPopup.root.inkDeep
            font.family: screenshotsPopup.root.mono
            font.pixelSize: 11
            font.letterSpacing: 2
            opacity: 0.6
        }

        Grid {
            columns: 4
            rowSpacing: 6
            columnSpacing: 6
            width: parent.width
            visible: screenshotsPopup.root.screenshotFiles.length > 0

            Repeater {
                // 12 slots regardless of page fill so the grid keeps its
                // silhouette on a partial last page.
                model: screenshotsPopup.root.screenshotsPerPage
                delegate: Item {
                    id: shotCell
                    required property int index
                    readonly property var entry: screenshotsPopup.root.visibleScreenshots[index] || null
                    readonly property bool filled: entry !== null
                    readonly property bool isSelected: filled && screenshotsPopup.root.selectedScreenshot === index
                    readonly property bool justCopied: filled && screenshotsPopup.root.copiedPath === entry.path

                    width: (shotCol.width - 18) / 4
                    height: width * 9 / 16

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(screenshotsPopup.root.ink.r, screenshotsPopup.root.ink.g, screenshotsPopup.root.ink.b, shotCell.filled ? 0.04 : 0.02)
                        border.color: shotCell.isSelected ? screenshotsPopup.root.seal : screenshotsPopup.root.sep
                        border.width: 1
                        antialiasing: true
                    }

                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: shotCell.filled
                        // Source gated on popup visibility so the QQuickPixmapCache
                        // drops decoded bitmaps when the widget is hidden.
                        source: (shotCell.filled && screenshotsPopup.root.screenshotsVisible)
                                ? "file://" + shotCell.entry.path : ""
                        sourceSize.width: 256
                        sourceSize.height: 144
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        clip: true
                        opacity: shotMouse.containsMouse || shotCell.isSelected ? 1.0 : 0.85
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        color: "transparent"
                        border.color: screenshotsPopup.root.seal
                        border.width: shotMouse.containsMouse && !shotCell.isSelected ? 1 : 0
                        visible: shotCell.filled
                        antialiasing: true
                        Behavior on border.width { NumberAnimation { duration: 120 } }
                    }

                    // Snap-on / fade-out so the ack reads even from peripheral
                    // vision; copiedReset clears root.copiedPath after 1.4s.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        color: Qt.rgba(screenshotsPopup.root.seal.r, screenshotsPopup.root.seal.g, screenshotsPopup.root.seal.b, 0.28)
                        border.color: screenshotsPopup.root.seal
                        border.width: 2
                        visible: opacity > 0.01
                        opacity: shotCell.justCopied ? 1 : 0
                        antialiasing: true
                        Behavior on opacity {
                            NumberAnimation {
                                duration: shotCell.justCopied ? 80 : 600
                                easing.type: shotCell.justCopied ? Easing.OutQuad : Easing.InCubic
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "COPIED"
                            color: screenshotsPopup.root.seal.hsvValue < 0.5 ? screenshotsPopup.root.ink : screenshotsPopup.root.paper
                            font.family: screenshotsPopup.root.mono
                            font.pixelSize: 11
                            font.letterSpacing: 3
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: shotMouse
                        anchors.fill: parent
                        hoverEnabled: shotCell.filled
                        enabled: shotCell.filled
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onEntered: screenshotsPopup.root.selectedScreenshot = shotCell.index
                        onClicked: (e) => {
                            screenshotsPopup.root.selectedScreenshot = shotCell.index;
                            if (e.button === Qt.RightButton) {
                                screenshotsPopup.root.copyScreenshotToClipboard(shotCell.entry.path);
                            } else {
                                screenshotsPopup.root.run("xdg-open " + JSON.stringify(shotCell.entry.path));
                                screenshotsPopup.root.screenshotsVisible = false;
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: screenshotsPopup.root.sep
            visible: screenshotsPopup.root.selectedScreenshotEntry !== null
        }

        Item {
            width: parent.width
            height: 22
            visible: screenshotsPopup.root.selectedScreenshotEntry !== null

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: screenshotsPopup.root.selectedScreenshotEntry ? screenshotsPopup.root.selectedScreenshotEntry.label : ""
                color: screenshotsPopup.root.ink
                font.family: screenshotsPopup.root.mono
                font.pixelSize: 11
                font.letterSpacing: 2
            }

            Text {
                readonly property bool copied: screenshotsPopup.root.copiedPath !== ""
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: copied ? "COPIED TO CLIPBOARD" : "RIGHT-CLICK TO COPY"
                color: copied ? screenshotsPopup.root.seal : screenshotsPopup.root.inkDeep
                font.family: screenshotsPopup.root.mono
                font.pixelSize: 11
                font.letterSpacing: 2
                opacity: copied ? 1.0 : 0.7
                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
        }
    }
}
