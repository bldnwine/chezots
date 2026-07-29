import QtQuick

// Videos detail — recent thumbs with duration badges. Keyboard:
// arrows navigate the grid, Enter copies a file:// URI to the
// clipboard, Shift+Enter or right-click opens in the default player.
// Index 0 is the OPEN FOLDER button.
Item {
    id: body
    required property var root
    required property var nav
    width: parent ? parent.width : 0

    signal close()

    implicitHeight: col.implicitHeight + 8
    readonly property int cols: 4
    readonly property real cellW: Math.max(60, (col.width - (cols - 1) * 8) / cols)
    readonly property real cellH: cellW * 0.62

    Component.onCompleted: if (body.nav) body.nav.refreshVideos()

    property int kbdIndex: 1
    readonly property var _items: body.nav ? body.nav.videoFiles.slice(0, cols * 4) : []
    readonly property int _kbdMax: 1 + _items.length

    function kbdHandle(event) {
        const k = event.key;
        const n = body._kbdMax;
        if (n === 0) return false;
        if (k === Qt.Key_Left) {
            if (body.kbdIndex > 1) body.kbdIndex = Math.max(1, body.kbdIndex - 1);
            else if (body.kbdIndex === 1) body.kbdIndex = 0;
            return true;
        }
        if (k === Qt.Key_Right || k === Qt.Key_Tab) {
            body.kbdIndex = Math.min(n - 1, body.kbdIndex + 1);
            return true;
        }
        if (k === Qt.Key_Up) {
            if (body.kbdIndex === 0) return true;
            const newIdx = body.kbdIndex - body.cols;
            body.kbdIndex = newIdx >= 1 ? newIdx : 0;
            return true;
        }
        if (k === Qt.Key_Down) {
            body.kbdIndex = Math.min(n - 1, body.kbdIndex + (body.kbdIndex === 0 ? 1 : body.cols));
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            if (body.kbdIndex === 0) {
                if (body.nav) body.nav.run("xdg-open "
                    + JSON.stringify(Quickshell.env("HOME") + "/Videos"));
                body.close();
                return true;
            }
            const it = body._items[body.kbdIndex - 1];
            if (it && body.nav) body.nav.copyVideoUri(it.path);
            return true;
        }
        return false;
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 6
        spacing: 10

        Item {
            width: parent.width
            height: 24
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: body.nav
                      ? body.nav.videoFiles.length + " RECENT"
                      : "—"
                color: body.root.inkDeep
                font.family: body.root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                QuickButton {
                    root: body.root
                    glyph: ""
                    label: "OPEN FOLDER"
                    selected: body.kbdIndex === 0
                    onClicked: {
                        if (body.nav) body.nav.run("xdg-open "
                            + JSON.stringify(Quickshell.env("HOME") + "/Videos"));
                        body.close();
                    }
                }
            }
        }

        Grid {
            width: parent.width
            columns: body.cols
            rowSpacing: 8
            columnSpacing: 8
            Repeater {
                model: body._items
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool kbdFocused: body.kbdIndex === (index + 1)
                    width: body.cellW
                    height: body.cellH
                    radius: body.root.cornerRadius
                    color: Qt.rgba(body.root.ink.r, body.root.ink.g, body.root.ink.b, 0.05)
                    border.color: kbdFocused || vidMouse.containsMouse ? body.root.seal : body.root.sep
                    border.width: kbdFocused ? 2 : 1
                    clip: true
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                    Behavior on border.width { NumberAnimation { duration: 120 } }

                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        source: modelData.thumb ? "file://" + modelData.thumb : ""
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                        cache: true
                        sourceSize.width: 320
                        sourceSize.height: 200
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !modelData.thumb || modelData.thumb.length === 0
                        text: body.nav ? body.nav.icoFilm : ""
                        color: body.root.inkDeep
                        font.family: body.root.mono
                        font.pixelSize: 22
                    }
                    Rectangle {
                        visible: modelData.duration > 0
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: 4
                        radius: 3
                        // theme.bg paired with theme.ink so the badge
                        // tracks dark + light themes without forcing a
                        // fixed black background.
                        color: Qt.rgba(body.root.paper.r, body.root.paper.g, body.root.paper.b, 0.78)
                        border.color: body.root.sep
                        border.width: 1
                        width: durText.implicitWidth + 8
                        height: durText.implicitHeight + 4
                        Text {
                            id: durText
                            anchors.centerIn: parent
                            text: body.nav ? body.nav.formatVideoDuration(modelData.duration) : ""
                            color: body.root.ink
                            font.family: body.root.mono
                            font.pixelSize: 8
                        }
                    }
                    MouseArea {
                        id: vidMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (e) => {
                            if (!body.nav) return;
                            body.kbdIndex = index + 1;
                            if (e.button === Qt.RightButton)
                                body.nav.run("xdg-open " + JSON.stringify(modelData.path));
                            else
                                body.nav.copyVideoUri(modelData.path);
                        }
                    }
                }
            }
        }

        Text {
            visible: body.nav && body.nav.videoFiles.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "NO VIDEOS FOUND"
            color: body.root.inkDeep
            font.family: body.root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
            opacity: 0.6
        }
    }
}
