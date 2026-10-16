import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    Themes { id: themes; active: false }
    IpcHandler {
        target: "audit"
        function open() { themes.active = true; }
        function close() { themes.active = false; }
        function refresh() { themes.checkFreshness(); }
        function status(): string {
            return JSON.stringify({ loaded: themes.loaded, running: themes.running, items: themes.items });
        }
        function quit() { Qt.quit(); }
    }
}
