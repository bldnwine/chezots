"""Run the real overlay in a private D-Bus session with temporary archives."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

desktop = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="quickshell-notification-test-") as directory:
    root = Path(directory)
    for filename in ("NotificationOverlay.qml", "NotificationModel.js"):
        shutil.copy2(desktop / filename, root / filename)
    harness = (desktop / "tests/NotificationRetentionTest.qml").read_text()
    (root / "shell.qml").write_text(harness.replace('import ".." as Desktop', 'import "." as Desktop'))
    # PanelWindow needs a real backend. The card stays hidden throughout;
    # the private bus isolates its NotificationServer from the desktop.
    env = dict(os.environ, QT_QPA_PLATFORM="wayland", QT_NO_XDG_DESKTOP_PORTAL="1",
               QS_TEST_ARCHIVE_DIR=str(root / "archive"))
    result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(root)], env=env,
                            capture_output=True, text=True, timeout=12)
    output = result.stdout + result.stderr
    if result.returncode or "notification lifecycle regression tests passed" not in output:
        print(output)
        raise SystemExit(1)
    print("notification lifecycle regression tests passed")
