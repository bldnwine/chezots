"""Private QML lifecycle: worker reuse, hidden refresh, and shutdown."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='qs-ai-worker-') as directory:
    root = Path(directory)
    shutil.copy2(source / 'AiService.qml', root / 'AiService.qml')
    (root / 'scanner.py').write_text('''import json,sys,os
with open(os.environ['AI_WORKER_LOG'],'a') as f: f.write('start\\n')
for line in sys.stdin:
    request=json.loads(line)
    with open(os.environ['AI_WORKER_LOG'],'a') as f: f.write('scan\\n')
    print(json.dumps(dict(ready=True,agentRunning=False,sessionCount=0)),flush=True)
''')
    (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
    AiService { id: ai; scannerScript: Qt.resolvedUrl("scanner.py").toString().replace("file://", "") }
    property int step: 0
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (ai.refreshing || !ai.ready) return;
            if (step === 0) {
                if (!ai._workerStarted) { Qt.exit(1); return; }
                ai.refresh(false);
            } else if (step === 1) {
                if (!ai._workerStarted) { Qt.exit(2); return; }
                ai.pollingEnabled = false;
            } else if (step === 2) {
                if (ai._workerStarted) return;
                ai.refresh(true);
            } else {
                if (ai._workerStarted) return;
                console.log("AI worker lifecycle passed"); Qt.quit();
            }
            step++;
        }
    }
    Timer { interval: 6000; running: true; onTriggered: Qt.exit(3) }
}
''')
    log = root / 'worker.log'
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_NO_XDG_DESKTOP_PORTAL='1', AI_WORKER_LOG=str(log))
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(root)], env=env,
                            capture_output=True, text=True, timeout=10)
    output = result.stdout + result.stderr
    if result.returncode or 'AI worker lifecycle passed' not in output or 'WARN scene:' in output:
        raise AssertionError(output)
    calls = log.read_text().splitlines()
    assert calls.count('start') == 2, calls
    assert calls.count('scan') == 3, calls
    print('AI worker lifecycle passed')
