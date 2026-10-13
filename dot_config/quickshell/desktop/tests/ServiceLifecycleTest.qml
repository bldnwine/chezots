import QtQuick
import Quickshell

ShellRoot {
    id: test
    property int phase: 0
    function check(ok, message) { if (!ok) throw new Error(message); }
    CalendarService {
        id: calendar
        eventsPath: Quickshell.env("QS_TEST_EVENTS")
        actionScript: Quickshell.env("QS_TEST_ACTION")
        syncCommand: ["python3", Quickshell.env("QS_TEST_SYNC")]
    }
    WarpService {
        id: warp
        pollingEnabled: false
        cliPath: Quickshell.env("QS_TEST_WARP")
        actionTimeoutMs: 100
        daemonTimeoutMs: 100
    }
    WarpService {
        id: startup
        pollingEnabled: false
        cliPath: Quickshell.env("QS_TEST_WARP")
        daemonCommandPrefix: ["python3", "-c", "pass"]
    }
    WarpService {
        id: stalled
        pollingEnabled: false
        cliPath: Quickshell.env("QS_TEST_WARP")
        daemonCommandPrefix: ["python3", "-c", "pass"]
        startReadinessTimeoutMs: 100
    }
    Timer {
        interval: 250; repeat: true; running: true
        onTriggered: {
            switch (test.phase++) {
            case 0:
                test.check(calendar.allEvents.length === 2, "initial cache did not load");
                calendar.viewVisible = true;
                break;
            case 1:
                test.check(calendar._syncFailures === 1, "failed sync loops or did not report error");
                test.check(calendar.lastError !== "", "sync failure is hidden");
                calendar.ensureFresh();
                calendar.viewVisible = false;
                test.check(calendar.editEvent("one", "event", "New title", "", "", "", false), "first edit rejected");
                test.check(!calendar.deleteEvent("two", "event"), "second action cancelled the first");
                test.check(calendar.allEvents[0].title === "New title" && calendar.allEvents[1].title === "Other", "optimism crossed calendar identity");
                calendar.viewVisible = false;
                break;
            case 2:
                test.check(calendar._syncFailures === 1, "cache reload retriggered a failed sync");
                test.check(calendar.allEvents[0].title === "Original", "failed edit was not rolled back");
                test.check(/denied/.test(calendar.lastError), "action error is hidden");
                test.check(calendar.editEvent("one", "event", "Time edit", "2026-10-12", "11:00", "12:00", false), "time edit rejected");
                warp.installed = true;
                warp.installedProbe = 1;
                warp._desired = 1;
                warp.applyStatus('{"status":"Unable","reason":{"ConnectivityCheckFailed":null}}',0,"");
                test.check(!warp.active && warp._desired === -1, "terminal failure remains optimistically connected");
                warp.applyRegistration('{"registration":{"device_id":"known","account":{"account_type":"Free"}}}');
                warp.applyRegistration('{}');
                test.check(warp.registered && warp.deviceId === "known", "transient registration failure erased good state");
                warp.mode = "warp";
                warp.applySettings('{"code":"Error","error":"failure"}');
                test.check(warp.mode === "warp", "settings error erased good state");
                warp.applyStatus('{"status":"Connected"}',0,"");
                test.check(warp.active && warp._desired === -1, "real connected state did not apply");
                break;
            case 3:
                test.check(!warp.busy, "fake detail reads did not complete");
                warp.setMode("hang");
                break;
            case 4:
                test.check(!warp.busy && /timed out/.test(warp.lastError), "action timeout did not release controls");
                warp.startDaemon();
                break;
            case 5:
                test.check(!warp.daemonTransition && /timed out/.test(warp.lastError), "daemon timeout did not release transition");
                warp.stopDaemon();
                break;
            case 6:
                test.check(!warp.daemonTransition && /timed out/.test(warp.lastError), "daemon stop timeout did not release transition");
                warp.copyText('literal $(printf injected) `printf injected` spaces', "Test copy");
                warp._desired = 1;
                warp.connecting = true;
                warp.statusText = "Connecting…";
                warp.runAction(["connect"], "Connecting…");
                break;
            case 7:
                test.check(!warp.connecting && warp._desired === -1 && warp.statusText === "Checking status…", "failed connect left a stale connecting label");
                test.check(calendar._syncFailures === 1, "failed sync retried without cooldown");
                startup.installed = true;
                startup.installedProbe = 1;
                startup.statusKnown = true;
                startup.daemonDown = true;
                startup.startDaemon();
                test.check(!startup.detailsReady && startup.daemonTransition, "start expanded the details too early");
                stalled.installed = true;
                stalled.installedProbe = 1;
                stalled.statusKnown = true;
                stalled.daemonDown = true;
                stalled.startDaemon();
                break;
            case 8:
                test.check(!stalled.daemonTransition && !stalled.detailsReady && /did not become ready/.test(stalled.lastError), "readiness timeout left a false expanded state");
                test.check(startup._daemonStartPending && !startup.detailsReady, "start command ended before readiness was confirmed");
                const beforeStale = startup._startGoodPolls;
                startup.applyStatus('{"status":"Disconnected"}', 0, "", startup._daemonEpoch - 1);
                test.check(startup._startGoodPolls === beforeStale, "a stale status poll settled startup");
                startup.applyStatus('{"code":"FailedToConnectToDaemon","error":"daemon is not running"}', 1, "");
                test.check(!startup.detailsReady, "transient daemon failure expanded the details");
                startup.applyStatus('{"status":"Connecting","reason":{"ConnectivityCheck":null}}', 0, "");
                test.check(!startup.detailsReady, "one response expanded the details");
                startup.applyStatus('{"status":"Disconnected"}', 0, "");
                test.check(startup.detailsReady && !startup.daemonTransition, "ready daemon did not expand the details");
                startup.applyStatus('{"code":"FailedToConnectToDaemon","error":"daemon is not running"}', 1, "");
                test.check(startup.detailsReady, "one transient failure collapsed the details");
                startup.applyStatus('{"status":"Disconnected"}', 0, "");
                test.check(startup.detailsReady, "recovery changed detail visibility");
                startup.applyStatus('{}', 0, "");
                test.check(startup.detailsReady, "invalid status erased the last known daemon state");
                startup.applyStatus('{"status":"Connecting","reason":{"ConnectivityCheck":null}}', 0, "");
                test.check(!startup.connecting && startup.displayStatusText === "Verifying connectivity", "connectivity check claimed a tunnel attempt");
                startup.applyStatus('{"status":"Connecting"}', 0, "");
                test.check(startup.connecting && startup.displayStatusText === "Connecting", "real connecting state was hidden");
                startup.applyStatus('{"code":"FailedToConnectToDaemon","error":"daemon is not running"}', 1, "");
                startup.applyStatus('{"code":"FailedToConnectToDaemon","error":"daemon is not running"}', 1, "");
                test.check(!startup.detailsReady && startup.daemonDown, "confirmed daemon failure stayed expanded");
                break;
            case 9:
                console.log("service lifecycle regression tests passed");
                Qt.quit();
            }
        }
    }
}
