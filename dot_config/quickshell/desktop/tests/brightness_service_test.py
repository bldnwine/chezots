from pathlib import Path
import os
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='quickshell-brightness-test-') as tmp:
    directory = Path(tmp)
    shutil.copy2(root / 'BrightnessService.qml', directory)
    shutil.copy2(root / 'tests/BrightnessServiceTest.qml', directory / 'shell.qml')
    helper = directory / 'helper.py'
    helper.write_text('''import json, os, pathlib, sys, time
kind, output, value = sys.argv[1:]
if output == "slow": time.sleep(.12)
if output == "hang": time.sleep(3)
if output == "bad": print("bad"); sys.exit(0)
state = pathlib.Path(os.environ["QS_TEST_BRIGHTNESS_STATE"])
current = float(state.read_text()) if state.exists() else 50
previous = current
if output == "eDP-1":
    if kind in ("set", "dim"): current = float(value)
    elif kind == "step": current += float(value)
    state.write_text(str(current))
result = {"ok": True, "output": output, "percentage": current}
if kind == "dim": result["previousPercentage"] = previous
print(json.dumps(result))
''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_NO_XDG_DESKTOP_PORTAL='1',
               QS_TEST_BRIGHTNESS_HELPER=str(helper), QS_TEST_BRIGHTNESS_STATE=str(directory / 'state'))
    p = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(directory)], env=env,
                       capture_output=True, text=True, timeout=12)
    output = p.stdout + p.stderr
    if p.returncode or 'brightness service lifecycle tests passed' not in output or 'WARN scene:' in output:
        print(output)
        raise SystemExit(1)
    print('brightness service lifecycle tests passed')
