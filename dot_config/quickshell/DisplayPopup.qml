import QtQuick

CardWindow {
    id: displayPopup
    required property var root

    theme: root
    revealed: root.displayVisible
    cardWidth: 480
    layerNamespace: "omarchy-display"
    footer: "↑↓ ROW · ←→ ADJUST · 1-4 PRESET · R RESET · B BLANK · E EDIT · ESC"

    anchorEdge: displayPopup.root.barEdge
    anchorBarX: displayPopup.root.popupAnchorX
    anchorBarY: displayPopup.root.popupAnchorY

    title: "DISPLAY"
    subtitle: Math.round(displayPopup.root.warmthK) + "K  ·  BR " + displayPopup.root.brightnessPct
              + "  ·  γ " + Math.round(displayPopup.root.gammaPct)
              + "  ·  " + displayPopup.root.monitorRate.toFixed(0) + "HZ"

    headerRight: CalendarChevron {
        root: displayPopup.root
        text: displayPopup.root.icoRefresh
        restColor: displayPopup.root.inkDeep
        font.pixelSize: 22
        onTriggered: displayPopup.root.resetDisplay()
    }

    onDismiss: displayPopup.root.displayVisible = false
    onKeyPressed: function(event) {
        const r = displayPopup.root;
        const k = event.key;
        if (k === Qt.Key_Q) {
            r.displayVisible = false;
        } else if (k === Qt.Key_Down || k === Qt.Key_J) {
            r.displayRow = Math.min(6, r.displayRow + 1);
        } else if (k === Qt.Key_Up || k === Qt.Key_K) {
            r.displayRow = Math.max(0, r.displayRow - 1);
        } else if (k === Qt.Key_Left || k === Qt.Key_H) {
            if (r.displayRow === 0)      r.setWarmth(r.warmthK - 250);
            else if (r.displayRow === 1) r.setBrightness(r.brightnessPct - 5);
            else if (r.displayRow === 2) r.setGamma(r.gammaPct - 5);
            else if (r.displayRow === 3) {
                const n = r.displayPresets.length;
                r.selectedPreset = (r.selectedPreset - 1 + n) % n;
            }
        } else if (k === Qt.Key_Right || k === Qt.Key_L) {
            if (r.displayRow === 0)      r.setWarmth(r.warmthK + 250);
            else if (r.displayRow === 1) r.setBrightness(r.brightnessPct + 5);
            else if (r.displayRow === 2) r.setGamma(r.gammaPct + 5);
            else if (r.displayRow === 3) {
                r.selectedPreset = (r.selectedPreset + 1) % r.displayPresets.length;
            }
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            if (r.displayRow === 3) {
                r.applyPreset(r.displayPresets[r.selectedPreset]);
            } else if (r.displayRow === 4) {
                r.run("omarchy-launch-editor ~/.config/hypr/monitors.lua");
                r.displayVisible = false;
            } else if (r.displayRow === 5) r.blankScreen();
            else if (r.displayRow === 6) r.resetDisplay();
        } else if (k >= Qt.Key_1 && k <= Qt.Key_4) {
            const idx = k - Qt.Key_1;
            if (idx < r.displayPresets.length) {
                r.selectedPreset = idx;
                r.applyPreset(r.displayPresets[idx]);
            }
        } else if (k === Qt.Key_R) {
            r.resetDisplay();
        } else if (k === Qt.Key_B) {
            r.blankScreen();
        } else if (k === Qt.Key_E) {
            r.run("omarchy-launch-editor ~/.config/hypr/monitors.lua");
            r.displayVisible = false;
        } else {
            return;
        }
        event.accepted = true;
    }

    Column {
        id: dispCol
        width: parent.width
        spacing: 12

        Repeater {
            model: [
                { label: "WARMTH",     valKey: "warmthK",       lo: 1000, hi: 6500, unit: "K", row: 0 },
                { label: "BRIGHTNESS", valKey: "brightnessPct", lo: 1,    hi: 100,  unit: "%", row: 1 },
                { label: "GAMMA",      valKey: "gammaPct",      lo: 50,   hi: 150,  unit: "",  row: 2 }
            ]
            delegate: DisplaySlider {
                required property var modelData
                root: displayPopup.root
                width: dispCol.width
                label: modelData.label
                value: displayPopup.root[modelData.valKey]
                minV: modelData.lo
                maxV: modelData.hi
                unit: modelData.unit
                selected: displayPopup.root.displayRow === modelData.row
                onCommit: function(v) {
                    if      (modelData.row === 0) displayPopup.root.setWarmth(v);
                    else if (modelData.row === 1) displayPopup.root.setBrightness(v);
                    else                          displayPopup.root.setGamma(v);
                }
                onFocusRequested: displayPopup.root.displayRow = modelData.row
            }
        }

        Rectangle { width: parent.width; height: 1; color: displayPopup.root.sep }

        Item {
            width: parent.width
            height: 38

            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                text: "PRESETS"
                color: displayPopup.root.displayRow === 3 ? displayPopup.root.seal : displayPopup.root.inkDeep
                font.family: displayPopup.root.mono
                font.pixelSize: 10
                font.letterSpacing: 2
                Behavior on color { ColorAnimation { duration: 140 } }
            }

            Row {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                spacing: 6

                Repeater {
                    model: displayPopup.root.displayPresets
                    delegate: DisplayChip {
                        required property var modelData
                        required property int index
                        root: displayPopup.root
                        label: modelData.label
                        selected: displayPopup.root.selectedPreset === index
                        onActivated: {
                            displayPopup.root.selectedPreset = index;
                            displayPopup.root.displayRow = 3;
                            displayPopup.root.applyPreset(modelData);
                        }
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: displayPopup.root.sep }

        // Scale / rate / VRR are read-only — Hyprland's lua parser refuses
        // runtime `keyword monitor` ("Use eval."). EDIT MONITORS below
        // opens monitors.lua for persistent edits.
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: "MONITOR · " + displayPopup.root.monitorName + " · " + displayPopup.root.monitorRes
                  + " · ×" + displayPopup.root.monitorScale.toFixed(2)
            color: displayPopup.root.inkDeep
            font.family: displayPopup.root.mono
            font.pixelSize: 10
            font.letterSpacing: 2
        }

        Item {
            width: parent.width
            height: 26
            DisplayChip {
                root: displayPopup.root
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                label: "EDIT MONITORS"
                selected: displayPopup.root.displayRow === 4
                onActivated: {
                    displayPopup.root.displayRow = 4;
                    displayPopup.root.run("omarchy-launch-editor ~/.config/hypr/monitors.lua");
                    displayPopup.root.displayVisible = false;
                }
            }
            DisplayChip {
                root: displayPopup.root
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                label: displayPopup.root.icoPower + " BLANK"
                selected: displayPopup.root.displayRow === 5
                onActivated: { displayPopup.root.displayRow = 5; displayPopup.root.blankScreen(); }
            }
            DisplayChip {
                root: displayPopup.root
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: "RESET"
                selected: displayPopup.root.displayRow === 6
                onActivated: { displayPopup.root.displayRow = 6; displayPopup.root.resetDisplay(); }
            }
        }
    }
}
