import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: test
    property int bursts: 0

    TelemetryService {
        id: telemetry
        systemEnabled: false
        burstEnabled: false
        statPath: Quickshell.env("QS_TEST_STAT")
        memoryPath: Quickshell.env("QS_TEST_MEMORY")
        networkPath: Quickshell.env("QS_TEST_NETWORK")
        // Explicit requests drive fixture updates without competing ticks.
        systemIntervalMs: 60000
        burstIntervalMs: 60000
        onNetBurst: test.bursts += 1
    }
    TelemetryService { id: live }

    IpcHandler {
        target: "audit"
        function status(): string {
            return JSON.stringify({
                cpu: telemetry.cpuVal, memory: telemetry.memVal,
                phase: telemetry._phase, statBusy: telemetry._statBusy,
                memoryBusy: telemetry._memoryBusy,
                bytes: telemetry.netBytes, netBusy: telemetry._netBusy,
                armed: telemetry.burstArmed, bursts: test.bursts,
                liveCpu: live.cpuVal, liveMemory: live.memVal, liveBytes: live.netBytes,
                livePhase: live._phase, window: telemetry.cpuWindowMs
            });
        }
        function request() { telemetry.requestSystemSample(); }
        function system(enabled: bool) { telemetry.systemEnabled = enabled; }
        function network(enabled: bool) { telemetry.burstEnabled = enabled; }
        function sampleNetwork() { telemetry.requestNetworkSample(); }
        function quit() {
            telemetry.systemEnabled = false;
            telemetry.burstEnabled = false;
            live.systemEnabled = false;
            live.burstEnabled = false;
            shutdown.start();
        }
    }
    Timer {
        id: shutdown
        interval: 10
        repeat: true
        onTriggered: {
            if (telemetry._statBusy || telemetry._memoryBusy || telemetry._netBusy
                || live._statBusy || live._memoryBusy || live._netBusy) return;
            stop();
            Qt.quit();
        }
    }
}
