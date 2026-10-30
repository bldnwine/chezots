"""Check AudioPopup fixed card geometry with isolated fake device and stream data."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from popup_test_support import write_card

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="qs-audio-popup-test-") as directory:
    root = Path(directory)
    qml = (source / "AudioPopup.qml").read_text()
    qml = qml.replace('import Quickshell.Services.Pipewire\n', '')
    start = qml.index('    readonly property var playbackCandidates:')
    end = qml.index('    readonly property var playbackNodes:', start)
    qml = qml[:start] + '    readonly property var playbackCandidates: root.testStreams\n' + qml[end:]
    start = qml.index('    PwNodePeakMonitor {')
    end = qml.index('\n    // Component for the standard Audio Control Pane', start)
    qml = qml[:start] + '    Item { id: inputPeak; property real peak: 0 }\n' + qml[end:]
    qml = qml.replace('Pipewire.ready ? "No application playback" : "Playback unavailable"', '"No application playback"')
    hooks = '''
    readonly property real testDeckBottom: contentDeck.mapToItem(audioPopup, 0, contentDeck.height).y
    readonly property real testScrollY: (eqExpanded ? rightDeck.item : normalDeck.item) ? (eqExpanded ? rightDeck.item : normalDeck.item).contentY : 0
    readonly property real testScrollHeight: (eqExpanded ? rightDeck.item : normalDeck.item) ? (eqExpanded ? rightDeck.item : normalDeck.item).height : 0
    function testSelectionVisible() { return (eqExpanded ? rightDeck.item : normalDeck.item).testSelectionVisible(); }
'''
    qml = qml.replace('    id: audioPopup', '    id: audioPopup' + hooks, 1)
    qml = qml.replace('            function ensureFocusVisible() {', '''            function testSelectionVisible() {
                const row = audioPopup.focusedRow();
                let item = null;
                if (row.type === "source") item = sourceRows.itemAt(audioPopup.kbdIndex - audioPopup._sourceKbdBase);
                else if (row.type === "sink") item = sinkRows.itemAt(audioPopup.kbdIndex - 2);
                if (!item) return false;
                const top = item.mapToItem(controlsScroll, 0, 0).y;
                return top >= -1 && top + item.height <= controlsScroll.height + 1;
            }
            function ensureFocusVisible() {''', 1)
    qml = qml.replace('        // ---------- Content Deck (Single Column vs 2-Column Split when EQ Expanded) ----------\n        Item {', '        // ---------- Content Deck (Single Column vs 2-Column Split when EQ Expanded) ----------\n        Item {\n            id: contentDeck', 1)
    (root / 'AudioPopup.qml').write_text(qml)
    (root / 'EqPanel.qml').write_text('import QtQuick\nItem { required property var root; implicitHeight: 900 }\n')
    for name in ('QuickButton.qml', 'DisplaySlider.qml'):
        shutil.copy2(source / name, root / name)
    shutil.copy2(source / 'tests/AudioPopupTest.qml', root / 'shell.qml')
    write_card(root)
    card = (root / "CardWindow.qml").read_text()
    card = card.replace("    id: card", "    id: card\n    readonly property real testActualBodyBottom: bodyContainer.mapToItem(card, 0, bodyContainer.height).y\n    readonly property real testFooterBottomInSurface: footerLabel.mapToItem(surface, 0, footerLabel.height).y", 1)
    (root / "CardWindow.qml").write_text(card)
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_NO_XDG_DESKTOP_PORTAL='1')
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(root)], env=env,
                            capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    if result.returncode or 'audio popup regression tests passed' not in output or 'WARN scene:' in output or 'TypeError' in output or 'ReferenceError' in output:
        print(output)
        raise SystemExit(1)
    print('audio popup regression tests passed')
