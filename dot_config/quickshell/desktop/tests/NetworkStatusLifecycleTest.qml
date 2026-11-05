import QtQuick
import Quickshell

ShellRoot {
    id: test
    property int phase: 0
    property int count: 0
    property var latest: ({})
    property double stageAt: Date.now()
    property double started: Date.now()
    function check(ok, message) {
        if (!ok) { console.error(message); Qt.exit(1); throw new Error(message); }
    }
    NetworkStatusService {
        id: service
        helperCommand: ["python3", Quickshell.env("QS_TEST_STATUS_HELPER")]
        retryMs: 150
        onStatusChanged: function(status) { test.latest = status; test.count++; }
    }
    Timer {
        interval: 20; repeat: true; running: true
        onTriggered: {
            if (Date.now() - test.started > 7000) { test.check(false, "status lifecycle timeout at phase " + test.phase + " last=" + JSON.stringify(test.latest)); return; }
            switch (test.phase) {
            case 0:
                service.wifiEnabled = true;
                service.monitoringEnabled = true;
                test.phase = 1;
                break;
            case 1:
                if (test.latest.generation === 1) {
                    test.check(test.latest.mode === "wifi", "initial mode wrong");
                    service.monitoringEnabled = false;
                    test.stageAt = Date.now(); test.phase = 2;
                }
                break;
            case 2:
                if (Date.now() - test.stageAt > 180) {
                    test.count = 0; test.stageAt = Date.now(); test.phase = 3;
                }
                break;
            case 3:
                if (Date.now() - test.stageAt > 300) {
                    test.check(test.count === 0, "status updates continued while paused");
                    service.monitoringEnabled = true;
                    test.stageAt = Date.now(); test.phase = 4;
                }
                break;
            case 4:
                if (test.latest.generation === 2) {
                    test.check(Date.now() - test.stageAt < 1000, "resume was delayed");
                    test.check(test.latest.mode === "wifi", "resume mode wrong");
                    service.wifiEnabled = false; test.phase = 5;
                }
                break;
            case 5:
                if (test.latest.generation === 3) {
                    test.check(test.latest.mode === "links", "links-only mode wrong");
                    service.wifiEnabled = true; test.phase = 6;
                }
                break;
            case 6:
                if (test.latest.generation === 5) {
                    test.check(test.latest.mode === "wifi", "retry mode wrong");
                    service.wifiEnabled = false; test.phase = 7;
                }
                break;
            case 7:
                if (test.latest.generation === 6) {
                    service.monitoringEnabled = false;
                    test.stageAt = Date.now(); test.phase = 8;
                }
                break;
            case 8:
                if (Date.now() - test.stageAt > 400) {
                    test.check(test.latest.generation === 6, "watch restarted after pause during retry");
                    service.monitoringEnabled = true;
                    test.phase = 9;
                }
                break;
            case 9:
                if (test.latest.generation === 7) {
                    test.check(test.latest.mode === "links", "resume after retry used wrong mode");
                    service.monitoringEnabled = false;
                    console.log("network status lifecycle tests passed"); Qt.quit(); test.phase = 10;
                }
                break;
            }
        }
    }
}
