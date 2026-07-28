import QtQuick

// Aether detail with three modes:
//   BLUEPRINTS — saved aether palettes (apply on Enter)
//   WALLHAVEN  — top wallpapers from wallhaven.cc with material toggle
// Tab cycles modes; ↑/↓/Tab move through the visible content; Enter
// applies the focused item. ESC collapses (handled by OmniMenu).
Item {
    id: body
    required property var root
    required property var nav
    width: parent ? parent.width : 0

    signal close()

    implicitHeight: col.implicitHeight + 8

    // ---------- Mode ----------
    property string mode: "blueprints"   // "blueprints" | "wallhaven"
    readonly property var _modes: ["blueprints", "wallhaven"]
    readonly property int _modeIndex: _modes.indexOf(mode)

    // ---------- Auxiliary sources ----------
    WallhavenSource {
        id: wallhaven
        navbar: body.nav
        active: body.mode === "wallhaven"
    }

    onModeChanged: {
        body.kbdIndex = body._headerCount;
        if (mode === "blueprints" && body.nav && body.nav.aetherBlueprints.length === 0)
            body.nav.refreshAetherBlueprints();
        else if (mode === "wallhaven" && wallhaven.items.length === 0)
            wallhaven.refresh();
    }

    Component.onCompleted: {
        if (body.nav && body.nav.aetherBlueprints.length === 0)
            body.nav.refreshAetherBlueprints();
    }

    // ---------- Lists per mode ----------
    readonly property var _bps: body.nav ? body.nav.aetherBlueprints.slice(0, 6) : []
    readonly property var _wallhavenItems: wallhaven.items.slice(0, 8)

    // ---------- Keyboard ----------
    // Layout: 0..2 = tab chips, 3..N+2 = mode-specific content rows.
    readonly property int _headerCount: 2
    readonly property int _contentCount: {
        if (mode === "blueprints") return _bps.length + 1;       // +1 for RANDOM
        if (mode === "wallhaven")  return _wallhavenItems.length + 1; // +1 for MATERIAL toggle
        return 0;
    }
    readonly property int _kbdMax: _headerCount + _contentCount
    property int kbdIndex: _headerCount   // start on first content row

    function _setMode(idx) { body.mode = body._modes[idx]; }

    function kbdHandle(event) {
        const k = event.key;
        const n = body._kbdMax;
        if (n === 0) return false;
        // Tab always cycles modes for predictable section switching.
        if (k === Qt.Key_Tab) {
            const next = (body._modeIndex + 1) % body._modes.length;
            body._setMode(next);
            return true;
        }
        if (k === Qt.Key_Backtab) {
            const prev = (body._modeIndex - 1 + body._modes.length) % body._modes.length;
            body._setMode(prev);
            return true;
        }
        // M toggles material extraction in wallhaven mode.
        if (k === Qt.Key_M && body.mode === "wallhaven") {
            wallhaven.material = !wallhaven.material;
            return true;
        }
        if (k === Qt.Key_R && body.mode === "wallhaven") {
            wallhaven.refresh();
            return true;
        }
        if (k === Qt.Key_Up) {
            body.kbdIndex = Math.max(0, body.kbdIndex - 1);
            return true;
        }
        if (k === Qt.Key_Down) {
            body.kbdIndex = Math.min(n - 1, body.kbdIndex + 1);
            return true;
        }
        if (k === Qt.Key_Left) {
            if (body.kbdIndex < body._headerCount && body.kbdIndex > 0) {
                body.kbdIndex--;
                body._setMode(body.kbdIndex);
            } else {
                body.kbdIndex = Math.max(0, body.kbdIndex - 1);
            }
            return true;
        }
        if (k === Qt.Key_Right) {
            if (body.kbdIndex < body._headerCount - 1) {
                body.kbdIndex++;
                body._setMode(body.kbdIndex);
            } else {
                body.kbdIndex = Math.min(n - 1, body.kbdIndex + 1);
            }
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            body._activateAt(body.kbdIndex);
            return true;
        }
        return false;
    }

    function _activateAt(i) {
        body.kbdIndex = i;
        if (i < body._headerCount) {
            body._setMode(i);
            return;
        }
        const ci = i - body._headerCount;
        if (body.mode === "blueprints") {
            if (ci < body._bps.length) {
                if (body.nav) body.nav.applyAetherBlueprint(body._bps[ci].name);
            } else {
                if (body.nav) body.nav.run("sh -c '" + (body.nav.aetherBin || "aether") + " --generate \"$(" + (body.nav.aetherBin || "aether") + " --random-wallpaper)\" && " + (body.nav.pushThemeScript || "") + "'");
            }
        } else if (body.mode === "wallhaven") {
            if (ci === 0) {
                wallhaven.material = !wallhaven.material;
            } else if (ci - 1 < body._wallhavenItems.length) {
                wallhaven.applyItem(body._wallhavenItems[ci - 1]);
            }
        }
    }

    // ---------- Layout ----------
    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 6
        spacing: 10

        // Tab row
        Row {
            width: parent.width
            spacing: 6
            Repeater {
                model: [
                    { label: "BLUEPRINTS", key: "blueprints" },
                    { label: "WALLHAVEN",  key: "wallhaven" }
                ]
                delegate: QuickButton {
                    required property var modelData
                    required property int index
                    root: body.root
                    label: modelData.label
                    selected: body.mode === modelData.key || body.kbdIndex === index
                    onClicked: body._setMode(index)
                }
            }
        }

        // Sub-line
        Text {
            text: {
                if (body.mode === "blueprints")
                    return body.nav && body.nav.aetherLoading
                           ? "LOADING…"
                           : (body.nav
                              ? (body.nav.aetherBlueprints.length + " BLUEPRINTS")
                              : "—");
                if (body.mode === "wallhaven") {
                    const m = wallhaven.material ? "MATERIAL" : "NORMAL";
                    return wallhaven.loading
                           ? "LOADING…  ·  " + m
                           : (wallhaven.items.length + " WALLPAPERS  ·  " + m);
                }
                return "";
            }
            color: body.root.inkDeep
            font.family: body.root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
        }

        // ---------- BLUEPRINTS ----------
        Column {
            visible: body.mode === "blueprints"
            width: parent.width
            spacing: 8

            Repeater {
                model: body._bps
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool kbdFocused: body.kbdIndex === (body._headerCount + index)
                    width: col.width
                    height: 36
                    radius: body.root.cornerRadius
                    color: kbdFocused ? body.root.rowSel
                                      : rowMouse.containsMouse ? body.root.rowHi : "transparent"
                    border.color: kbdFocused ? body.root.seal : body.root.sep
                    border.width: kbdFocused ? 2 : 1
                    Behavior on color        { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                    Behavior on border.width { NumberAnimation { duration: 120 } }

                    Row {
                        id: swatchRow
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Repeater {
                            model: (modelData.colors || []).slice(0, 8)
                            delegate: Rectangle {
                                required property string modelData
                                width: 10; height: 10; radius: 2
                                color: modelData
                                border.color: Qt.rgba(body.root.ink.r, body.root.ink.g, body.root.ink.b, 0.10)
                                border.width: 1
                            }
                        }
                    }
                    Text {
                        anchors.left: swatchRow.right
                        anchors.right: lightTag.left
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name || "untitled"
                        elide: Text.ElideRight
                        color: body.root.ink
                        font.family: body.root.mono
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                    Text {
                        id: lightTag
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.lightMode ? "LIGHT" : "DARK"
                        color: body.root.inkDeep
                        font.family: body.root.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1.5
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            body._activateAt(body._headerCount + index);
                        }
                    }
                }
            }

            QuickButton {
                root: body.root
                glyph: ""
                label: "RANDOM"
                selected: body.kbdIndex === (body._headerCount + body._bps.length)
                onClicked: {
                    var cmd = (body.nav ? body.nav.aetherBin || "" : "") + " --generate \"$(" + (body.nav ? body.nav.aetherBin || "" : "") + " --random-wallpaper)\"";
                    if (body.nav && body.nav.pushThemeScript) cmd += " && " + body.nav.pushThemeScript;
                    if (body.nav) body.nav.run("sh -c '" + cmd + "'");
                }
            }
        }

        // ---------- WALLHAVEN ----------
        Column {
            visible: body.mode === "wallhaven"
            width: parent.width
            spacing: 8

            // Material toggle as the first focusable item in this mode.
            QuickButton {
                root: body.root
                glyph: wallhaven.material ? "" : ""
                label: wallhaven.material ? "MATERIAL · ON" : "MATERIAL · OFF"
                selected: body.kbdIndex === body._headerCount
                onClicked: wallhaven.material = !wallhaven.material
            }

            Grid {
                width: parent.width
                columns: 4
                rowSpacing: 8
                columnSpacing: 8
                Repeater {
                    model: body._wallhavenItems
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool kbdFocused: body.kbdIndex === (body._headerCount + 1 + index)
                        readonly property real cellW: (parent.width - 24) / 4
                        width: cellW
                        height: cellW * 0.62
                        radius: body.root.cornerRadius
                        color: Qt.rgba(body.root.ink.r, body.root.ink.g, body.root.ink.b, 0.05)
                        border.color: kbdFocused || whMouse.containsMouse ? body.root.seal : body.root.sep
                        border.width: kbdFocused ? 2 : 1
                        clip: true
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        Behavior on border.width { NumberAnimation { duration: 120 } }

                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            source: wallhaven.thumbPathFor(modelData)
                                    ? "file://" + wallhaven.thumbPathFor(modelData)
                                    : (modelData.thumb || "")
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            smooth: true
                            sourceSize.width: 320
                            sourceSize.height: 200
                        }
                        MouseArea {
                            id: whMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: body._activateAt(body._headerCount + 1 + index)
                        }
                    }
                }
            }

            Text {
                visible: !wallhaven.loading && body._wallhavenItems.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "NO WALLPAPERS — TAP REFRESH (R)"
                color: body.root.inkDeep
                font.family: body.root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
                opacity: 0.6
            }
        }
    }
}
