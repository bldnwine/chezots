"""Exercise the QML queue with a private fake helper and no audio access."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="qs-audio-device-service-") as directory:
    root = Path(directory)
    for name in ("AudioDeviceService.qml", "CommandQueue.qml"):
        shutil.copy2(source / name, root / name)
    shutil.copy2(source / "tests/AudioDeviceServiceTest.qml", root / "shell.qml")
    helper = root / "fake_audio.py"
    helper.write_text('''import json, os, sys, time
from pathlib import Path
request = json.loads(sys.argv[1])
number = 1 if request['kind'] == 'sink' else 2
log = Path(os.environ['QS_TEST_AUDIO_LOG'])
with log.open('a') as out: out.write(json.dumps(['start', number, request]) + '\\n')
time.sleep(.15)
with log.open('a') as out: out.write(json.dumps(['end', number]) + '\\n')
Path(os.environ['QS_TEST_AUDIO_DONE'] + str(number)).write_text('done')
if number == 1:
    print('fixture failure', file=sys.stderr)
    raise SystemExit(1)
''')
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_NO_XDG_DESKTOP_PORTAL="1",
               DBUS_SESSION_BUS_ADDRESS="", QS_TEST_AUDIO_HELPER=str(helper),
               QS_TEST_AUDIO_LOG=str(root / "calls.jsonl"), QS_TEST_AUDIO_DONE=str(root / "done"))
    result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(root)],
                            env=env, capture_output=True, text=True, timeout=10)
    output = result.stdout + result.stderr
    if result.returncode or "audio device service lifecycle tests passed" not in output or "WARN scene:" in output:
        print(output)
        raise SystemExit(1)
    calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
    assert [call[:2] for call in calls] == [["start", 1], ["end", 1], ["start", 2], ["end", 2]], calls
    assert calls[0][2] == {"kind": "sink", "name": 'first $(printf injected) "quotes"', "port": "port `touch injected`"}, calls
    assert calls[2][2] == {"kind": "source", "name": "second $HOME \\ name", "port": "port 'literal'"}, calls
    print("audio device service lifecycle tests passed")
