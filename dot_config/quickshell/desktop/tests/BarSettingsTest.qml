import QtQuick
import Quickshell
import "." as Desktop

ShellRoot {
    id: test
    property string mode: Quickshell.env("QS_TEST_MODE")
    property int phase: 0
    function check(value, message) { if (!value) throw new Error(message); }
    Desktop.BarSettings {
        id: settings
        stateDirectory: Quickshell.env("QS_TEST_STATE")
        Component.onCompleted: if (test.mode === "migration") setSetting("height", 37)
    }
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (!settings.ready) return;
            if (test.phase++ === 0) {
                if (test.mode === "savefail") {
                    settings.stateDirectory += "/bar.json";
                    settings.setSetting("air", 50);
                } else if (test.mode === "shutdown") {
                    settings.setSetting("air", 23);
                    console.log("bar settings lifecycle tests passed");
                    Qt.quit();
                    return;
                } else if (test.mode === "corrupt") {
                    test.check(!settings.writable && settings.lastError.length > 0, "corrupt JSON became writable");
                    settings.setSetting("height", 40);
                } else if (test.mode === "migration") {
                    test.check(settings.document.settings.edge === "left", "legacy edge was lost");
                    test.check(settings.document.settings.height === 37, "pending edit lost during loading");
                    test.check(settings.document.selectedTemplate === "desk", "selected template lost");
                    for (let i = 0; i < 20; i++) settings.setSetting("air", i);
                    settings.setTemplates({newdesk: {height: 30}});
                    settings.setSelected("newdesk");
                } else {
                    test.check(settings.document.settings.air === 19, "restart did not restore latest setting");
                    test.check(settings.document.selectedTemplate === "newdesk", "restart did not restore template");
                }
            }
            if (test.phase >= 5) {
                test.check(test.mode === "corrupt" || test.mode === "savefail" || settings.lastError === "", settings.lastError);
                if (test.mode === "savefail") test.check(settings.lastError.length > 0, "save failure hidden");
                console.log("bar settings lifecycle tests passed");
                Qt.quit();
            }
        }
    }
    Timer { interval: 5000; running: true; onTriggered: { throw new Error("settings initialization timed out"); } }
}
