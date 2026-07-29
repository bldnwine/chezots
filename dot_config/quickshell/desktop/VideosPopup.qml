import QtQuick

CardWindow {
    id: videosPopup
    required property var root

    theme: root
    revealed: root.videosVisible
    cardWidth: 566
    layerNamespace: "omarchy-videos"
    title: "VIDEOS"
    subtitle: videosPopup.root.videoFiles.length === 0
              ? "NO RECENT VIDEOS"
              : "PAGE " + (videosPopup.root.videoPage + 1) + " / " + videosPopup.root.videoPageCount
                + "  ·  " + videosPopup.root.videoFiles.length + " TOTAL"

    headerRight: Row {
        spacing: 12
        CalendarChevron {
            root: videosPopup.root
            text: "‹"
            opacity: videosPopup.root.videoPage > 0 ? 1.0 : 0.3
            onTriggered: {
                if (videosPopup.root.videoPage > 0) {
                    videosPopup.root.videoPage--;
                    videosPopup.root.selectedVideo = 0;
                }
            }
        }
        CalendarChevron {
            root: videosPopup.root
            text: videosPopup.root.icoRefresh
            restColor: videosPopup.root.inkDeep
            font.pixelSize: 24
            onTriggered: videosPopup.root.refreshVideos()
        }
        CalendarChevron {
            root: videosPopup.root
            text: "›"
            opacity: videosPopup.root.videoPage < videosPopup.root.videoPageCount - 1 ? 1.0 : 0.3
            onTriggered: {
                if (videosPopup.root.videoPage < videosPopup.root.videoPageCount - 1) {
                    videosPopup.root.videoPage++;
                    videosPopup.root.selectedVideo = 0;
                }
            }
        }
    }

    onDismiss: videosPopup.root.videosVisible = false
    onKeyPressed: function(event) {
        const r = videosPopup.root;
        const k = event.key;
        if (k === Qt.Key_Q) {
            r.videosVisible = false;
        } else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_Tab) {
            r.moveVideoSelection(1);
        } else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_Backtab) {
            r.moveVideoSelection(-1);
        } else if (k === Qt.Key_Down || k === Qt.Key_J) {
            r.moveVideoRow(1);
        } else if (k === Qt.Key_Up || k === Qt.Key_K) {
            r.moveVideoRow(-1);
        } else if (k === Qt.Key_N) {
            r.pageVideos(1);
        } else if (k === Qt.Key_P) {
            r.pageVideos(-1);
        } else if (k === Qt.Key_O || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            const e = r.selectedVideoEntry;
            if (e) {
                r.run("xdg-open " + JSON.stringify(e.path));
                r.videosVisible = false;
            }
        } else if (k === Qt.Key_C) {
            const e = r.selectedVideoEntry;
            if (e) {
                if (event.modifiers & Qt.ShiftModifier) r.copyVideoBytes(e.path);
                else r.copyVideoUri(e.path);
            }
        } else {
            return;
        }
        event.accepted = true;
    }

    Column {
        id: vidCol
        width: parent.width
        spacing: 12

        Text {
            width: parent.width
            height: 248
            visible: videosPopup.root.videoFiles.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "~/Videos/*.mp4 · mkv · webm · mov · avi · m4v"
            color: videosPopup.root.inkDeep
            font.family: videosPopup.root.mono
            font.pixelSize: 11
            font.letterSpacing: 2
            opacity: 0.6
        }

        Grid {
            columns: 4
            rowSpacing: 6
            columnSpacing: 6
            width: parent.width
            visible: videosPopup.root.videoFiles.length > 0

            Repeater {
                model: videosPopup.root.videosPerPage
                delegate: Item {
                    id: vidCell
                    required property int index
                    readonly property var entry: videosPopup.root.visibleVideos[index] || null
                    readonly property bool filled: entry !== null
                    readonly property bool isSelected: filled && videosPopup.root.selectedVideo === index
                    readonly property bool justCopied: filled && videosPopup.root.copiedVideo === entry.path

                    width: (vidCol.width - 18) / 4
                    height: width * 9 / 16

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(videosPopup.root.ink.r, videosPopup.root.ink.g, videosPopup.root.ink.b, vidCell.filled ? 0.04 : 0.02)
                        border.color: vidCell.isSelected ? videosPopup.root.seal : videosPopup.root.sep
                        border.width: 1
                        antialiasing: true
                    }

                    // Non-Ready statuses surface the fallback glyph below —
                    // covers ffmpeg failures and the race window before a
                    // fresh thumb lands on disk.
                    Image {
                        id: vidThumb
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: vidCell.filled && status === Image.Ready
                        // cache: false because the cached thumb on disk is
                        // overwritten when the source video changes; the
                        // QQuickPixmapCache would otherwise keep serving the
                        // stale decode for the session.
                        source: (vidCell.filled && videosPopup.root.videosVisible && vidCell.entry.thumb)
                                ? "file://" + vidCell.entry.thumb : ""
                        sourceSize.width: 320
                        sourceSize.height: 180
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        clip: true
                        opacity: vidMouse.containsMouse || vidCell.isSelected ? 1.0 : 0.85
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: vidCell.filled && vidThumb.status !== Image.Ready
                        text: String.fromCodePoint(0xf040a)
                        color: videosPopup.root.inkDeep
                        font.family: videosPopup.root.mono
                        font.pixelSize: 28
                        opacity: 0.55
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 4
                        width: durLabel.implicitWidth + 8
                        height: durLabel.implicitHeight + 4
                        color: Qt.rgba(videosPopup.root.paper.r, videosPopup.root.paper.g, videosPopup.root.paper.b, 0.72)
                        visible: vidCell.filled && durLabel.text.length > 0
                        radius: videosPopup.root.cornerRadius

                        Text {
                            id: durLabel
                            anchors.centerIn: parent
                            text: vidCell.filled ? videosPopup.root.formatVideoDuration(vidCell.entry.duration) : ""
                            color: videosPopup.root.ink
                            font.family: videosPopup.root.mono
                            font.pixelSize: 9
                            font.letterSpacing: 1
                            font.weight: Font.Medium
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        color: "transparent"
                        border.color: videosPopup.root.seal
                        border.width: vidMouse.containsMouse && !vidCell.isSelected ? 1 : 0
                        visible: vidCell.filled
                        antialiasing: true
                        Behavior on border.width { NumberAnimation { duration: 120 } }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        color: Qt.rgba(videosPopup.root.seal.r, videosPopup.root.seal.g, videosPopup.root.seal.b, 0.28)
                        border.color: videosPopup.root.seal
                        border.width: 2
                        visible: opacity > 0.01
                        opacity: vidCell.justCopied ? 1 : 0
                        antialiasing: true
                        Behavior on opacity {
                            NumberAnimation {
                                duration: vidCell.justCopied ? 80 : 600
                                easing.type: vidCell.justCopied ? Easing.OutQuad : Easing.InCubic
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: videosPopup.root.copiedVideoMode === "bytes" ? "BYTES COPIED" : "FILE COPIED"
                            color: videosPopup.root.seal.hsvValue < 0.5 ? videosPopup.root.ink : videosPopup.root.paper
                            font.family: videosPopup.root.mono
                            font.pixelSize: 11
                            font.letterSpacing: 3
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: vidMouse
                        anchors.fill: parent
                        hoverEnabled: vidCell.filled
                        enabled: vidCell.filled
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                        property point pressPos: Qt.point(0, 0)
                        property bool dragInitiated: false

                        onEntered: videosPopup.root.selectedVideo = vidCell.index
                        onPressed: (e) => {
                            pressPos = Qt.point(e.x, e.y);
                            dragInitiated = false;
                        }
                        onPositionChanged: (e) => {
                            if (!pressed || dragInitiated || !vidCell.filled) return;
                            if (!(e.buttons & Qt.LeftButton)) return;
                            const dx = e.x - pressPos.x;
                            const dy = e.y - pressPos.y;
                            if (dx * dx + dy * dy < 81) return;  // 9px threshold
                            dragInitiated = true;
                            videosPopup.root.selectedVideo = vidCell.index;
                            // Hyprland blocks layer-shell surfaces from being
                            // Wayland DnD sources, so we hand off to
                            // dragon-drop: a tiny xdg-toplevel that holds the
                            // file and can be dragged onto any drop target.
                            // -x exits after one accepted drop; --on-top
                            // keeps the handle above Kdenlive while you grab
                            // it. If the binary is missing the popup
                            // dismisses; right-click URI copy remains the
                            // keyboard fallback.
                            videosPopup.root.run("dragon-drop -x -T -i -s 128 "
                                + JSON.stringify(vidCell.entry.path));
                            videosPopup.root.videosVisible = false;
                        }
                        onClicked: (e) => {
                            if (dragInitiated) return;
                            videosPopup.root.selectedVideo = vidCell.index;
                            if (e.button === Qt.RightButton) {
                                videosPopup.root.copyVideoUri(vidCell.entry.path);
                            } else if (e.button === Qt.MiddleButton) {
                                videosPopup.root.copyVideoBytes(vidCell.entry.path);
                            } else {
                                videosPopup.root.run("xdg-open " + JSON.stringify(vidCell.entry.path));
                                videosPopup.root.videosVisible = false;
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: videosPopup.root.sep
            visible: videosPopup.root.selectedVideoEntry !== null
        }

        Item {
            width: parent.width
            height: 22
            visible: videosPopup.root.selectedVideoEntry !== null

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.55
                elide: Text.ElideMiddle
                text: videosPopup.root.selectedVideoEntry ? videosPopup.root.selectedVideoEntry.label : ""
                color: videosPopup.root.ink
                font.family: videosPopup.root.mono
                font.pixelSize: 11
                font.letterSpacing: 2
            }

            Text {
                readonly property bool copied: videosPopup.root.copiedVideo !== ""
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (copied) {
                        return videosPopup.root.copiedVideoMode === "bytes"
                            ? "VIDEO BYTES ON CLIPBOARD"
                            : "FILE ON CLIPBOARD";
                    }
                    if (!videosPopup.root.selectedVideoEntry) return "";
                    const e = videosPopup.root.selectedVideoEntry;
                    const bits = [];
                    const d = videosPopup.root.formatVideoDuration(e.duration); if (d) bits.push(d);
                    const s = videosPopup.root.formatVideoSize(e.size);         if (s) bits.push(s);
                    const t = videosPopup.root.formatVideoMtime(e.mtime);       if (t) bits.push(t);
                    return bits.join("  ·  ");
                }
                color: copied ? videosPopup.root.seal : videosPopup.root.inkDeep
                font.family: videosPopup.root.mono
                font.pixelSize: 11
                font.letterSpacing: 2
                opacity: copied ? 1.0 : 0.7
                Behavior on color { ColorAnimation { duration: 180 } }
                Behavior on opacity { NumberAnimation { duration: 180 } }
            }
        }
    }
}
