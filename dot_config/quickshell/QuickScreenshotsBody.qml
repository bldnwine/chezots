import QtQuick

// Screenshots detail — recent thumbs (4-column grid). Keyboard:
// arrows move through the grid, Enter copies to clipboard, Shift+Enter
// opens in the default viewer. Index 0 is the CAPTURE button.
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

    Component.onCompleted: if (body.nav) body.nav.refreshScreenshots()

    property int kbdIndex: 1   // 0 = CAPTURE, 1..N = thumbs
    readonly property var _items: body.nav ? body.nav.screenshotFiles.slice(0, cols * 4) : []
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
                if (body.nav) body.nav.run("omarchy-capture-screenshot");
                body.close();
                return true;
            }
            const it = body._items[body.kbdIndex - 1];
            if (it && body.nav) body.nav.copyScreenshotToClipboard(it.path);
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
                      ? body.nav.screenshotFiles.length + " RECENT"
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
                    label: "CAPTURE"
                    selected: body.kbdIndex === 0
                    onClicked: {
                        if (body.nav) body.nav.run("omarchy-capture-screenshot");
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
                    border.color: kbdFocused || shotMouse.containsMouse ? body.root.seal : body.root.sep
                    border.width: kbdFocused ? 2 : 1
                    clip: true
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                    Behavior on border.width { NumberAnimation { duration: 120 } }

                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        source: "file://" + modelData.path
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                        cache: true
                        sourceSize.width: 320
                        sourceSize.height: 200
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 4
                        text: modelData.label
                        // theme.ink with theme.paper outline keeps the
                        // caption legible whether the user's theme is
                        // dark (light text + dark halo) or light (dark
                        // text + light halo) — the outline is what makes
                        // it pop against arbitrary thumbnail content.
                        color: body.root.ink
                        elide: Text.ElideRight
                        font.family: body.root.mono
                        font.pixelSize: 8
                        font.letterSpacing: 1
                        style: Text.Outline
                        styleColor: body.root.paper
                    }

                    // Snap-in / fade-out COPIED overlay, driven by the same
                    // `copiedPath` state the full ScreenshotsPopup uses, so
                    // the ack reads consistently wherever the user copies.
                    // copiedReset on the navbar clears the path after ~1.4s.
                    Rectangle {
                        id: copyFlash
                        readonly property bool justCopied:
                            body.nav && body.nav.copiedPath === modelData.path
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: body.root.cornerRadius
                        color: Qt.rgba(body.root.seal.r, body.root.seal.g, body.root.seal.b, 0.30)
                        border.color: body.root.seal
                        border.width: 2
                        visible: opacity > 0.01
                        opacity: justCopied ? 1 : 0
                        antialiasing: true
                        Behavior on opacity {
                            NumberAnimation {
                                duration: copyFlash.justCopied ? 80 : 600
                                easing.type: copyFlash.justCopied ? Easing.OutQuad : Easing.InCubic
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "COPIED"
                            // 30% seal over the thumbnail leaves the
                            // effective background dependent on the
                            // image, so a theme.ink fill + theme.paper
                            // outline guarantees contrast in both light
                            // and dark themes.
                            color: body.root.ink
                            style: Text.Outline
                            styleColor: body.root.paper
                            font.family: body.root.mono
                            font.pixelSize: 11
                            font.letterSpacing: 3
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: shotMouse
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
                                body.nav.copyScreenshotToClipboard(modelData.path);
                        }
                    }
                }
            }
        }

        Text {
            visible: body.nav && body.nav.screenshotFiles.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "NO SCREENSHOTS YET"
            color: body.root.inkDeep
            font.family: body.root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
            opacity: 0.6
        }
    }
}
