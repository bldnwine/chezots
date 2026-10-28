import QtQuick
import Quickshell

Item {
    id: service
    visible: false
    property string helperPath: Quickshell.shellDir + "/scripts/audio-device-helper.py"
    readonly property bool busy: queue.busy
    readonly property string lastError: queue.lastError
    signal settled()

    function selectDevice(kind, name, port) {
        if (!name) return false;
        return queue.enqueue(["python3", helperPath,
            JSON.stringify({kind: kind, name: name, port: port || ""})], "", {});
    }

    CommandQueue {
        id: queue
        label: "audio device"
        onFinished: service.settled()
    }
}
