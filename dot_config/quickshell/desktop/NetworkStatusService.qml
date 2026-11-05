import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: service
    property bool monitoringEnabled: false
    property bool wifiEnabled: false
    property var helperCommand: ["python3", Quickshell.shellDir + "/scripts/network_status.py"]
    property int retryMs: 3000
    signal statusChanged(var status)

    function restart() {
        retry.stop();
        if (watch.running) watch.running = false;
        if (monitoringEnabled) watch.running = true;
    }
    onMonitoringEnabledChanged: restart()
    onWifiEnabledChanged: if (monitoringEnabled) restart()

    Process {
        id: watch
        command: service.helperCommand.concat(service.wifiEnabled ? [] : ["--links-only"])
        stdout: SplitParser {
            onRead: function(line) {
                if (!service.monitoringEnabled) return;
                try { service.statusChanged(JSON.parse(line)); }
                catch (error) { console.warn("Invalid network status", error); }
            }
        }
        onExited: if (service.monitoringEnabled && !watch.running) retry.restart()
    }
    Timer {
        id: retry
        interval: service.retryMs
        onTriggered: if (service.monitoringEnabled && !watch.running) watch.running = true
    }
}
