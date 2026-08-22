import QtQuick
import Quickshell
import Quickshell.Io

// Equalizer Deck with live 0ms updates, ON/BYPASS toggle, dynamic 1..10 parametric bands,
// auto-preamp calculator, user presets below apply, and AutoEQ import/export.
Item {
    id: eqPanel
    required property var root

    property bool eqEnabled: true
    property real preamp: 0.0
    property var bands: []
    property string activePreset: "Flat"
    property var presetList: ["Flat"]
    property var presetsMap: ({})
    property bool isApplied: true
    property bool importOpen: false
    property string importText: ""
    property string statusMsg: ""

    implicitWidth: 360
    implicitHeight: mainCol.implicitHeight

    readonly property string scriptPath: Quickshell.env("HOME") + "/.config/quickshell/desktop/scripts/pipewire-eq"

    function loadFromState(txt) {
        if (!txt || txt.trim().length === 0) return;
        try {
            const data = JSON.parse(txt.trim());
            if (data.enabled !== undefined) eqPanel.eqEnabled = Boolean(data.enabled);
            if (data.preamp !== undefined) eqPanel.preamp = Number(data.preamp);
            if (data.activePreset) {
                const clean = String(data.activePreset).split(/[\r\n]+/)[0].trim().slice(0, 32);
                eqPanel.activePreset = clean.length > 0 ? clean : "Flat";
            }
            if (Array.isArray(data.bands) && data.bands.length > 0) {
                eqPanel.bands = data.bands.slice(0, 10);
            }
            eqPanel.isApplied = true;
        } catch (e) {
            console.log("[EqPanel load error]", e);
        }
    }

    function loadPresets(txt) {
        if (!txt || txt.trim().length === 0) return;
        try {
            const data = JSON.parse(txt.trim());
            if (typeof data === "object" && data !== null) {
                const cleanedMap = {};
                const list = [];
                for (const k in data) {
                    const cleanK = String(k).split(/[\r\n]+/)[0].trim().slice(0, 32);
                    if (cleanK.length > 0 && !cleanedMap[cleanK]) {
                        cleanedMap[cleanK] = data[k];
                        list.push(cleanK);
                    }
                }
                eqPanel.presetsMap = cleanedMap;
                eqPanel.presetList = list.length > 0 ? list : ["Flat"];
            }
        } catch (e) {
            console.log("[EqPanel presets load error]", e);
        }
    }

    // Sends 0ms live update to running PipeWire filter graph
    function applyLive() {
        const payload = JSON.stringify({
            enabled: eqPanel.eqEnabled,
            activePreset: eqPanel.activePreset,
            preamp: eqPanel.preamp,
            bands: eqPanel.bands
        });
        Quickshell.execDetached([eqPanel.scriptPath, "live", payload]);
        eqPanel.isApplied = true;
    }

    function toggleEnabled() {
        eqPanel.eqEnabled = !eqPanel.eqEnabled;
        eqPanel.applyLive();
        eqPanel.statusMsg = eqPanel.eqEnabled ? "EQ ON" : "BYPASSED";
        clearStatusTimer.restart();
    }

    function runAutoPreamp() {
        let maxGain = 0.0;
        for (let i = 0; i < eqPanel.bands.length; i++) {
            const g = Number(eqPanel.bands[i].gain) || 0.0;
            if (g > maxGain) maxGain = g;
        }
        const autoPreampVal = -Math.max(0.0, maxGain);
        eqPanel.preamp = Math.round(autoPreampVal * 2) / 2;
        eqPanel.applyLive();
        eqPanel.statusMsg = "AUTO: " + eqPanel.preamp.toFixed(1) + " dB";
        clearStatusTimer.restart();
    }

    function setBandGain(index, newGain) {
        const list = Array.from(eqPanel.bands);
        if (index >= 0 && index < list.length) {
            list[index] = {
                freq: list[index].freq,
                gain: newGain,
                q: list[index].q,
                type: list[index].type
            };
            eqPanel.bands = list;
            liveDebounceTimer.restart();
        }
    }

    function addBand() {
        if (eqPanel.bands.length >= 10) return;
        const list = Array.from(eqPanel.bands);
        let newFreq = 1000.0;
        if (list.length > 0) {
            const last = list[list.length - 1].freq;
            newFreq = Math.min(20000.0, Math.round(last * 1.5));
        }
        list.push({
            freq: newFreq,
            gain: 0.0,
            q: 1.0,
            type: "peaking"
        });
        eqPanel.bands = list;
        eqPanel.isApplied = false;
        // Adding band changes graph topology -> full apply
        eqPanel.applyEq();
    }

    function removeBand() {
        if (eqPanel.bands.length <= 1) return;
        const list = Array.from(eqPanel.bands);
        list.pop();
        eqPanel.bands = list;
        eqPanel.isApplied = false;
        eqPanel.applyEq();
    }

    function flattenBands() {
        const list = [];
        for (let i = 0; i < eqPanel.bands.length; i++) {
            const b = eqPanel.bands[i];
            list.push({
                freq: b.freq,
                gain: 0.0,
                q: b.q,
                type: b.type
            });
        }
        eqPanel.bands = list;
        eqPanel.preamp = 0.0;
        eqPanel.applyLive();
        eqPanel.statusMsg = "FLAT";
        clearStatusTimer.restart();
    }

    function selectPreset(name) {
        if (eqPanel.presetsMap && eqPanel.presetsMap[name]) {
            const p = eqPanel.presetsMap[name];
            eqPanel.preamp = p.preamp !== undefined ? p.preamp : 0.0;
            if (Array.isArray(p.bands)) {
                eqPanel.bands = p.bands.slice(0, 10);
            }
            eqPanel.activePreset = name;
            eqPanel.applyLive();
            eqPanel.statusMsg = "LOADED: " + name;
            clearStatusTimer.restart();
        }
    }

    function applyEq() {
        const payload = JSON.stringify({
            enabled: eqPanel.eqEnabled,
            activePreset: eqPanel.activePreset,
            preamp: eqPanel.preamp,
            bands: eqPanel.bands
        });
        Quickshell.execDetached([eqPanel.scriptPath, "apply", payload]);
        eqPanel.isApplied = true;
        eqPanel.statusMsg = "APPLIED";
        clearStatusTimer.restart();
    }

    function savePreset(name) {
        if (!name || name.trim().length === 0) return;
        const clean = name.trim().slice(0, 32);
        Quickshell.execDetached([eqPanel.scriptPath, "save", clean]);
        eqPanel.activePreset = clean;
        eqPanel.statusMsg = "SAVED: " + clean;
        clearStatusTimer.restart();
    }

    function deletePreset(name) {
        if (!name) return;
        Quickshell.execDetached([eqPanel.scriptPath, "delete", name]);
        eqPanel.statusMsg = "DELETED";
        clearStatusTimer.restart();
    }

    function runImport(text) {
        if (!text || text.trim().length === 0) return;
        Quickshell.execDetached([eqPanel.scriptPath, "import", text.trim()]);
        eqPanel.importOpen = false;
        eqPanel.importText = "";
        eqPanel.statusMsg = "IMPORTED";
        clearStatusTimer.restart();
    }

    function runExport() {
        Quickshell.execDetached(["bash", "-c",
            "\"" + eqPanel.scriptPath + "\" export | wl-copy"
        ]);
        eqPanel.statusMsg = "COPIED TO CLIPBOARD";
        clearStatusTimer.restart();
    }

    Timer {
        id: liveDebounceTimer
        interval: 30
        repeat: false
        onTriggered: eqPanel.applyLive()
    }

    Timer {
        id: clearStatusTimer
        interval: 2200
        onTriggered: eqPanel.statusMsg = ""
    }

    FileView {
        id: stateWatcher
        path: Quickshell.env("HOME") + "/.local/state/quickshell-desktop/eq-state.json"
        watchChanges: true
        printErrors: false
        onLoaded: eqPanel.loadFromState(text())
        onFileChanged: reload()
    }

    FileView {
        id: presetsWatcher
        path: Quickshell.env("HOME") + "/.local/state/quickshell-desktop/eq-presets.json"
        watchChanges: true
        printErrors: false
        onLoaded: eqPanel.loadPresets(text())
        onFileChanged: reload()
    }

    Column {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 8

        // Top Header: Title + ON/BYPASS Switch + Dynamic Band Controls
        Item {
            width: parent.width
            height: 24

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "EQUALIZER"
                    color: eqPanel.root.ink
                    font.family: eqPanel.root.mono
                    font.pixelSize: 11
                    font.letterSpacing: 2
                    font.weight: Font.Medium
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: eqPanel.bands.length + " BANDS"
                    color: eqPanel.root.inkDeep
                    font.family: eqPanel.root.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1.5
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                // ON / BYPASS Switch
                Rectangle {
                    width: 44
                    height: 22
                    radius: eqPanel.root.cornerRadius
                    color: eqPanel.eqEnabled ? eqPanel.root.rowSel : eqPanel.root.rowHi
                    border.color: eqPanel.eqEnabled ? eqPanel.root.seal : eqPanel.root.sep
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: eqPanel.eqEnabled ? "ON" : "OFF"
                        color: eqPanel.eqEnabled ? eqPanel.root.seal : eqPanel.root.inkDeep
                        font.family: eqPanel.root.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: toggleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: eqPanel.toggleEnabled()
                    }
                }

                // Add Band button
                Rectangle {
                    width: 22
                    height: 22
                    radius: eqPanel.root.cornerRadius
                    color: addMouse.containsMouse && eqPanel.bands.length < 10 ? eqPanel.root.rowHi : "transparent"
                    border.color: eqPanel.root.sep
                    border.width: 1
                    opacity: eqPanel.bands.length < 10 ? 1.0 : 0.4

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: eqPanel.root.ink
                        font.family: eqPanel.root.mono
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: addMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: eqPanel.bands.length < 10 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: eqPanel.addBand()
                    }
                }

                // Remove Band button
                Rectangle {
                    width: 22
                    height: 22
                    radius: eqPanel.root.cornerRadius
                    color: subMouse.containsMouse && eqPanel.bands.length > 1 ? eqPanel.root.rowHi : "transparent"
                    border.color: eqPanel.root.sep
                    border.width: 1
                    opacity: eqPanel.bands.length > 1 ? 1.0 : 0.4

                    Text {
                        anchors.centerIn: parent
                        text: "-"
                        color: eqPanel.root.ink
                        font.family: eqPanel.root.mono
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: subMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: eqPanel.bands.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: eqPanel.removeBand()
                    }
                }

                // Flat button
                Rectangle {
                    width: 38
                    height: 22
                    radius: eqPanel.root.cornerRadius
                    color: flatMouse.containsMouse ? eqPanel.root.rowHi : "transparent"
                    border.color: eqPanel.root.sep
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "FLAT"
                        color: eqPanel.root.ink
                        font.family: eqPanel.root.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1
                    }

                    MouseArea {
                        id: flatMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: eqPanel.flattenBands()
                    }
                }
            }
        }

        // Preamp Slider Bar with AUTO button
        Item {
            width: parent.width
            height: 22

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "PREAMP"
                    color: eqPanel.root.ink
                    font.family: eqPanel.root.mono
                    font.pixelSize: 10
                    font.letterSpacing: 1.2
                }

                // Auto-Preamp button
                Rectangle {
                    width: 36
                    height: 18
                    radius: eqPanel.root.cornerRadius
                    color: autoMouse.containsMouse ? eqPanel.root.seal : eqPanel.root.rowHi
                    border.color: eqPanel.root.sep
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "AUTO"
                        color: autoMouse.containsMouse ? eqPanel.root.bg : eqPanel.root.ink
                        font.family: eqPanel.root.mono
                        font.pixelSize: 8
                        font.letterSpacing: 1
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: autoMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: eqPanel.runAutoPreamp()
                    }
                }
            }

            Text {
                anchors.right: preampTrack.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: (eqPanel.preamp > 0 ? "+" : "") + eqPanel.preamp.toFixed(1) + " dB"
                color: Math.abs(eqPanel.preamp) > 0.05 ? eqPanel.root.seal : eqPanel.root.inkDeep
                font.family: eqPanel.root.mono
                font.pixelSize: 10
                font.weight: Font.Medium
            }

            Rectangle {
                id: preampTrack
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 160
                height: 4
                radius: 1
                color: Qt.rgba(eqPanel.root.ink.r, eqPanel.root.ink.g, eqPanel.root.ink.b, 0.14)

                // Zero line in center
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 8
                    color: eqPanel.root.sep
                }

                // Fill from -12dB to +12dB
                Rectangle {
                    readonly property real norm: Math.max(0, Math.min(1, (eqPanel.preamp - (-12.0)) / 24.0))
                    readonly property real centerNorm: 0.5
                    x: Math.min(norm, centerNorm) * parent.width
                    width: Math.abs(norm - centerNorm) * parent.width
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    color: eqPanel.root.seal
                    radius: 1
                }

                // Thumb
                Rectangle {
                    readonly property real norm: Math.max(0, Math.min(1, (eqPanel.preamp - (-12.0)) / 24.0))
                    x: Math.max(0, Math.min(parent.width - width, parent.width * norm - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: 12
                    radius: 1
                    color: preampMouse.containsMouse || preampMouse.pressed ? eqPanel.root.ink : eqPanel.root.seal
                }

                MouseArea {
                    id: preampMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: (e) => {
                        const ratio = Math.max(0, Math.min(1, e.x / preampTrack.width));
                        const val = -12.0 + ratio * 24.0;
                        eqPanel.preamp = Math.round(val * 2) / 2;
                        liveDebounceTimer.restart();
                    }
                    onPositionChanged: (e) => {
                        if (!pressed) return;
                        const ratio = Math.max(0, Math.min(1, e.x / preampTrack.width));
                        const val = -12.0 + ratio * 24.0;
                        eqPanel.preamp = Math.round(val * 2) / 2;
                        liveDebounceTimer.restart();
                    }
                    onWheel: (wheel) => {
                        const step = wheel.angleDelta.y > 0 ? 0.5 : -0.5;
                        eqPanel.preamp = Math.max(-12.0, Math.min(12.0, eqPanel.preamp + step));
                        liveDebounceTimer.restart();
                    }
                    onDoubleClicked: {
                        eqPanel.preamp = 0.0;
                        liveDebounceTimer.restart();
                    }
                }
            }
        }

        // Sliders Deck (Main Vertical Bands Container)
        Rectangle {
            id: sliderDeck
            width: parent.width
            height: 175
            radius: eqPanel.root.cornerRadius
            color: Qt.rgba(eqPanel.root.ink.r, eqPanel.root.ink.g, eqPanel.root.ink.b, 0.04)
            border.color: eqPanel.root.sep
            border.width: 1
            clip: true

            Row {
                id: sliderRow
                anchors.fill: parent
                anchors.margins: 8

                readonly property int count: Math.max(1, eqPanel.bands.length)
                readonly property real availW: width
                readonly property real gap: count > 1 ? 4 : 0
                readonly property real bandW: Math.max(26, Math.min(42, Math.floor((availW - (count - 1) * gap) / count)))
                spacing: count > 1 ? Math.max(2, Math.floor((availW - count * bandW) / (count - 1))) : 0

                Repeater {
                    model: eqPanel.bands
                    delegate: EqSlider {
                        required property var modelData
                        required property int index

                        root: eqPanel.root
                        width: sliderRow.bandW
                        height: parent.height
                        freq: modelData.freq || 1000
                        gain: modelData.gain !== undefined ? modelData.gain : 0.0
                        qVal: modelData.q || 1.0
                        filterType: modelData.type || "peaking"

                        onValueModified: (newGain) => eqPanel.setBandGain(index, newGain)
                    }
                }
            }
        }

        // Inline Import Box (Collapsible)
        Column {
            width: parent.width
            spacing: 6
            visible: eqPanel.importOpen

            Rectangle {
                width: parent.width
                height: 48
                radius: eqPanel.root.cornerRadius
                color: eqPanel.root.rowHi
                border.color: eqPanel.root.seal
                border.width: 1

                TextInput {
                    id: importInput
                    anchors.fill: parent
                    anchors.margins: 6
                    text: eqPanel.importText
                    color: eqPanel.root.ink
                    font.family: eqPanel.root.mono
                    font.pixelSize: 10
                    selectByMouse: true
                    onTextChanged: eqPanel.importText = text

                    Text {
                        visible: importInput.text.length === 0
                        anchors.fill: parent
                        text: "Paste AutoEQ filter block or file path here..."
                        color: eqPanel.root.inkDeep
                        font.family: eqPanel.root.mono
                        font.pixelSize: 9
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Row {
                anchors.right: parent.right
                spacing: 6

                Rectangle {
                    width: 60
                    height: 22
                    radius: eqPanel.root.cornerRadius
                    color: cancelImportMouse.containsMouse ? eqPanel.root.rowHi : "transparent"
                    border.color: eqPanel.root.sep
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "CANCEL"
                        color: eqPanel.root.inkDeep
                        font.family: eqPanel.root.mono
                        font.pixelSize: 9
                    }

                    MouseArea {
                        id: cancelImportMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            eqPanel.importOpen = false;
                            eqPanel.importText = "";
                        }
                    }
                }

                Rectangle {
                    width: 70
                    height: 22
                    radius: eqPanel.root.cornerRadius
                    color: loadImportMouse.containsMouse ? eqPanel.root.seal : eqPanel.root.rowSel
                    border.color: eqPanel.root.seal
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "LOAD"
                        color: loadImportMouse.containsMouse ? eqPanel.root.bg : eqPanel.root.ink
                        font.family: eqPanel.root.mono
                        font.pixelSize: 9
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: loadImportMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: eqPanel.runImport(eqPanel.importText)
                    }
                }
            }
        }

        // Action Row: APPLY + IMPORT + EXPORT
        Row {
            width: parent.width
            height: 28
            spacing: 6

            // Apply Button
            Rectangle {
                width: parent.width - 130
                height: parent.height
                radius: eqPanel.root.cornerRadius
                color: applyMouse.containsMouse || !eqPanel.isApplied ? eqPanel.root.seal : eqPanel.root.rowSel
                border.color: eqPanel.root.seal
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "󰄬"
                        color: applyMouse.containsMouse || !eqPanel.isApplied ? eqPanel.root.bg : eqPanel.root.ink
                        font.family: eqPanel.root.mono
                        font.pixelSize: 11
                    }

                    Text {
                        text: eqPanel.statusMsg.length > 0 ? eqPanel.statusMsg : "APPLY"
                        color: applyMouse.containsMouse || !eqPanel.isApplied ? eqPanel.root.bg : eqPanel.root.ink
                        font.family: eqPanel.root.mono
                        font.pixelSize: 10
                        font.letterSpacing: 2
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    id: applyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: eqPanel.applyEq()
                }
            }

            // Import Button
            Rectangle {
                width: 60
                height: parent.height
                radius: eqPanel.root.cornerRadius
                color: importMouse.containsMouse || eqPanel.importOpen ? eqPanel.root.rowHi : "transparent"
                border.color: eqPanel.root.sep
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "IMPORT"
                    color: eqPanel.root.ink
                    font.family: eqPanel.root.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }

                MouseArea {
                    id: importMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        eqPanel.importOpen = !eqPanel.importOpen;
                    }
                }
            }

            // Export Button
            Rectangle {
                width: 58
                height: parent.height
                radius: eqPanel.root.cornerRadius
                color: exportMouse.containsMouse ? eqPanel.root.rowHi : "transparent"
                border.color: eqPanel.root.sep
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "EXPORT"
                    color: eqPanel.root.ink
                    font.family: eqPanel.root.mono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }

                MouseArea {
                    id: exportMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: eqPanel.runExport()
                }
            }
        }

        // Presets Manager Row (Placed BELOW APPLY Button)
        EqPresetsMenu {
            id: presetsDropdown
            width: parent.width
            root: eqPanel.root
            activePreset: eqPanel.activePreset
            presetList: eqPanel.presetList
            onPresetSelected: (name) => eqPanel.selectPreset(name)
            onSaveRequested: (name) => eqPanel.savePreset(name)
            onDeleteRequested: (name) => eqPanel.deletePreset(name)
        }
    }
}
