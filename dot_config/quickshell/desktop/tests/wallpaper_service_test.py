"""Exercise index reuse, refresh and failure retention with an isolated helper."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="qs-wallpaper-service-") as directory:
    root = Path(directory)
    shutil.copy2(source / "WallpaperService.qml", root / "WallpaperService.qml")
    helper = root / "scan.py"
    helper.write_text('''import json, pathlib, sys
count = pathlib.Path(sys.argv[1])
count.write_text(count.read_text() + "x" if count.exists() else "x")
if sys.argv[2] == "fail":
    print("[]")
    sys.exit(1)
print(json.dumps([{"name": sys.argv[2], "path": "/tmp/" + sys.argv[2], "mtime": 1, "btime": 1, "size": 1}]))
''')
    (root / "shell.qml").write_text('''import QtQuick
import Quickshell
ShellRoot {
    WallpaperService { id: index; staleAfterMs: 60000 }
    Timer {
        interval: 100; repeat: true; running: true
        property int phase: 0
        property int ticks: 0
        function check(ok, msg) { if (!ok) { console.error(msg); Qt.exit(1); throw new Error(msg); } }
        onTriggered: {
            if (++ticks > 100) { check(false, "timed out in phase " + phase); return; }
            if (phase === 0) {
                check(!index.scanning && !index.hasIndex, "scanned while hidden");
                index.scanCommand = ["python3", "%s", "%s", "first"];
                index.enter(); phase++;
            } else if (phase === 1 && !index.scanning) {
                check(index.hasIndex && index.wallpapers[0].name === "first", "initial index");
                index.enter(); check(!index.scanning, "warm reopen scanned");
                index.scanCommand = ["python3", "%s", "%s", "fail"];
                index.requestRefresh(true); phase++;
            } else if (phase === 2 && !index.scanning) {
                check(index.wallpapers[0].name === "first" && index.error.length > 0, "failed scan replaced cache");
                index.lastSuccess = 0;
                index.scanCommand = ["python3", "%s", "%s", "second"];
                index.enter(); phase++;
            } else if (phase === 3 && !index.scanning) {
                check(index.wallpapers[0].name === "second" && index.error === "", "stale refresh failed");
                console.log("wallpaper service tests passed"); Qt.quit();
            }
        }
    }
}
''' % ((str(helper), str(root / 'count')) * 3))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_NO_XDG_DESKTOP_PORTAL="1")
    result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(root)], env=env, capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    if result.returncode or "wallpaper service tests passed" not in output or "TypeError" in output or "ReferenceError" in output:
        print(output)
        raise SystemExit(1)
    assert (root / 'count').read_text() == 'xxx'
    print("wallpaper service tests passed")
