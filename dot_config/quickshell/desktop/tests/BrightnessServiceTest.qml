import QtQuick
import Quickshell
import "." as Desktop

ShellRoot {
    id: test
    property int phase: 0
    property var results: []
    property var errors: []
    property double started: Date.now()
    function check(condition, message) { if (!condition) { console.error(message); Qt.exit(1); throw new Error(message); } }
    Desktop.BrightnessService {
        id: service
        helperCommand: ["python3", Quickshell.env("QS_TEST_BRIGHTNESS_HELPER")]
        timeoutMs: 300
        onBrightnessChanged: (output, pct) => test.results = test.results.concat([output + ":" + pct])
        onBrightnessRemembered: (output, pct) => test.results = test.results.concat(["remember:" + output + ":" + pct])
        onActionFailed: (output, message) => test.errors = test.errors.concat([output + ":" + message])
    }
    Timer {
        running: true; repeat: true; interval: 20
        onTriggered: {
            if (Date.now() - test.started > 8000) { test.check(false, "test timeout phase " + test.phase); return; }
            if (test.phase === 0) {
                service.refresh("slow");
                service.setBrightness("eDP-1", 10);
                service.setBrightness("eDP-1", 20);
                service.stepBrightness("eDP-1", 5);
                service.stepBrightness("eDP-1", 5);
                service.stepBrightness("eDP-1", -5);
                service.rememberAndSet("eDP-1", 15);
                service.setBrightness("eDP-1", 30);
                service.setBrightness("eDP-1", 40);
                test.phase = 1;
            } else if (test.phase === 1 && !service.busy) {
                test.check(JSON.stringify(test.results) === JSON.stringify(["slow:50", "eDP-1:20", "eDP-1:30", "eDP-1:25", "remember:eDP-1:25", "eDP-1:15", "eDP-1:40"]), "order/coalescing mismatch " + JSON.stringify(test.results));
                service.refresh("hang"); service.refresh("eDP-1"); test.phase = 2;
            } else if (test.phase === 2 && !service.busy) {
                test.check(test.errors.length === 1 && test.errors[0].indexOf("timed out") >= 0, "timeout not reported " + JSON.stringify(test.errors));
                test.check(service.stateByOutput["eDP-1"] === 40, "queue did not resume after timeout");
                service.refresh("bad"); test.phase = 3;
            } else if (test.phase === 3 && !service.busy) {
                test.check(test.errors.length === 2, "malformed response not rejected");
                test.check(service.stateByOutput["eDP-1"] === 40, "failure erased cached value");
                test.results = [];
                service.refresh("slow");
                service.setBrightness("slow", 90);
                service.cancelOutput("slow");
                service.refresh("eDP-1");
                test.phase = 4;
            } else if (test.phase === 4 && !service.busy) {
                test.check(JSON.stringify(test.results) === JSON.stringify(["eDP-1:40"]), "cancelled output published or queued work ran " + JSON.stringify(test.results));
                test.check(service.stateByOutput.slow === undefined, "cancelled output retained cached state");
                test.results = [];
                service.rememberAndSet("eDP-1", 30);
                service.restoreRemembered("eDP-1");
                service.restoreRemembered("unremembered");
                test.phase = 5;
            } else if (test.phase === 5 && !service.busy) {
                test.check(JSON.stringify(test.results) === JSON.stringify(["remember:eDP-1:40", "eDP-1:30", "eDP-1:40"]), "immediate restore ordering or unknown restore failed " + JSON.stringify(test.results));
                test.check(service.stateByOutput["eDP-1"] === 40 && service.stateByOutput.unremembered === undefined, "restore state incorrect");
                test.check(test.errors.length === 2, "unknown restore reported an error");
                console.log("brightness service lifecycle tests passed"); Qt.quit(); test.phase = 6;
            }
        }
    }
}
