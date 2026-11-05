"""Exercise Navbar's workspace state with a fake native Hyprland singleton."""
import os
from pathlib import Path
import re
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
navbar = (source / 'Navbar.qml').read_text()
state = navbar.split('    // ---------- State ----------\n', 1)[1]
state = state.split('    property int cpuVal:', 1)[0]
completed = navbar.split('    Component.onCompleted: {', 1)[1].split('\n    }', 1)[0]
startup = re.search(r'^\s*syncFocusedWorkspace\(true\);', completed, re.M)
assert startup, 'Navbar must synchronize already-populated native state at startup'

with tempfile.TemporaryDirectory(prefix='qs-workspace-test-') as directory:
    root = Path(directory)
    (root / 'WorkspaceState.qml').write_text(
        'import QtQuick\nItem {\n id: root\n required property var hyprland\n'
        + state.replace('Hyprland', 'root.hyprland')
        + '\n Component.onCompleted: {' + startup.group() + '\n}\n}\n')
    (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
    QtObject {
        id: populated
        property var focusedWorkspace: ({id: 7})
        property var toplevels: ({values: []})
    }
    QtObject {
        id: delayed
        property var focusedWorkspace: null
        property var toplevels: ({values: []})
    }
    WorkspaceState { id: ready; hyprland: populated }
    WorkspaceState { id: waiting; hyprland: delayed }
    function check(condition, message) {
        if (!condition) throw new Error(message);
    }
    Timer {
        interval: 20
        running: true
        onTriggered: {
            try {
                check(ready.activeWs === 7, "startup must use the current workspace");
                check(ready.lastDirection === 0, "startup must not animate fake travel");
                check(waiting.activeWs === 1, "missing native state retains the fallback");
                delayed.focusedWorkspace = {id: 4};
                check(waiting.activeWs === 4, "late native state must synchronize");
                populated.focusedWorkspace = {id: 9};
                check(ready.activeWs === 9 && ready.lastDirection === 1, "forward switch");
                populated.focusedWorkspace = {id: 3};
                check(ready.activeWs === 3 && ready.lastDirection === -1, "backward switch");
                populated.focusedWorkspace = null;
                check(ready.activeWs === 3, "transient missing focus retains known state");
                populated.focusedWorkspace = {id: 3};
                check(ready.lastDirection === -1, "same workspace does not invent travel");
                for (let i = 1; i <= 9; i++) populated.focusedWorkspace = {id: i};
                check(ready.activeWs === 9, "burst ends on the latest workspace");
                console.log("workspace state regression tests passed");
                Qt.quit();
            } catch (error) {
                console.error(error);
                Qt.exit(1);
            }
        }
    }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_NO_XDG_DESKTOP_PORTAL='1')
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(root)],
                            env=env, capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    if result.returncode or 'workspace state regression tests passed' not in output or 'WARN scene:' in output:
        print(output, end='')
        raise SystemExit(1)
    print('workspace state regression tests passed')
