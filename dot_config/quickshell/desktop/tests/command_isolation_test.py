"""Real queues and EQ panel with private fake tools; never changes audio."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

SOURCE = Path(__file__).resolve().parents[1]
HELPER = r'''import json,os,sys,time
from pathlib import Path
root=Path(os.environ['QS_TEST_DIR'])
def log(**value):
 with open(root/'events.jsonl','a') as f: f.write(json.dumps(value)+'\n')
def write_state(value):
 p=root/(str(os.getpid())+'.tmp'); p.write_text(json.dumps(value)); p.replace(root/'eq-state.json')
action=sys.argv[1]
if action=='job':
 name,delay=sys.argv[2:4]
 log(event='start',kind='job',name=name); time.sleep(float(delay))
 log(event='end',kind='job',name=name); print(name); raise SystemExit(0)
active=root/'eq-active'
try:
 fd=os.open(active,os.O_CREAT|os.O_EXCL|os.O_WRONLY); os.close(fd)
except FileExistsError:
 log(event='overlap',kind='eq'); raise SystemExit(9)
code=0
try:
 state=json.loads((root/'eq-state.json').read_text())
 if action in ('live','apply'): state=json.loads(sys.argv[2]); write_state(state)
 log(event='start',kind='eq',action=action,preamp=state['preamp'],gain=state['bands'][0]['gain'])
 time.sleep(.18)
 if action in ('live','apply'):
  write_state(state) # deliberately late watcher notification of an older edit
  time.sleep(.17)
  if action=='live' and state['preamp']==13:
   print(json.dumps({'error':'EQ unavailable; press APPLY to initialize it'}),file=sys.stderr); code=1
 elif action=='save':
  state['activePreset']=sys.argv[2]; write_state(state)
  (root/'saved.json').write_text(json.dumps(state))
 elif action=='export':
  print('Preamp: '+str(state['preamp'])+' dB\nFilter 1: ON PK Fc 100 Hz Gain '+str(state['bands'][0]['gain'])+' dB Q 1')
 log(event='end',kind='eq',action=action,preamp=state['preamp'],gain=state['bands'][0]['gain'])
finally:
 active.unlink()
raise SystemExit(code)
'''

with tempfile.TemporaryDirectory(prefix="quickshell-command-test-") as directory:
    root = Path(directory)
    for name in ("CommandQueue.qml", "EqService.qml", "EqPanel.qml", "EqSlider.qml", "EqPresetsMenu.qml"):
        shutil.copy2(SOURCE / name, root / name)
    shutil.copy2(SOURCE / "tests/CommandIsolationTest.qml", root / "shell.qml")
    helper = root / "helper.py"
    helper.write_text(HELPER)
    initial = dict(enabled=True, preamp=0, activePreset="Flat", bands=[dict(freq=100, gain=0, q=1, type="peaking")])
    (root / "eq-state.json").write_text(json.dumps(initial))
    (root / "eq-presets.json").write_text(json.dumps({"Flat": initial}))
    clipboard = root / "wl-copy"
    clipboard.write_text("#!/usr/bin/env python3\nimport os,sys\nfrom pathlib import Path\nPath(os.environ['QS_TEST_DIR'],'clipboard').write_text(sys.stdin.read())\n")
    clipboard.chmod(0o755)
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_NO_XDG_DESKTOP_PORTAL="1",
               XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(root / "cache"),
               PATH=str(root) + os.pathsep + os.environ["PATH"], QS_TEST_DIR=str(root),
               QS_TEST_HELPER=str(helper), QS_TEST_EQ_STATE=str(root / "eq-state.json"),
               QS_TEST_EQ_PRESETS=str(root / "eq-presets.json"))
    env.pop("WAYLAND_DISPLAY", None)
    log_path = root / "test.log"
    with log_path.open("w+") as log:
        process = subprocess.Popen(["dbus-run-session", "--", "qs", "-p", str(root)], env=env,
                                   stdout=log, stderr=subprocess.STDOUT, start_new_session=True)

        def call(method, *args):
            result = subprocess.run(["qs", "-p", str(root), "ipc", "call", "audit", method, *map(str, args)],
                                    env=env, capture_output=True, text=True, timeout=5)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            return json.loads(result.stdout) if method == "status" else None

        def wait(predicate, timeout=6):
            deadline = time.monotonic() + timeout
            last = None
            while time.monotonic() < deadline:
                try:
                    last = call("status")
                except (RuntimeError, json.JSONDecodeError, subprocess.TimeoutExpired):
                    if process.poll() is not None:
                        raise RuntimeError("test shell exited")
                    time.sleep(.02)
                    continue
                if predicate(last):
                    return last
                time.sleep(.02)
            raise AssertionError(f"timeout; last status: {last}")

        def events():
            path = root / "events.jsonl"
            return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

        try:
            start = wait(lambda s: s["gain"] == 0, timeout=15)
            call("job", "left", "slow", "2", "")
            for name, key in (("old", "volume"), ("latest", "volume"), ("barrier", ""), ("old-after", "volume"), ("latest-after", "volume")):
                call("job", "left", name, "0", key)
            call("job", "right", "fast", "0", "")
            state = wait(lambda s: any(c["name"] == "fast" for c in s["completions"]))
            assert state["leftBusy"] and state["ticks"] > start["ticks"], "unrelated work or GUI heartbeat stalled"
            state = wait(lambda s: not s["leftBusy"])
            names = [c["name"] for c in state["completions"] if c["name"] != "fast"]
            assert names == ["slow", "latest", "barrier", "latest-after"], names
            assert all(c["output"].strip() == c["name"] for c in state["completions"])
            call("missing")
            wait(lambda s: not s["leftBusy"] and any(c["name"] == "missing" and c["code"] != 0 for c in s["completions"]))
            call("job", "left", "recovered", "0", "")
            wait(lambda s: any(c["name"] == "recovered" for c in s["completions"]))

            call("eqLive", "-1")
            wait(lambda s: s["eqBusy"])
            call("eqLive", "-2")
            call("gain", "6")
            call("gain", "9")
            time.sleep(.2)
            assert call("status")["gain"] == 9, "an older state-file notification overwrote a newer slider edit"
            state = wait(lambda s: not s["eqBusy"] and s["applied"])
            stored = json.loads((root / "eq-state.json").read_text())
            assert (stored["preamp"], stored["bands"][0]["gain"]) == (-2, 9)
            assert not any(e["event"] == "overlap" for e in events())

            call("eqLive", "13")
            state = wait(lambda s: not s["eqBusy"] and any(not r["success"] for r in s["eqResults"]))
            assert not state["applied"] and "press APPLY" in state["eqResults"][-1]["message"]
            call("apply")
            wait(lambda s: not s["eqBusy"] and s["applied"])
            call("eqLive", "-4")
            call("gain", "3")
            call("save", "Saved")
            wait(lambda s: not s["eqBusy"] and any(r["action"] == "save" and r["success"] for r in s["eqResults"]))
            saved = json.loads((root / "saved.json").read_text())
            assert saved["bands"][0]["gain"] == 3 and saved["activePreset"] == "Saved"
            call("exportEq")
            wait(lambda s: not s["eqBusy"] and any(r["action"] == "export" and r["success"] for r in s["eqResults"]))
            assert "Gain 3" in (root / "clipboard").read_text()

            call("eqLive", "-8")
            call("unload")
            wait(lambda s: not s["eqBusy"])
            assert json.loads((root / "eq-state.json").read_text())["preamp"] == -8
            call("launch", "app-survives", ".5")
            call("quit")
            assert process.wait(timeout=5) == 0
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline and not any(e.get("name") == "app-survives" and e["event"] == "end" for e in events()):
                time.sleep(.02)
            assert any(e.get("name") == "app-survives" and e["event"] == "end" for e in events())
            output = log_path.read_text()
            assert "WARN scene:" not in output and "TypeError" not in output and "ReferenceError" not in output, output
            print("command isolation, coalescing, app lifetime, EQ ordering, stale-state, and recovery tests passed")
        except BaseException:
            log.flush()
            print(log_path.read_text())
            raise
        finally:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
