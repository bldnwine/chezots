"""Isolated real NetworkPopup QML regression tests with fake UI and root APIs."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from popup_test_support import write_card

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="qs-network-popup-test-") as directory:
    root = Path(directory)
    popup = (source / "NetworkPopup.qml").read_text()
    hooks = """
    readonly property real testScrollY: bodyScroll.contentY
    readonly property real testScrollHeight: bodyScroll.height
    readonly property bool testInputFocused: passInput.activeFocus
    readonly property string testInputText: passInput.text
    readonly property string testStatusText: statusLine.text
    readonly property real testStatsTop: statsScroll.y
    readonly property real testStatsBottom: statsScroll.y + statsScroll.height
    readonly property real testStatsHeight: statsScroll.height
    readonly property real testStatsContentHeight: statsScroll.contentHeight
    readonly property bool testStatsVisible: statsScroll.visible
    function testSetInput(value) { passInput.text = value; }
    function testSelectionVisible() {
        const row = networkList.itemAtIndex(kbdIndex - headerCount);
        if (!row) return false;
        const top = row.mapToItem(bodyScroll, 0, 0).y;
        return top >= -1 && top + row.height <= bodyScroll.height + 1;
    }
"""
    (root / "NetworkPopup.qml").write_text(popup.replace("    id: netpopup", "    id: netpopup" + hooks, 1))
    shutil.copy2(source / "QuickButton.qml", root / "QuickButton.qml")
    shutil.copy2(source / "tests/NetworkPopupTest.qml", root / "shell.qml")
    write_card(root)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               QT_NO_XDG_DESKTOP_PORTAL="1")
    try:
        result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(root)],
                                env=env, capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired as error:
        print((error.stdout or b"").decode(errors="replace"))
        print((error.stderr or b"").decode(errors="replace"))
        raise SystemExit("QML test timed out")
    output = result.stdout + result.stderr
    if result.returncode or "network popup regression tests passed" not in output or "WARN scene:" in output or "TypeError" in output or "ReferenceError" in output:
        print(output)
        raise SystemExit(1)
    print("network popup regression tests passed")
