import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import "BarSettingsModel.js" as Model

// One persistent owner. Never writes defaults before the initial read completes.
Item {
    id: service
    visible: false
    property string stateDirectory: Quickshell.env("HOME") + "/.local/state/quickshell-desktop"
    readonly property string statePath: stateDirectory + "/bar.json"
    property var document: Model.initial()
    property bool ready: false
    property bool writable: false
    property string lastError: ""
    property bool directoryReady: false
    property bool migrating: false
    property var legacy: ({})
    property var settled: ({})
    property var pendingSettings: ({})
    property var pendingTemplates: null
    property string pendingSelected: ""
    readonly property var legacyFiles: ["bar-edge", "bar-variant", "bar-transparent", "bar-type", "bar-height",
        "bar-opacity", "bar-air", "bar-rounding", "bar-templates.json", "bar-template"]

    function finish(value, canWrite) {
        const next = Object.assign({}, value);
        next.settings = Model.settings(Object.assign({}, next.settings, pendingSettings));
        if (pendingTemplates !== null) next.templates = pendingTemplates;
        if (pendingSelected) next.selectedTemplate = pendingSelected;
        document = Model.normalize(next);
        writable = canWrite;
        ready = true;
        if (canWrite && (migrating || Object.keys(pendingSettings).length || pendingTemplates !== null || pendingSelected)) saveTimer.restart();
        migrating = false;
    }
    function setSetting(key, value) {
        const next = Object.assign({}, document);
        next.settings = Model.settings(Object.assign({}, document.settings, {[key]: value}));
        document = next;
        if (!ready) pendingSettings = Object.assign({}, pendingSettings, {[key]: next.settings[key]});
        else if (writable) saveTimer.restart();
    }
    function setTemplates(value) {
        const next = Object.assign({}, document, {templates: Model.templates(value)});
        document = next;
        if (!ready) pendingTemplates = next.templates;
        else if (writable) saveTimer.restart();
    }
    function setSelected(value) {
        document = Object.assign({}, document, {selectedTemplate: value});
        if (!ready) pendingSelected = value;
        else if (writable) saveTimer.restart();
    }
    function legacyRead(name, value) {
        if (settled[name]) return;
        settled[name] = true;
        if (value !== null) legacy[name] = value.trim();
        if (Object.keys(settled).length === legacyFiles.length) finish(Model.migrate(legacy), true);
    }
    Process {
        command: ["mkdir", "-p", service.stateDirectory]
        running: true
        onExited: function(code) {
            if (code !== 0) {
                service.lastError = "Could not create bar settings directory";
                service.finish(Model.initial(), false);
            } else service.directoryReady = true;
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
            try { service.finish(Model.normalize(JSON.parse(file.text())), true); }
            catch (error) {
                service.lastError = String(error) + "; existing bar.json was preserved";
                console.warn(service.lastError);
                service.finish(Model.initial(), false);
            }
        }
        onLoadFailed: function(error) {
            if (!service.directoryReady || service.ready) return;
            if (error === FileViewError.FileNotFound) service.migrating = true;
            else {
                service.lastError = "Could not read bar settings; existing file was preserved";
                service.finish(Model.initial(), false);
            }
        }
        onSaveFailed: { service.lastError = "Could not save bar settings"; console.warn(service.lastError); }
        onSaved: service.lastError = ""
    }
    Instantiator {
        model: service.migrating ? service.legacyFiles : []
        delegate: FileView {
            required property string modelData
            path: service.stateDirectory + "/" + modelData
            printErrors: false
            onLoaded: service.legacyRead(modelData, text())
            onLoadFailed: service.legacyRead(modelData, null)
        }
    }
    Timer {
        id: saveTimer
        interval: 250
        onTriggered: if (service.ready && service.writable) file.setText(JSON.stringify(service.document, null, 2) + "\n")
    }
    Component.onDestruction: {
        if (ready && writable && saveTimer.running) {
            file.blockWrites = true;
            file.setText(JSON.stringify(document, null, 2) + "\n");
        }
    }
}
