import QtQuick

CardWindow {
    id: bp
    required property var root

    theme: root
    revealed: root.aetherVisible
    cardWidth: 460
    layerNamespace: "omarchy-aether"

    title: "BLUEPRINTS"
    subtitle: {
        const r = bp.root;
        if (r.aetherLoading) return "LOADING\u2026";
        const total = r.aetherBlueprints.length;
        if (total === 0) return "NONE";
        const shown = r.aetherFiltered.length;
        if (r.aetherQuery === "") return total + " SAVED";
        return shown === 0
            ? "NO MATCHES"
            : shown + " / " + total + " MATCH" + (shown === 1 ? "" : "ES");
    }
    footer: "\u2191\u2193 NAV  \u00b7  \u23CE APPLY  \u00b7  TYPE FILTER  \u00b7  ESC CLOSE"

    onDismiss: { bp.root.aetherVisible = false; Qt.quit() }

    onKeyPressed: function(event) {
        const r = bp.root;
        const k = event.key;
        const mods = event.modifiers;

        if (k === Qt.Key_Down || (k === Qt.Key_Tab && !(mods & Qt.ShiftModifier))) {
            r.moveAetherSelection(1, true);
            aetherList.positionViewAtIndex(r.selectedAether, ListView.Contain);
        } else if (k === Qt.Key_Up || k === Qt.Key_Backtab || (k === Qt.Key_Tab && (mods & Qt.ShiftModifier))) {
            r.moveAetherSelection(-1, true);
            aetherList.positionViewAtIndex(r.selectedAether, ListView.Contain);
        } else if (k === Qt.Key_PageDown) {
            r.moveAetherSelection(8, false);
            aetherList.positionViewAtIndex(r.selectedAether, ListView.Contain);
        } else if (k === Qt.Key_PageUp) {
            r.moveAetherSelection(-8, false);
            aetherList.positionViewAtIndex(r.selectedAether, ListView.Contain);
        } else if (k === Qt.Key_Home) {
            if (r.aetherFiltered.length > 0) {
                r.selectedAether = 0;
                aetherList.positionViewAtIndex(0, ListView.Beginning);
            }
        } else if (k === Qt.Key_End) {
            const n = r.aetherFiltered.length;
            if (n > 0) {
                r.selectedAether = n - 1;
                aetherList.positionViewAtIndex(n - 1, ListView.End);
            }
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            const e = r.aetherFiltered[r.selectedAether];
            if (e) r.applyAetherBlueprint(e.name);
        } else if (k === Qt.Key_Backspace) {
            if (r.aetherQuery.length > 0)
                r.aetherQuery = r.aetherQuery.slice(0, -1);
        } else if (event.text && event.text.length === 1) {
            const ch = event.text;
            if (ch.charCodeAt(0) >= 32 && ch.charCodeAt(0) !== 127) {
                r.aetherQuery += ch;
            } else {
                return;
            }
        } else {
            return;
        }
        event.accepted = true;
    }

    Column {
        width: parent.width
        spacing: 12

        Item {
            width: parent.width
            height: 28

            Text {
                id: searchGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf002"
                color: bp.root.seal
                font.family: bp.root.mono
                font.pixelSize: 14
            }

            Text {
                id: queryText
                anchors.left: searchGlyph.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                readonly property string activeQuery: bp.root.aetherQuery
                text: activeQuery.length === 0
                    ? "Filter blueprints\u2026"
                    : activeQuery
                color: activeQuery.length === 0 ? bp.root.inkDeep : bp.root.ink
                opacity: activeQuery.length === 0 ? 0.5 : 1.0
                font.family: bp.root.mono
                font.pixelSize: 12
                font.letterSpacing: 1
            }

            Rectangle {
                width: 2
                height: 14
                color: bp.root.seal
                anchors.verticalCenter: parent.verticalCenter
                x: queryText.activeQuery.length === 0
                   ? searchGlyph.x + searchGlyph.width + 10
                   : queryText.x + queryText.contentWidth + 2
                visible: bp.root.aetherVisible
                SequentialAnimation on opacity {
                    running: bp.root.aetherVisible
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.2; duration: 600; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.2; to: 1; duration: 600; easing.type: Easing.InOutSine }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: bp.root.sep }

        ListView {
            id: aetherList
            width: parent.width
            height: 360
            clip: true
            model: bp.root.aetherFiltered
            spacing: 0
            currentIndex: bp.root.selectedAether
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: aeRow
                required property var modelData
                required property int index
                width: aetherList.width
                height: 48

                readonly property bool selected: bp.root.selectedAether === aeRow.index
                readonly property string wpPath: modelData.wallpaper || ""

                Rectangle {
                    anchors.fill: parent
                    color: rowMouse.containsMouse
                           ? Qt.rgba(bp.root.ink.r, bp.root.ink.g, bp.root.ink.b, 0.10)
                           : (aeRow.selected
                              ? Qt.rgba(bp.root.ink.r, bp.root.ink.g, bp.root.ink.b, 0.04)
                              : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                Image {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    height: 27
                    source: aeRow.wpPath.length > 0 ? "file://" + aeRow.wpPath : ""
                    sourceSize.width: 64
                    sourceSize.height: 36
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    clip: true
                    visible: aeRow.wpPath.length > 0
                }

                Rectangle {
                    visible: aeRow.selected
                    width: 2
                    height: parent.height - 12
                    anchors.left: parent.left
                    anchors.leftMargin: 62
                    anchors.verticalCenter: parent.verticalCenter
                    color: bp.root.seal
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 74
                    anchors.verticalCenter: parent.verticalCenter
                    width: 155
                    elide: Text.ElideRight
                    text: aeRow.modelData.name
                    color: aeRow.selected ? bp.root.ink : bp.root.inkDeep
                    font.family: bp.root.mono
                    font.pixelSize: 11
                    font.letterSpacing: 1
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 234
                    anchors.verticalCenter: parent.verticalCenter
                    text: aeRow.modelData.lightMode ? "L" : "D"
                    color: bp.root.inkDeep
                    font.family: bp.root.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                    opacity: 0.7
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: (aeRow.modelData.colors || []).slice(0, 8)
                        delegate: Rectangle {
                            required property var modelData
                            width: 14
                            height: 14
                            color: modelData
                            border.color: Qt.rgba(0, 0, 0, 0.25)
                            border.width: 1
                        }
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: bp.root.selectedAether = aeRow.index
                    onClicked: bp.root.applyAetherBlueprint(aeRow.modelData.name)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: bp.root.sep
            visible: bp.root.aetherBlueprints.length > 0
        }

        Item {
            width: parent.width
            height: 26
            visible: bp.root.aetherBlueprints.length > 0
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Item {
                    implicitWidth: openLabel.implicitWidth + 18
                    implicitHeight: 22
                    Rectangle {
                        anchors.fill: parent
                        color: openMouse.containsMouse
                            ? Qt.rgba(bp.root.ink.r, bp.root.ink.g, bp.root.ink.b, 0.10)
                            : Qt.rgba(bp.root.ink.r, bp.root.ink.g, bp.root.ink.b, 0.04)
                        border.color: bp.root.sep
                        border.width: 1
                        radius: bp.root.cornerRadius
                        antialiasing: true
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    Text {
                        id: openLabel
                        anchors.centerIn: parent
                        text: "OPEN GUI"
                        color: bp.root.ink
                        font.family: bp.root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }
                    MouseArea {
                        id: openMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: bp.root.run(bp.root.aetherBin)
                    }
                }

                Item {
                    implicitWidth: randLabel.implicitWidth + 18
                    implicitHeight: 22
                    Rectangle {
                        anchors.fill: parent
                        color: randMouse.containsMouse
                            ? Qt.rgba(bp.root.ink.r, bp.root.ink.g, bp.root.ink.b, 0.10)
                            : Qt.rgba(bp.root.ink.r, bp.root.ink.g, bp.root.ink.b, 0.04)
                        border.color: bp.root.sep
                        border.width: 1
                        radius: bp.root.cornerRadius
                        antialiasing: true
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    Text {
                        id: randLabel
                        anchors.centerIn: parent
                        text: "RANDOM REGEN"
                        color: bp.root.ink
                        font.family: bp.root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }
                    MouseArea {
                        id: randMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: bp.root.run("sh -c '" + bp.root.aetherBin + " --generate \"$(" + bp.root.aetherBin + " --random-wallpaper)\"'")
                    }
                }
            }
        }
    }
}
