import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: test
    property int ticks: 0
    property var completions: []
    property var eqResults: []
    readonly property string helper: Quickshell.env("QS_TEST_HELPER")
    function record(job, code, output, error) {
        completions = completions.concat([{ name: job.context.name, code: code, output: output, error: error }]);
    }
    CommandQueue { id: left; label: "test-left"; onFinished: (job, code, output, error) => test.record(job, code, output, error) }
    CommandQueue { id: right; label: "test-right"; onFinished: (job, code, output, error) => test.record(job, code, output, error) }
    EqService {
        id: eq
        scriptPath: test.helper
        statePath: Quickshell.env("QS_TEST_EQ_STATE")
        presetsPath: Quickshell.env("QS_TEST_EQ_PRESETS")
        onCompleted: (action, success, message) => test.eqResults = test.eqResults.concat([{action: action, success: success, message: message}])
    }
    QtObject {
        id: fakeTheme
        property var eqService: eq
        property color bg: "#111111"
        property color ink: "#eeeeee"
        property color fg: "#cccccc"
        property color inkDeep: "#aaaaaa"
        property color seal: "#ff9999"
        property color sep: "#444444"
        property color rowHi: "#333333"
        property color rowSel: "#555555"
        property string mono: "monospace"
        property int cornerRadius: 0
    }
    Loader { id: panel; sourceComponent: EqPanel { root: fakeTheme; width: 360 } }
    Timer { interval: 16; running: true; repeat: true; onTriggered: test.ticks += 1 }
    IpcHandler {
        target: "audit"
        function job(owner: string, name: string, delay: string, key: string) {
            (owner === "left" ? left : right).enqueue(["python3", test.helper, "job", name, delay], key, {name: name});
        }
        function launch(name: string, delay: string) { Quickshell.execDetached(["python3", test.helper, "job", name, delay]); }
        function missing() { left.enqueue(["/qs-test-no-such-command"], "", {name: "missing"}); }
        function eqLive(value: string) { panel.item.preamp = Number(value); panel.item.applyLive(); }
        function gain(value: string) { panel.item.setBandGain(0, Number(value)); }
        function save(name: string) { panel.item.savePreset(name); }
        function apply() { panel.item.applyEq(); }
        function exportEq() { panel.item.runExport(); }
        function unload() { panel.active = false; }
        function status(): string {
            return JSON.stringify({ticks: ticks, leftBusy: left.busy, rightBusy: right.busy,
                completions: completions, eqBusy: eq.busy, applied: eq.isApplied,
                eqResults: eqResults, gain: panel.item && panel.item.bands.length ? panel.item.bands[0].gain : null,
                preamp: panel.item ? panel.item.preamp : null});
        }
        function quit() { shutdown.start(); }
    }
    Timer { id: shutdown; interval: 100; onTriggered: Qt.quit() }
}
