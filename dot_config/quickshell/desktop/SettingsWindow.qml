import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: root
    required property var theme
    required property var settings
    title: "QS Settings"
    minimumSize: Qt.size(760, 400)
    implicitWidth: settings.windowWidth
    implicitHeight: settings.windowHeight
    visible: false
    color: theme.paper
    property string page: "Colors"
    property string aetherBin: "/home/bldnwine/aethergo/build/bin/aether"
    property bool acceptingPalette: false
    property bool pendingExternal: false
    property int previewEpoch: 0
    property var settledColors: null
    property string settledFingerprint: ""
    readonly property bool previewRunning: previewWorker.running
    property var roles: [
        {name:"Background", role:"paper", token:"qs_paper"}, {name:"Text", role:"ink", token:"qs_ink"},
        {name:"Secondary text", role:"inkDeep", token:"qs_ink_deep"}, {name:"Muted text", role:"sumi", token:"qs_sumi"},
        {name:"Secondary accent", role:"indigo", token:"qs_indigo"}, {name:"Success", role:"green", token:"qs_green"},
        {name:"Primary accent", role:"sealRaw", token:"qs_seal_raw"}, {name:"Panel background", role:"bg", token:"qs_bg"},
        {name:"Warning", role:"warn", token:"qs_warn"}, {name:"Border", role:"sep", token:"qs_sep"},
        {name:"Hover", role:"rowHi", token:"qs_row_hi"}, {name:"Selection", role:"rowSel", token:"qs_row_sel"}]
    property var palette: null
    property var draft: ({})
    property string errorText: ""
    property string selectedRole: "paper"
    property bool closePrompt: false
    property bool saveAsPrompt: false
    property bool closeAfterApply: false
    property int generation: 0
    property bool reloadPending: false
    readonly property bool dirty: palette !== null && JSON.stringify(sorted(draft)) !== JSON.stringify(sorted(palette.overrides || {}))
    readonly property var colors: resolved()
    function sorted(obj) { const out = {}; Object.keys(obj || {}).sort().forEach(k => out[k] = obj[k]); return out; }
    function clone(obj) { return Object.assign({}, obj || {}); }
    function hexByte(value) { return Math.round(value * 255).toString(16).padStart(2, "0"); }
    function validHex(value) { return /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(value); }
    function rgba(hex, alpha) { return hex.substring(0, 7) + Math.round(alpha * 255).toString(16).padStart(2, "0"); }
    function fingerprint() { return palette ? JSON.stringify([palette.revision, sorted(draft)]) : ""; }
    function invalidatePreview() { previewTimer.stop(); previewEpoch++; settledColors = null; settledFingerprint = ""; }
    function syncDraftPreview() {
        invalidatePreview();
        theme.previewPalette(colors);
        if (dirty) previewTimer.restart();
    }
    function resolved() {
        if (!palette) return {};
        if (!dirty) return clone(palette.colors);
        if (settledColors && settledFingerprint === fingerprint()) return settledColors;
        const out = clone(palette.defaults);
        for (const entry of roles) if (draft[entry.token]) out[entry.role] = draft[entry.token];
        if (!draft.qs_bg && out.paper) out.bg = rgba(out.paper, .94);
        if (!draft.qs_warn && out.sealRaw) out.warn = out.sealRaw;
        if (!draft.qs_sep && out.ink) out.sep = rgba(out.ink, .18);
        if (!draft.qs_row_hi && out.ink) out.rowHi = rgba(out.ink, .06);
        if (!draft.qs_row_sel && out.sealRaw) out.rowSel = rgba(out.sealRaw, .18);
        return out;
    }
    function updateColor(role, value) {
        if (worker.running || !validHex(value)) return;
        const entry = roles.find(e => e.role === role);
        if (!entry) return;
        const next = clone(draft); next[entry.token] = value.toLowerCase(); draft = next;
        syncDraftPreview();
    }
    function resetRole(role) {
        const entry = roles.find(e => e.role === role); if (!entry || worker.running) return;
        const next = clone(draft); delete next[entry.token]; draft = next; syncDraftPreview();
    }
    function resetColors() { if (worker.running) return; draft = ({}); syncDraftPreview(); }
    function open() {
        if (visible) { if (chrome.Window.window) chrome.Window.window.requestActivate(); return; }
        visible = true; closePrompt = false; saveAsPrompt = false;
        generation++; readPalette();
        Qt.callLater(function() { if (chrome.Window.window) chrome.Window.window.requestActivate(); });
    }
    function requestClose() {
        if (dirty) closePrompt = true;
        else { invalidatePreview(); theme.cancelPreview(); visible = false; }
    }
    function readPalette() {
        if (worker.running) { reloadPending = true; return; }
        run("palette", {});
    }
    function run(action, payload) {
        if (worker.running) return;
        errorText = "";
        worker.action = action; worker.jobGeneration = generation;
        worker.input = JSON.stringify(payload);
        worker.command = [aetherBin, "--quickshell-" + action, "--json"];
        worker.running = true;
    }
    function commit(action, name) {
        if (!palette || worker.running) return;
        invalidatePreview();
        const payload = {revision: palette.revision, overrides: clone(draft)};
        if (action === "save-as") payload.name = name;
        run(action, payload);
    }
    function completed(action, jobGeneration, output, code) {
        if (jobGeneration !== generation) { if (reloadPending) { reloadPending = false; readPalette(); } return; }
        let result;
        try { result = JSON.parse(output); } catch (_) { result = {ok:false, error:"Invalid response from Aether"}; }
        if (code !== 0 || !result.ok) {
            errorText = result.error || "Aether command failed";
            closeAfterApply = false;
        } else {
            palette = result; draft = clone(result.overrides); errorText = "";
            if (action !== "palette") { acceptingPalette = true; theme.acceptPalette(result.colors, result.revision); acceptingPalette = false; }
            if (closeAfterApply) { closeAfterApply = false; closePrompt = false; visible = false; }
        }
        if (pendingExternal) { pendingExternal = false; theme.cancelPreview(); generation++; reloadPending = true; }
        if (reloadPending) { reloadPending = false; readPalette(); }
    }
    onWidthChanged: if (visible && !maximized && width >= minimumSize.width) settings.setSetting("windowWidth", width)
    onHeightChanged: if (visible && !maximized && height >= minimumSize.height) settings.setSetting("windowHeight", height)
    onClosed: {
        // A compositor close cannot be vetoed by FloatingWindow; re-open the
        // window to present the unsaved-change choice when necessary.
        if (dirty) { visible = true; closePrompt = true; }
        else { invalidatePreview(); theme.cancelPreview(); }
    }
    Connections {
        target: root.theme
        function onPaletteCommitted() {
            if (!root.visible || root.acceptingPalette) return;
            root.invalidatePreview();
            if (worker.running && worker.action !== "palette") { root.pendingExternal = true; return; }
            root.generation++; root.theme.cancelPreview();
            root.closePrompt = false; root.closeAfterApply = false; root.readPalette();
        }
    }
    Timer {
        id: previewTimer
        interval: 100
        onTriggered: {
            if (!root.palette || !root.dirty || worker.running || !root.visible) return;
            if (previewWorker.running) return;
            previewWorker.requestEpoch = root.previewEpoch;
            previewWorker.requestFingerprint = root.fingerprint();
            previewWorker.input = JSON.stringify({revision: root.palette.revision, overrides: root.clone(root.draft)});
            previewWorker.command = [root.aetherBin, "--quickshell-preview", "--json"];
            previewWorker.running = true;
        }
    }
    Process {
        id: previewWorker
        property int requestEpoch: -1
        property string requestFingerprint: ""
        property string input: ""
        stdinEnabled: true
        stdout: StdioCollector { id: previewOutput; waitForEnd: true }
        onStarted: { write(input); stdinEnabled = false; }
        onExited: function(code) {
            stdinEnabled = true;
            const current = root.visible && !worker.running && root.dirty && requestEpoch === root.previewEpoch && requestFingerprint === root.fingerprint();
            if (current) {
                let result;
                try { result = JSON.parse(previewOutput.text); } catch (_) { result = null; }
                if (code === 0 && result && result.ok && result.colors) {
                    root.settledFingerprint = requestFingerprint;
                    root.settledColors = result.colors;
                    root.theme.previewPalette(root.colors);
                } else root.errorText = result && result.error ? result.error : "Could not preview palette";
            }
            if (root.visible && root.dirty && !worker.running && requestEpoch !== root.previewEpoch) previewTimer.restart();
        }
    }
    Process {
        id: worker
        property string action: ""
        property string input: ""
        property int jobGeneration: 0
        stdinEnabled: true
        stdout: StdioCollector { id: output; waitForEnd: true }
        stderr: StdioCollector { id: errors; waitForEnd: true }
        onStarted: { write(input); stdinEnabled = false; }
        onExited: function(code) {
            stdinEnabled = true;
            root.completed(action, jobGeneration, output.text, code);
        }
    }
    Pane {
        id: chrome
        anchors.fill: parent
        padding: 0
        font.family: root.theme.mono || "sans-serif"
        palette.window: root.theme.paper
        palette.windowText: root.theme.ink
        palette.base: root.theme.paper
        palette.text: root.theme.ink
        palette.button: Qt.lighter(root.theme.paper, 1.3)
        palette.buttonText: root.theme.ink
        palette.highlight: root.theme.sealRaw || root.theme.warn
        palette.highlightedText: root.theme.paper
        palette.mid: root.theme.sep
        palette.placeholderText: root.theme.sumi
        background: Rectangle { color: root.theme.paper }
        RowLayout {
            anchors.fill: parent; anchors.margins: 20; spacing: 20
            ColumnLayout {
                Layout.preferredWidth: 155; Layout.fillHeight: true; spacing: 6
                Label { text: "QS SETTINGS"; color: root.theme.ink; font.bold: true; font.pixelSize: 18; Layout.bottomMargin: 15 }
                Repeater {
                    model: ["Colors", "Panels", "Locus"]
                    delegate: Button {
                        required property string modelData
                        text: modelData; Layout.fillWidth: true; highlighted: root.page === modelData
                        onClicked: root.page = modelData
                    }
                }
                Item { Layout.fillHeight: true }
                Button { text: "Close"; Layout.fillWidth: true; onClicked: root.requestClose() }
            }
            Rectangle { Layout.fillHeight: true; width: 1; color: root.theme.sep }
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10
                Label { text: root.page; color: root.theme.ink; font.pixelSize: 24; font.bold: true }
                Label {
                    visible: root.errorText !== "" || root.settings.lastError !== ""
                    text: root.errorText || root.settings.lastError; color: root.theme.warn
                    wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: parent.width; spacing: 12
                        Label {
                            visible: root.page === "Colors"; Layout.fillWidth: true; wrapMode: Text.Wrap
                            color: root.theme.sumi
                            text: root.palette ? "Source: " + (root.palette.source.name || root.palette.source.filename || root.palette.source.kind) : "Loading palette…"
                        }
                        Repeater {
                            model: root.page === "Colors" && root.palette ? root.roles : []
                            delegate: RowLayout {
                                required property var modelData
                                enabled: !worker.running
                                Layout.fillWidth: true; spacing: 8
                                Rectangle { width: 30; height: 30; radius: 4; color: root.colors[modelData.role] ? root.qtColor(root.colors[modelData.role]) : "transparent"; border.color: root.theme.sumi }
                                Label { text: modelData.name; color: root.theme.ink; Layout.preferredWidth: 145 }
                                TextField {
                                    id: hexField
                                    Layout.fillWidth: true; Layout.minimumWidth: 90
                                    text: root.colors[modelData.role] || ""; placeholderText: "#RRGGBB or #RRGGBBAA"
                                    onTextEdited: if (root.validHex(text)) root.updateColor(modelData.role, text)
                                    onEditingFinished: if (!root.validHex(text)) root.errorText = "Enter #RRGGBB or #RRGGBBAA"
                                }
                                Button { text: "Pick"; onClicked: { root.selectedRole = modelData.role; picker.open(); } }
                                Button { text: "Reset"; enabled: !!root.draft[modelData.token]; onClicked: root.resetRole(modelData.role) }
                            }
                        }
                        Repeater {
                            model: root.page === "Panels" ? [
                                {label:"Panel scale", key:"panelScale", min:.75, max:1.5, step:.05},
                                {label:"Text scale", key:"panelTextScale", min:.7, max:2, step:.05}
                            ] : root.page === "Locus" ? [
                                {label:"Locus scale", key:"locusScale", min:.75, max:1.5, step:.05},
                                {label:"Text scale", key:"locusTextScale", min:.7, max:2, step:.05},
                                {label:"Normal width", key:"normalWidth", min:480, max:2000, step:10},
                                {label:"Preview width", key:"previewWidth", min:800, max:3000, step:10},
                                {label:"Height (0 = auto)", key:"locusHeight", min:0, max:2000, step:10}
                            ] : []
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: modelData.label; color: root.theme.ink; Layout.fillWidth: true }
                                    Label { text: String(Math.round(root.settings[modelData.key] * 100) / 100); color: root.theme.sumi }
                                }
                                Slider {
                                    Layout.fillWidth: true; from: modelData.min; to: modelData.max; stepSize: modelData.step
                                    value: root.settings[modelData.key]
                                    onMoved: root.settings.setSetting(modelData.key, modelData.key === "locusHeight" && value > 0 && value < 360 ? 360 : value)
                                }
                            }
                        }
                        ColumnLayout {
                            id: effectsControls
                            visible: root.page !== "Colors"
                            Layout.fillWidth: true
                            property string opacityKey: root.page === "Panels" ? "panelOpacity" : "locusOpacity"
                            property string blurKey: root.page === "Panels" ? "panelBlur" : "locusBlur"
                            property var customOpacity: root.settings[opacityKey]
                            property real effectiveOpacity: customOpacity == null ? root.theme.bg.a : customOpacity
                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Background opacity"; color: root.theme.ink; Layout.fillWidth: true }
                                Label { text: Math.round(effectsControls.effectiveOpacity * 100) + "%"; color: root.theme.sumi }
                            }
                            Slider {
                                objectName: "backgroundOpacity"
                                Layout.fillWidth: true; from: 0; to: 1; stepSize: .01
                                value: effectsControls.effectiveOpacity
                                onMoved: root.settings.setSetting(effectsControls.opacityKey, value)
                            }
                            Button {
                                objectName: "resetOpacity"
                                text: "Reset to theme"; enabled: effectsControls.customOpacity != null
                                onClicked: root.settings.setSetting(effectsControls.opacityKey, null)
                            }
                            Switch {
                                objectName: "blurBackground"
                                text: "Blur background"; checked: !!root.settings[effectsControls.blurKey]
                                onClicked: root.settings.setSetting(effectsControls.blurKey, checked)
                            }
                        }
                        Button { visible: root.page !== "Colors"; text: "Reset " + root.page; onClicked: root.settings.resetSection(root.page.toLowerCase()) }
                        Item { Layout.preferredHeight: 10 }
                    }
                }
                Label {
                    visible: root.page === "Colors" && root.palette && !root.palette.source.filename
                    text: "Save current is unavailable until this palette has a blueprint. Use Save as to create one."
                    color: root.theme.sumi; wrapMode: Text.Wrap; Layout.fillWidth: true
                }
                RowLayout {
                    visible: root.page === "Colors"; Layout.fillWidth: true
                    Button { text: "Reset all"; enabled: !!root.palette && !worker.running; onClicked: root.resetColors() }
                    Item { Layout.fillWidth: true }
                    Button { text: "Cancel"; enabled: root.dirty && !worker.running; onClicked: { root.invalidatePreview(); root.draft = root.clone(root.palette.overrides); root.theme.cancelPreview(); } }
                    Button { text: "Apply"; enabled: root.dirty && !worker.running; onClicked: root.commit("apply", "") }
                    Button { text: "Save current"; enabled: !!root.palette && !!root.palette.source.filename && !worker.running; onClicked: root.commit("save", "") }
                    Button { text: "Save as…"; enabled: !!root.palette && !worker.running; onClicked: { saveName.text = ""; root.saveAsPrompt = true; } }
                }
            }
        }
    }
    function qtColor(hex) {
        // Qt parses eight-digit strings as AARRGGBB; the API uses RRGGBBAA.
        return hex && hex.length === 9 ? "#" + hex.substring(7, 9) + hex.substring(1, 7) : hex;
    }
    Dialog {
        id: picker
        palette: chrome.palette
        implicitWidth: 440
        parent: Overlay.overlay
        modal: true; title: "Choose color"; anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Cancel
        property color selected: "white"
        property var priorDraft: ({})
        onAboutToShow: { priorDraft = root.clone(root.draft); selected = root.qtColor(root.colors[root.selectedRole]); }
        onRejected: { root.draft = priorDraft; root.syncDraftPreview(); }
        onAccepted: {
            root.updateColor(root.selectedRole, "#" + root.hexByte(selected.r) + root.hexByte(selected.g) + root.hexByte(selected.b) + root.hexByte(selected.a));
        }
        contentItem: ColumnLayout {
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 60; color: picker.selected; border.color: root.theme.sumi }
            Repeater {
                model: ["Hue", "Saturation", "Value", "Alpha"]
                delegate: RowLayout {
                    required property string modelData
                    required property int index
                    Label { text: modelData; Layout.preferredWidth: 90 }
                    Slider {
                        from: 0; to: 1; Layout.preferredWidth: 230
                        value: index === 0 ? Math.max(0, picker.selected.hsvHue) : index === 1 ? picker.selected.hsvSaturation : index === 2 ? picker.selected.hsvValue : picker.selected.a
                        onMoved: {
                            const c = picker.selected;
                            picker.selected = Qt.hsva(index === 0 ? value : Math.max(0, c.hsvHue), index === 1 ? value : c.hsvSaturation,
                                index === 2 ? value : c.hsvValue, index === 3 ? value : c.a);
                            const next = picker.selected;
                            root.updateColor(root.selectedRole, "#" + root.hexByte(next.r) + root.hexByte(next.g) + root.hexByte(next.b) + root.hexByte(next.a));
                        }
                    }
                }
            }
        }
    }
    Dialog {
        palette: chrome.palette
        implicitWidth: 440
        parent: Overlay.overlay; anchors.centerIn: parent; modal: true
        visible: root.closePrompt; title: "Unsaved color changes"
        closePolicy: Popup.NoAutoClose
        contentItem: Label { text: "Apply your changes before closing?" }
        footer: DialogButtonBox {
            Button { text: "Apply"; enabled: !worker.running; onClicked: { root.closeAfterApply = true; root.commit("apply", ""); } }
            Button { text: "Discard"; enabled: !worker.running; onClicked: { root.invalidatePreview(); root.theme.cancelPreview(); root.draft = root.clone(root.palette.overrides); root.closePrompt = false; root.visible = false; } }
            Button { text: "Keep editing"; onClicked: root.closePrompt = false }
        }
    }
    Dialog {
        palette: chrome.palette
        implicitWidth: 440
        parent: Overlay.overlay; anchors.centerIn: parent; modal: true
        visible: root.saveAsPrompt; title: "Save blueprint as"; standardButtons: Dialog.Save | Dialog.Cancel
        contentItem: TextField { id: saveName; placeholderText: "Blueprint name"; implicitWidth: 300 }
        onAccepted: { root.saveAsPrompt = false; if (saveName.text.trim()) root.commit("save-as", saveName.text.trim()); }
        onRejected: root.saveAsPrompt = false
    }
}
