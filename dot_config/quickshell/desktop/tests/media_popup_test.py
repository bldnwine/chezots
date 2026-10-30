"""Exercise the real MediaPopup geometry with fake players and card chrome."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="qs-media-popup-test-") as directory:
    root = Path(directory)
    popup = (source / "MediaPopup.qml").read_text()
    hooks = '''
    readonly property real testX: playerScroll.contentX
    readonly property real testWidth: playerScroll.width
    readonly property real testContentWidth: playerScroll.contentWidth
    readonly property real testMetadataX: metadata.mapToItem(col, 0, 0).x
    readonly property bool testClipped: playerScroll.clip
    readonly property bool testScrollbarVisible: playerBar.visible
    function testSetX(x) { playerScroll.contentX = x; }
    function testClick(i) { playerRepeater.itemAt(i).clicked(); }
    function testItem(i) { return playerRepeater.itemAt(i); }
    function testWheel(delta) { scrollPlayers(delta); }
'''
    popup = popup.replace('    id: mediaPopup', '    id: mediaPopup' + hooks, 1)
    popup = popup.replace('                ScrollBar.horizontal: ScrollBar {', '                ScrollBar.horizontal: ScrollBar {\n                    id: playerBar', 1)
    popup = popup.replace('        // Track metadata\n        Column {', '        // Track metadata\n        Column {\n            id: metadata', 1)
    (root / "MediaPopup.qml").write_text(popup)
    shutil.copy2(source / "QuickButton.qml", root / "QuickButton.qml")
    shutil.copy2(source / "tests/MediaPopupTest.qml", root / "shell.qml")
    shutil.copy2(source / "tests/NetworkPopupCardWindow.qml", root / "CardWindow.qml")
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_NO_XDG_DESKTOP_PORTAL="1")
    result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(root)], env=env,
                            capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    if result.returncode or "media popup regression tests passed" not in output or "WARN scene:" in output or "TypeError" in output or "ReferenceError" in output:
        print(output)
        raise SystemExit(1)
    print("media popup regression tests passed")
