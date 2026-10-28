"""Compile integrated QML surfaces without instantiating desktop services."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
files = ['Navbar.qml', 'AudioPopup.qml', 'BluetoothPopup.qml', 'DisplayPopup.qml', 'Osd.qml', 'shell.qml']
urls = [(source / name).as_uri() for name in files]
with tempfile.TemporaryDirectory(prefix='quickshell-adoption-compile-') as directory:
    root = Path(directory)
    (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
    Timer {
      interval: 50
      running: true
      onTriggered: {
        const files = ''' + json.dumps(urls) + ''';
        for (const file of files) {
            const component = Qt.createComponent(file);
            if (component.status !== Component.Ready) {
                console.error(component.errorString());
                Qt.exit(1);
                return;
            }
        }
        console.log("integrated QML compilation passed");
        Qt.quit();
      }
    }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM='wayland', QT_NO_XDG_DESKTOP_PORTAL='1')
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(root)], env=env,
                            capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    if result.returncode or 'integrated QML compilation passed' not in output or 'WARN scene:' in output:
        print(output)
        raise SystemExit(1)
    print('integrated QML compilation passed')
