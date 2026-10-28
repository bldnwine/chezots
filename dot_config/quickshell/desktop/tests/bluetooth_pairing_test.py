"""Run the Bluetooth service against a fake pairing helper and private session bus."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='bluetooth-pairing-') as directory:
    root = Path(directory)
    (root / 'runtime').mkdir(mode=0o700)
    shutil.copy2(source / 'BluetoothService.qml', root / 'BluetoothService.qml')
    shutil.copy2(source / 'tests/BluetoothPairingTest.qml', root / 'shell.qml')
    cli = root / 'agent'
    cli.write_text('#!/bin/sh\nsleep 0.25\nexit 0\n')
    cli.chmod(0o755)
    marker = root / 'cancelled'
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_NO_XDG_DESKTOP_PORTAL='1',
               XDG_RUNTIME_DIR=str(root / 'runtime'), QS_PAIR_FIXTURE=str(source / 'tests/bluetooth_pair_fixture.py'),
               QS_PAIR_MARKER=str(marker), QS_TEST_AGENT=str(cli))
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(root)], env=env,
                            capture_output=True, text=True, timeout=10)
    output = result.stdout + result.stderr
    if result.returncode or 'Bluetooth pairing lifecycle tests passed' not in output:
        raise AssertionError(output)
    assert marker.read_text() == 'cancel\n', 'helper did not receive cancellation'
print('Bluetooth pairing lifecycle tests passed')
