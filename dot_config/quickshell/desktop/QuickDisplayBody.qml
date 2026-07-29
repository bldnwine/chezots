import QtQuick

// Display detail — sliders + preset chips + monitor info + actions.
// Reuses the navbar's existing displayRow state so the embedded panel
// and the standalone popup track the same selection. Keyboard: up/down
// (or Tab) moves through rows 0..6, left/right adjusts the slider /
// cycles presets, Enter fires actions on the lower rows.
Item {
    id: body
    required property var root
    required property var nav
    width: parent ? parent.width : 0

    signal close()

    implicitHeight: col.implicitHeight + 8

    function kbdHandle(event) {
        if (!body.nav) return false;
        const r = body.nav;
        const k = event.key;
        if (k === Qt.Key_Up) {
            r.displayRow = Math.max(0, r.displayRow - 1);
            return true;
        }
        if (k === Qt.Key_Down || k === Qt.Key_Tab) {
            r.displayRow = Math.min(6, r.displayRow + 1);
            return true;
        }
        if (k === Qt.Key_Left) {
            if      (r.displayRow === 0) r.setWarmth(r.warmthK - 250);
            else if (r.displayRow === 1) r.setBrightness(r.brightnessPct - 5);
            else if (r.displayRow === 2) r.setGamma(r.gammaPct - 5);
            else if (r.displayRow === 3) {
                const n = r.displayPresets.length;
                r.selectedPreset = (r.selectedPreset - 1 + n) % n;
            }
            return true;
        }
        if (k === Qt.Key_Right) {
            if      (r.displayRow === 0) r.setWarmth(r.warmthK + 250);
            else if (r.displayRow === 1) r.setBrightness(r.brightnessPct + 5);
            else if (r.displayRow === 2) r.setGamma(r.gammaPct + 5);
            else if (r.displayRow === 3) {
                r.selectedPreset = (r.selectedPreset + 1) % r.displayPresets.length;
            }
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            if (r.displayRow === 3) {
                r.applyPreset(r.displayPresets[r.selectedPreset]);
            } else if (r.displayRow === 4) {
                r.run("omarchy-launch-editor ~/.config/hypr/monitors.lua");
                body.close();
            } else if (r.displayRow === 5) {
                r.blankScreen();
                body.close();
            } else if (r.displayRow === 6) {
                r.resetDisplay();
            }
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

        Text {
            text: body.nav
                  ? Math.round(body.nav.warmthK) + "K  ·  BR " + body.nav.brightnessPct
                    + "  ·  γ " + Math.round(body.nav.gammaPct)
                    + "  ·  " + body.nav.monitorRate.toFixed(0) + "HZ"
                  : ""
            color: body.root.inkDeep
            font.family: body.root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
        }

        Repeater {
            model: [
                { label: "WARMTH",     valKey: "warmthK",       lo: 1000, hi: 6500, unit: "K", row: 0 },
                { label: "BRIGHTNESS", valKey: "brightnessPct", lo: 1,    hi: 100,  unit: "%", row: 1 },
                { label: "GAMMA",      valKey: "gammaPct",      lo: 50,   hi: 150,  unit: "",  row: 2 }
            ]
            delegate: DisplaySlider {
                required property var modelData
                root: body.root
                width: col.width
                label: modelData.label
                value: body.nav ? body.nav[modelData.valKey] : 0
                minV: modelData.lo
                maxV: modelData.hi
                unit: modelData.unit
                selected: body.nav && body.nav.displayRow === modelData.row
                onCommit: function(v) {
                    if (!body.nav) return;
                    if      (modelData.row === 0) body.nav.setWarmth(v);
                    else if (modelData.row === 1) body.nav.setBrightness(v);
                    else                          body.nav.setGamma(v);
                }
                onFocusRequested: if (body.nav) body.nav.displayRow = modelData.row
            }
        }

        Rectangle { width: parent.width; height: 1; color: body.root.sep }

        Item {
            width: parent.width
            height: 38
            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                text: "PRESETS"
                color: body.nav && body.nav.displayRow === 3 ? body.root.seal : body.root.inkDeep
                font.family: body.root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
                Behavior on color { ColorAnimation { duration: 140 } }
            }
            Row {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                spacing: 6
                Repeater {
                    model: body.nav ? body.nav.displayPresets : []
                    delegate: DisplayChip {
                        required property var modelData
                        required property int index
                        root: body.root
                        label: modelData.label
                        selected: body.nav && body.nav.selectedPreset === index
                        onActivated: {
                            if (!body.nav) return;
                            body.nav.selectedPreset = index;
                            body.nav.displayRow = 3;
                            body.nav.applyPreset(modelData);
                        }
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: body.root.sep }

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: body.nav
                  ? "MONITOR · " + body.nav.monitorName + " · " + body.nav.monitorRes
                    + " · ×" + body.nav.monitorScale.toFixed(2)
                  : ""
            color: body.root.inkDeep
            font.family: body.root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
        }

        Item {
            width: parent.width
            height: 28
            DisplayChip {
                root: body.root
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                label: "EDIT MONITORS"
                selected: body.nav && body.nav.displayRow === 4
                onActivated: {
                    if (!body.nav) return;
                    body.nav.displayRow = 4;
                    body.nav.run("omarchy-launch-editor ~/.config/hypr/monitors.lua");
                    body.close();
                }
            }
            DisplayChip {
                root: body.root
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                label: (body.nav ? body.nav.icoPower : "") + " BLANK"
                selected: body.nav && body.nav.displayRow === 5
                onActivated: {
                    if (!body.nav) return;
                    body.nav.displayRow = 5;
                    body.nav.blankScreen();
                    body.close();
                }
            }
            DisplayChip {
                root: body.root
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: "RESET"
                selected: body.nav && body.nav.displayRow === 6
                onActivated: {
                    if (!body.nav) return;
                    body.nav.displayRow = 6;
                    body.nav.resetDisplay();
                }
            }
        }
    }
}
