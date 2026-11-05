import QtQuick
import Quickshell
import Quickshell.Io
import "ShellSettingsModel.js" as Model

Item {
    id: service
    visible: false
    property string stateDirectory: Quickshell.env("HOME") + "/.local/state/quickshell-desktop"
    readonly property string statePath: stateDirectory + "/settings.json"
    property var document: Model.initial()
    readonly property real panelScale: document.settings.panelScale
    readonly property real locusScale: document.settings.locusScale
    readonly property real panelTextScale: document.settings.panelTextScale
    readonly property real locusTextScale: document.settings.locusTextScale
    readonly property var panelOpacity: document.settings.panelOpacity
    readonly property var locusOpacity: document.settings.locusOpacity
    readonly property bool panelBlur: document.settings.panelBlur
    readonly property bool locusBlur: document.settings.locusBlur
    readonly property int normalWidth: document.settings.normalWidth
    readonly property int previewWidth: document.settings.previewWidth
    readonly property int locusHeight: document.settings.locusHeight
    readonly property int windowWidth: document.settings.windowWidth
    readonly property int windowHeight: document.settings.windowHeight
    property bool ready: false
    property bool writable: false
    property bool directoryReady: false
    property string lastError: ""
    property var pending: ({})
    function finish(doc, canWrite) {
        document = {version: 1, settings: Model.settings(Object.assign({}, doc.settings, pending))};
        writable = canWrite;
        ready = true;
        if (canWrite && Object.keys(pending).length) saveTimer.restart();
        pending = ({});
    }
    function setSetting(key, value) {
        if (!Object.prototype.hasOwnProperty.call(Model.defaults(), key)) return;
        const next = Model.settings(Object.assign({}, document.settings, {[key]: value}));
        document = {version: 1, settings: next};
        if (!ready) pending = Object.assign({}, pending, {[key]: next[key]});
        else if (writable) saveTimer.restart();
    }
    function resetSection(name) {
        const defaults = Model.defaults();
        for (const key of Model.sectionKeys(name)) setSetting(key, defaults[key]);
    }
    Process {
        command: ["mkdir", "-p", service.stateDirectory]
        running: true
        onExited: function(code) {
            if (code === 0) service.directoryReady = true;
            else { service.lastError = "Could not create settings directory"; service.finish(Model.initial(), false); }
        }
    }
    FileView {
        id: file
        path: service.directoryReady ? service.statePath : ""
        atomicWrites: true
        blockWrites: false
        printErrors: false
        onLoaded: {
            if (service.ready) return;
            try { service.finish(Model.normalize(JSON.parse(text())), true); }
            catch (error) { service.lastError = String(error) + "; existing settings.json was preserved"; service.finish(Model.initial(), false); }
        }
        onLoadFailed: function(error) {
            if (!service.directoryReady || service.ready) return;
            if (error === FileViewError.FileNotFound) service.finish(Model.initial(), true);
            else { service.lastError = "Could not read settings.json; existing file was preserved"; service.finish(Model.initial(), false); }
        }
        onSaveFailed: service.lastError = "Could not save settings.json"
        onSaved: service.lastError = ""
    }
    Timer { id: saveTimer; interval: 250; onTriggered: if (service.ready && service.writable) file.setText(JSON.stringify(service.document, null, 2) + "\n") }
    Component.onDestruction: {
        if (ready && writable && saveTimer.running) { file.blockWrites = true; file.setText(JSON.stringify(document, null, 2) + "\n"); }
    }
}
