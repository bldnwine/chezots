"""Check notification list sizing with production delegates and private data."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys

sys.dont_write_bytecode = True
from popup_test_support import write_card

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="qs-notification-layout-") as directory:
    root = Path(directory)
    write_card(root)
    for name in ("NotificationCard.qml", "NotificationPopup.qml"):
        shutil.copy2(source / name, root / name)
    popup = root / "NotificationPopup.qml"
    popup.write_text(popup.read_text().replace("    id: popup", """    id: popup
    readonly property var testList: notifListView
""", 1))
    (root / "shell.qml").write_text('''import QtQuick
import Quickshell
ShellRoot {
    Window {
        visible: true; width: 900; height: 700
        Item {
            id: state
            property real panelScale: 1
            property real panelTextScale: 1
            property real testPanelWidth: 900
            property real testPanelHeight: 700
            property bool notificationCenterVisible: false
            property bool doNotDisturb: false
            property string barEdge: "top"
            property int barOffset: 35
            property int popupAnchorX: 450
            property int popupAnchorY: 0
            property int cornerRadius: 0
            property string mono: "monospace"
            property color bg: "#222222"
            property color ink: "white"
            property color inkDeep: "gray"
            property color seal: "yellow"
            property color accent: "yellow"
            property color sep: "gray"
            property color rowHi: "#333333"
            property color rowSel: "#555555"
            property var notificationCenterService: QtObject {
                property var entries: [{key:"fixture", app:"", summary:"A long notification summary", body:"A long notification body. ".repeat(30), timestamp:1}]
                property int unread: 0
                property double lastSeen: 0
                signal entryAdded(var entry)
                signal entriesReset()
                function load() {}
                function markSeen() {}
            }
        }
        NotificationPopup { id: popup; root: state }
        Timer {
            interval: 250; running: true; repeat: true
            property int phase: 0
            property real initialHeight: 0
            function check(ok, message) { if (!ok) { console.error(message); Qt.exit(1); throw new Error(message); } }
            onTriggered: {
                phase++;
                if (phase === 1) { state.notificationCenterVisible = true; return; }
                if (phase === 2) {
                    const entry = popup.testList.itemAtIndex(0);
                    check(entry !== null && entry.width === popup.testList.width, "delegate width follows viewport");
                    initialHeight = entry.implicitHeight;
                    state.panelScale = 1.5; state.panelTextScale = 2;
                    state.testPanelWidth = 400; state.testPanelHeight = 400;
                    popup.searching = true;
                    return;
                }
                const entry = popup.testList.itemAtIndex(0);
                check(entry !== null && entry.width === popup.testList.width, "scaled delegate width follows viewport");
                check(entry.fontScale === 3 && entry.implicitHeight > initialHeight, "notification text reflows at requested scale");
                check(popup.testList.height > 0, "search leaves a positive list viewport");
                check(popup.testSurfaceHeight <= state.testPanelHeight && popup.testSurfaceWidth <= state.testPanelWidth, "card fits short screen");
                console.log("notification popup geometry passed"); Qt.quit();
            }
        }
    }
}''')
    env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / "config"),
               QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_NO_XDG_DESKTOP_PORTAL="1")
    result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(root)],
                            env=env, capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    if result.returncode or "notification popup geometry passed" not in output or "WARN scene:" in output:
        print(output)
        raise SystemExit(1)
print("notification popup geometry passed")
