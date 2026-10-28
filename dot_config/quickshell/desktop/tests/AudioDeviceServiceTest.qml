import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: test
    property int completions: 0
    function check(ok, message) {
        if (!ok) { console.error(message); Qt.exit(1); throw new Error(message); }
    }
    AudioDeviceService {
        id: service
        helperPath: Quickshell.env("QS_TEST_AUDIO_HELPER")
        onSettled: {
            test.completions++;
            marker.path = Quickshell.env("QS_TEST_AUDIO_DONE") + test.completions;
            marker.reload();
            test.check(marker.text() === "done", "settled fired before helper completion");
            if (test.completions === 1) {
                test.check(/fixture failure/.test(service.lastError), "first failure was not reported");
                test.check(service.busy, "queued command was lost on failure");
            } else if (test.completions === 2) {
                test.check(service.lastError === "", "success did not clear error");
                finishTimer.start();
            } else test.check(false, "unexpected settled signal");
        }
    }
    FileView { id: marker; blockLoading: true; printErrors: false }
    Timer {
        id: finishTimer
        interval: 40
        onTriggered: {
            test.check(!service.busy && test.completions === 2, "queue did not settle");
            console.log("audio device service lifecycle tests passed");
            Qt.quit();
        }
    }
    Timer { interval: 5000; running: true; onTriggered: { console.error("audio service fixture timed out"); Qt.exit(1); } }
    Component.onCompleted: {
        test.check(!service.selectDevice("sink", "", ""), "empty device accepted");
        test.check(service.selectDevice("sink", 'first $(printf injected) "quotes"', 'port `touch injected`'), "first switch rejected");
        test.check(service.selectDevice("source", "second $HOME \\ name", "port 'literal'"), "second switch rejected");
        test.check(service.busy && test.completions === 0, "switch did not become busy immediately");
    }
}
