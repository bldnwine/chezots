#!/usr/bin/env python3
"""Exercise the status watcher's process lifecycle against a fake helper."""
import os
from pathlib import Path
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='qs-network-status-') as temp:
    root = Path(temp)
    (root / 'NetworkStatusService.qml').write_bytes((source / 'NetworkStatusService.qml').read_bytes())
    (root / 'shell.qml').write_bytes((source / 'tests/NetworkStatusLifecycleTest.qml').read_bytes())
    helper = root / 'helper.py'
    helper.write_text('''import json, os, pathlib, sys, time
counter = pathlib.Path(os.environ['QS_TEST_STATUS_COUNTER'])
generation = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(generation))
mode = 'links' if '--links-only' in sys.argv else 'wifi'
if generation in (4, 6):
    print(json.dumps({'generation': generation, 'mode': mode}), flush=True)
    sys.exit(1)
while True:
    print(json.dumps({'generation': generation, 'mode': mode}), flush=True)
    time.sleep(.08)
''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_NO_XDG_DESKTOP_PORTAL='1',
               DBUS_SESSION_BUS_ADDRESS='', QS_TEST_STATUS_HELPER=str(helper),
               QS_TEST_STATUS_COUNTER=str(root / 'counter'))
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(root)],
                            env=env, capture_output=True, text=True, timeout=12)
    output = result.stdout + result.stderr
    if result.returncode or 'network status lifecycle tests passed' not in output or 'WARN scene:' in output:
        print(output, end='')
        raise SystemExit(1)
    assert (root / 'counter').read_text() == '7'
    print('network status lifecycle regression tests passed')
