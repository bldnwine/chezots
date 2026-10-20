#!/usr/bin/env python3
"""Run NetworkService against a private, deterministic helper fixture."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parents[1]
FAKE_HELPER = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
try: req=json.loads(sys.stdin.readline())
except Exception: req={}
with open(os.environ['QS_TEST_NETWORK_LOG'],'a') as f: f.write(req.get('op','?')+' '+req.get('ssid','')+'\n')
with open(os.environ['QS_TEST_NETWORK_TIMES'],'a') as f: f.write(json.dumps([time.monotonic(),req.get('op')])+'\n')
if req.get('ssid') == 'timeout-fixture': time.sleep(4)
if req.get('ssid') == 'slow-fixture': time.sleep(.15)
mode=sys.argv[1] if len(sys.argv)>1 else ''
if mode == 'late-scan' and req.get('op') == 'scan':
    import signal
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(.2)
if mode == 'malformed' and req.get('op') in ('scan','state'):
    print('not-json'); raise SystemExit(0)
if mode == 'bad-details' and req.get('op') == 'details':
    print('{"ok":true,"info":{"iface":"bad"}}'); raise SystemExit(0)
if mode == 'hang-scan' and req.get('op') == 'scan': time.sleep(4)
if req.get('op') in ('scan','state'):
    print(json.dumps({'ok':True,'radioOn':True,'networks':[{'ssid':'fixture','signal':80,'security':'psk','inUse':False,'known':True}]}))
elif req.get('op') == 'details':
    print(json.dumps({'ok':True,'info':{'iface':'test0','ip':'127.0.0.1','gateway':'127.0.0.1','rx_bytes':100,'tx_bytes':200,'sample_time':1.0,'internet_ping_ms':None}}))
else:
    print(json.dumps({'ok':True,'ssid':req.get('ssid'),'enabled':req.get('enabled')}))
'''

with tempfile.TemporaryDirectory(prefix="qs-network-service-") as temp:
    root = Path(temp)
    (root / "NetworkService.qml").write_bytes((SOURCE / "NetworkService.qml").read_bytes())
    clipboard = root / "wl-copy"
    clipboard.write_text("#!/usr/bin/env python3\nimport os,sys,time\nfrom pathlib import Path\nPath(os.environ['QS_TEST_NETWORK_CLIPBOARD']).write_text(sys.stdin.read())\nPath(os.environ['QS_TEST_NETWORK_CLOSED']).write_text(str(time.monotonic()))\n")
    clipboard.chmod(0o755)
    (root / "shell.qml").write_bytes((SOURCE / "tests/NetworkServiceLifecycleTest.qml").read_bytes())
    helper = root / "fake_helper.py"
    helper.write_text(FAKE_HELPER)
    log = root / "calls.log"
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_NO_XDG_DESKTOP_PORTAL="1",
               DBUS_SESSION_BUS_ADDRESS="",
               QS_TEST_NETWORK_HELPER=str(helper), QS_TEST_NETWORK_LOG=str(log),
               QS_TEST_NETWORK_CLIPBOARD=str(root / "clipboard"),
               QS_TEST_NETWORK_TIMES=str(root / "times.jsonl"),
               QS_TEST_NETWORK_CLOSED=str(root / "closed"),
               PATH=str(root) + os.pathsep + os.environ["PATH"])
    try:
        result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(root)],
                                env=env, capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired as exc:
        print((exc.stdout or b"").decode(errors="replace"), end="")
        print((exc.stderr or b"").decode(errors="replace"), end="")
        raise SystemExit("QML lifecycle fixture timed out")
    output = result.stdout + result.stderr
    if result.returncode or "network service lifecycle QML tests passed" not in output or "WARN scene:" in output:
        print(output, end="")
        raise SystemExit(1)
    calls = log.read_text().splitlines()
    assert "connect timeout-fixture" in calls, calls
    assert "state " in calls, calls
    assert "not-logged-secret" not in log.read_text()
    assert (root / "clipboard").read_text() == 'literal $(printf injected) `printf injected` $HOME'
    assert calls.count("scan ") >= 3, calls
    closed_at = float((root / "closed").read_text())
    times = [json.loads(line) for line in (root / "times.jsonl").read_text().splitlines()]
    assert not any(op == 'details' and timestamp > closed_at + .2 for timestamp, op in times), times
    print("network service lifecycle regression tests passed")
