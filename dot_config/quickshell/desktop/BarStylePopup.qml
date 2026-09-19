import QtQuick

CardWindow {
    id: barStylePopup
    required property var root

    property bool expanded: false
    property bool saving: false
    property string armedDelete: ""
    Timer {
        id: disarmTimer
        interval: 3000
        onTriggered: barStylePopup.armedDelete = ""
    }

    theme: root
    revealed: root.barStyleVisible
    cardWidth: 440
    layerNamespace: "omarchy-barstyle"
    footer: "↑↓ ROW · ←→ ADJUST · ⏎ SELECT · Q CLOSE"

    anchorEdge: barStylePopup.root.barEdge
    anchorBarX: barStylePopup.root.popupAnchorX
    anchorBarY: barStylePopup.root.popupAnchorY

    title: "BAR STYLE"
    subtitle: barStylePopup.root.barTemplateLabel
              + " · " + barStylePopup.root.barType.toUpperCase()
              + " · " + barStylePopup.root.barHeight + "PX"

    onDismiss: barStylePopup.root.barStyleVisible = false
    onKeyPressed: function(event) {
        const r = barStylePopup.root;
        const k = event.key;
        if (k === Qt.Key_Q) {
            r.barStyleVisible = false;
        } else if (k === Qt.Key_Down || k === Qt.Key_J) {
            r.barStyleRow = Math.min(6, r.barStyleRow + 1);
        } else if (k === Qt.Key_Up || k === Qt.Key_K) {
            r.barStyleRow = Math.max(0, r.barStyleRow - 1);
        } else if (k === Qt.Key_Left || k === Qt.Key_H) {
            adjustRow(-1);
        } else if (k === Qt.Key_Right || k === Qt.Key_L) {
            adjustRow(1);
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            activateRow();
        } else if (k >= Qt.Key_1 && k <= Qt.Key_7) {
            r.barStyleRow = k - Qt.Key_1;
        } else {
            return;
        }
        event.accepted = true;
    }

    function templateNames() {
        return ["zen"].concat(barStylePopup.root.barTemplateNames);
    }
    function cycleTemplates(dir) {
        const r = barStylePopup.root;
        const names = templateNames();
        let idx = names.indexOf(r.barTemplateSelected);
        if (idx === -1) idx = 0;
        r.applyBarTemplate(names[(idx + dir + names.length) % names.length]);
    }
    function deleteTap(name) {
        if (name === "zen") return;
        if (barStylePopup.armedDelete === name) {
            barStylePopup.armedDelete = "";
            disarmTimer.stop();
            barStylePopup.root.deleteBarTemplate(name);
        } else {
            barStylePopup.armedDelete = name;
            disarmTimer.restart();
        }
    }
    function saveCurrent() {
        if (barStylePopup.root.saveBarTemplate(nameField.text)) {
            barStylePopup.saving = false;
            barStylePopup.expanded = false;
            nameField.text = "";
        }
    }

    function adjustRow(dir) {
        const r = barStylePopup.root;
        if (r.barStyleRow === 0)      cycleTemplates(dir);
        else if (r.barStyleRow === 1) r.toggleBarType();
        else if (r.barStyleRow === 2) r.setBarTransparent(dir > 0 ? true : dir < 0 ? false : !r.barTransparent);
        else if (r.barStyleRow === 3) r.setBarOpacity(r.barOpacity + dir * 0.05);
        else if (r.barStyleRow === 4) r.setBarHeight(r.barHeight + dir);
        else if (r.barStyleRow === 5) r.setBarAir(r.barAir + dir);
        else if (r.barStyleRow === 6) r.setBarRounding(r.barRounding + dir);
    }

    function activateRow() {
        const r = barStylePopup.root;
        if (r.barStyleRow === 0) {
            barStylePopup.expanded = !barStylePopup.expanded;
            barStylePopup.saving = false;
        }
        else if (r.barStyleRow === 1) r.toggleBarType();
        else if (r.barStyleRow === 2) r.setBarTransparent(!r.barTransparent);
    }

    component SelRow: Item {
        property var sty: null
        property string label: ""
        property string value: ""
        property bool selected: false
        signal chosen()
        signal stepped(int dir)
        signal removed()

        implicitHeight: 30
        width: parent ? parent.width : 0

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: label
            color: selected ? sty.seal : sty.inkDeep
            font.family: sty.mono
            font.pixelSize: 10
            font.letterSpacing: 2
            Behavior on color { ColorAnimation { duration: 140 } }
        }
        Text {
            anchors.right: parent.right
            anchors.top: parent.top
            text: value.length > 0 ? "‹ " + value + " ›" : ""
            color: selected ? sty.ink : sty.inkDeep
            font.family: sty.mono
            font.pixelSize: 10
            font.letterSpacing: 2
            font.weight: Font.Medium
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (e) => {
                if (e.button === Qt.RightButton) removed();
                else chosen();
            }
            onWheel: (wheel) => {
                if (wheel.angleDelta.y > 0) stepped(1);
                else if (wheel.angleDelta.y < 0) stepped(-1);
            }
        }
    }

    component TplRow: Item {
        property var sty: null
        property string name: ""
        property bool selected: false
        property bool armed: false
        signal chosen()
        signal removed()

        implicitHeight: 28
        width: parent ? parent.width : 0

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: (selected ? "● " : "○ ") + name.toUpperCase()
            color: selected ? sty.seal : sty.ink
            font.family: sty.mono
            font.pixelSize: 10
            font.letterSpacing: 2
            font.weight: selected ? Font.Medium : Font.Normal
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: armed ? "TAP AGAIN" : ""
            color: sty.seal
            font.family: sty.mono
            font.pixelSize: 10
            font.letterSpacing: 2
            font.weight: Font.Medium
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (e) => {
                if (e.button === Qt.RightButton) removed();
                else chosen();
            }
        }
    }

    Column {
        width: parent.width
        spacing: 6

        SelRow {
            sty: barStylePopup.root
            label: "TEMPLATE"
            value: barStylePopup.root.barTemplateLabel
            selected: barStylePopup.root.barStyleRow === 0
            onChosen: {
                barStylePopup.root.barStyleRow = 0;
                barStylePopup.expanded = !barStylePopup.expanded;
                barStylePopup.saving = false;
            }
            onStepped: (dir) => { barStylePopup.root.barStyleRow = 0; barStylePopup.cycleTemplates(dir); }
        }

        Column {
            visible: barStylePopup.expanded
            width: parent.width
            spacing: 2

            Repeater {
                model: barStylePopup.templateNames()
                delegate: TplRow {
                    sty: barStylePopup.root
                    name: modelData
                    selected: modelData === barStylePopup.root.barTemplateSelected
                              && !barStylePopup.root.barTemplateDirty
                    armed: modelData === barStylePopup.armedDelete
                    onChosen: {
                        barStylePopup.root.applyBarTemplate(modelData);
                        barStylePopup.expanded = false;
                    }
                    onRemoved: barStylePopup.deleteTap(modelData)
                }
            }

            TplRow {
                sty: barStylePopup.root
                name: "+ save current"
                selected: false
                armed: false
                onChosen: barStylePopup.saving = !barStylePopup.saving
            }

            Column {
                visible: barStylePopup.saving
                width: parent.width
                spacing: 4

                Rectangle {
                    width: parent.width
                    height: 30
                    color: "transparent"
                    border.color: barStylePopup.root.sep
                    border.width: 1

                    TextInput {
                        id: nameField
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: barStylePopup.root.ink
                        selectionColor: barStylePopup.root.seal
                        font.family: barStylePopup.root.mono
                        font.pixelSize: 11
                        font.letterSpacing: 1
                        maximumLength: 24
                        onAccepted: barStylePopup.saveCurrent()
                    }
                }
                Text {
                    width: parent.width
                    text: "A-Z 0-9 SPACE - _ · MAX 24 · ⏎ SAVE · EXISTING NAME OVERWRITES"
                    color: barStylePopup.root.inkDeep
                    font.family: barStylePopup.root.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
            }
        }

        SelRow {
            sty: barStylePopup.root
            label: "TYPE"
            value: barStylePopup.root.barType.toUpperCase()
            selected: barStylePopup.root.barStyleRow === 1
            onChosen: { barStylePopup.root.barStyleRow = 1; barStylePopup.root.toggleBarType(); }
            onStepped: (dir) => { barStylePopup.root.barStyleRow = 1; barStylePopup.root.toggleBarType(); }
        }
        SelRow {
            sty: barStylePopup.root
            label: "TRANSPARENT"
            value: barStylePopup.root.barTransparent ? "ON" : "OFF"
            selected: barStylePopup.root.barStyleRow === 2
            onChosen: { barStylePopup.root.barStyleRow = 2; barStylePopup.root.setBarTransparent(!barStylePopup.root.barTransparent); }
            onStepped: (dir) => { barStylePopup.root.barStyleRow = 2; barStylePopup.adjustRow(dir); }
        }
        DisplaySlider {
            root: barStylePopup.root
            width: parent.width
            label: "OPACITY"
            value: barStylePopup.root.barOpacity * 100
            minV: 20
            maxV: 100
            unit: "%"
            selected: barStylePopup.root.barStyleRow === 3
            onCommit: (v) => barStylePopup.root.setBarOpacity(v / 100)
            onFocusRequested: barStylePopup.root.barStyleRow = 3
        }
        DisplaySlider {
            root: barStylePopup.root
            width: parent.width
            label: "HEIGHT"
            value: barStylePopup.root.barHeight
            minV: 22
            maxV: 40
            unit: "PX"
            selected: barStylePopup.root.barStyleRow === 4
            onCommit: (v) => barStylePopup.root.setBarHeight(v)
            onFocusRequested: barStylePopup.root.barStyleRow = 4
        }
        DisplaySlider {
            root: barStylePopup.root
            width: parent.width
            label: "AIR"
            value: barStylePopup.root.barAir
            minV: 0
            maxV: 360
            unit: "PX"
            selected: barStylePopup.root.barStyleRow === 5
            onCommit: (v) => barStylePopup.root.setBarAir(v)
            onFocusRequested: barStylePopup.root.barStyleRow = 5
        }
        DisplaySlider {
            root: barStylePopup.root
            width: parent.width
            label: "ROUNDING"
            value: barStylePopup.root.barRounding
            minV: 0
            maxV: 12
            unit: "PX"
            selected: barStylePopup.root.barStyleRow === 6
            onCommit: (v) => barStylePopup.root.setBarRounding(v)
            onFocusRequested: barStylePopup.root.barStyleRow = 6
        }
    }
}
