"""Exercise the real QML selection service with isolated player objects."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

desktop = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="quickshell-music-test-") as directory:
    root = Path(directory)
    shutil.copy2(desktop / "MusicService.qml", root / "MusicService.qml")
    harness = (desktop / "tests/MusicServiceTest.qml").read_text()
    (root / "shell.qml").write_text(harness.replace('import ".." as Desktop', 'import "." as Desktop'))
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_NO_XDG_DESKTOP_PORTAL="1")
    result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(root)], env=env,
                            capture_output=True, text=True, timeout=10)
    output = result.stdout + result.stderr
    if result.returncode or "music service regression tests passed" not in output or "WARN scene:" in output:
        print(output)
        raise SystemExit(1)
    print("music service regression tests passed")
