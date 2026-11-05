"""Real Locus geometry and settings regression, using an offscreen layer shim."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="qs-locus-geometry-") as directory:
    temp = Path(directory)
    config = temp / 'config'
    config.mkdir()
    for path in source.glob('*.qml'):
        shutil.copy2(path, config / path.name)
    for path in source.glob('*.js'):
        shutil.copy2(path, config / path.name)
    shutil.copytree(source / 'omni', config / 'omni')
    # Offscreen Qt has no layer-shell surface. Keep production geometry, replace
    # only the window and its Wayland-specific bindings with a resizable Item.
    locus = (config / 'Locus.qml').read_text()
    locus = locus.replace('    id: root\n', '''    id: root
    property real testScreenWidth: 1440
    property real testScreenHeight: 900
    readonly property real testCardWidth: card.width
    readonly property real testCardHeight: card.height
    readonly property real testCardX: card.x
    readonly property real testCardY: card.y
    readonly property real testListHeight: listArea.height
    readonly property real testQuickHeight: quickContainer.height
    readonly property real testSearchFont: searchInput.testFontPixelSize
    readonly property real testQuickContentHeight: quickContainer.testContentHeight
    readonly property real testQuickContentY: quickContainer.testContentY
    readonly property var testList: resultListInstance.list
    readonly property var testCard: card
''', 1)
    locus = locus.replace('    PanelWindow {\n        id: panel', '    Item {\n        id: panel', 1)
    locus = locus.replace('        color: "transparent"\n', '', 1)
    locus = locus.replace('        anchors { top: true; bottom: true; left: true; right: true }',
                          '        width: root.testScreenWidth\n        height: root.testScreenHeight', 1)
    locus = locus.replace('        PopupFocusGrab { window: panel }\n', '', 1)
    locus = '\n'.join(line for line in locus.splitlines() if not line.strip().startswith(('exclusionMode:', 'WlrLayershell.', 'BackgroundEffect.')))
    (config / 'Locus.qml').write_text(locus)
    search = config / 'omni' / 'SearchInput.qml'
    search.write_text(search.read_text().replace('    id: input', '    id: input\n    readonly property real testFontPixelSize: queryText.font.pixelSize', 1))
    quick = config / 'omni' / 'QuickContainer.qml'
    quick.write_text(quick.read_text().replace('    id: qc', '    id: qc\n    readonly property real testContentHeight: quickGrid.contentHeight\n    readonly property real testContentY: quickGrid.contentY', 1))
    # Avoid scanning host applications and invoking shell probes in this test.
    (config / 'AppScan.qml').write_text('import QtQuick\nItem { property bool loaded: true; property var apps: []; signal scanned(); function refresh() {} function checkFreshness() {} }\n')
    (config / 'Tuis.qml').write_text('import QtQuick\nItem { property var items: [] }\n')
    (config / 'shell.qml').write_text('''import QtQuick
import QtTest
import Quickshell
ShellRoot {
    Window {
        id: win; width: 1440; height: 900; visible: true
        ShellSettings { id: settings }
        Theme { id: theme; settings: settings }
        Locus { id: locus; theme: theme; settings: settings }
        TestCase {
            id: test
            name: "LocusGeometry"
            when: win.visible && settings.ready
            function near(a, b) { return Math.abs(a - b) < 1; }
            function bounds() {
                verify(locus.testCardWidth > 0 && locus.testCardHeight > 0, "positive card dimensions");
                verify(locus.testCardX >= 0 && locus.testCardY >= 0, "card origin on screen");
                verify(locus.testCardX + locus.testCardWidth <= locus.testScreenWidth + 1, "card width capped");
                verify(locus.testCardY + locus.testCardHeight <= locus.testScreenHeight + 1, "card height capped");
                verify(near(locus.testCardY + locus.testCardHeight / 2, locus.testScreenHeight / 2), "card vertically centered");
            }
            function test_geometry() {
                locus.visible_ = true; wait(150);
                compare(locus.testCardWidth, 640); bounds();
                settings.setSetting("locusHeight", 360); wait(150);
                compare(locus.testCardHeight, 360); bounds();
                settings.setSetting("locusHeight", 800); wait(20); bounds();
                wait(150); compare(locus.testCardHeight, 800); bounds();
                settings.setSetting("locusHeight", 2000); wait(150);
                compare(locus.testCardHeight, 868); bounds();
                settings.setSetting("locusHeight", 0); locus.categoryFilter = "Quick"; wait(150);
                bounds(); verify(locus.testCardHeight > 0, "Quick auto height");
                locus.categoryFilter = ""; wait(150); bounds();
                locus.categoryFilter = "Files"; wait(150);
                compare(locus.testCardWidth, 1000); bounds();
                settings.setSetting("normalWidth", 720);
                settings.setSetting("previewWidth", 1160);
                settings.setSetting("locusHeight", 580); wait(150);
                compare(locus.testCardWidth, 1160); compare(locus.testCardHeight, 580);
                bounds();
                locus.categoryFilter = ""; wait(150);
                compare(locus.testCardWidth, 720); compare(locus.testCardHeight, 580);
                bounds();
                locus.categoryFilter = "Files"; locus.testScreenWidth = 820; wait(150);
                verify(locus.testCardWidth <= 820); bounds();
                locus.testScreenWidth = 1440; locus.testScreenHeight = 900;
                locus.categoryFilter = ""; wait(150);
                compare(locus.testCardWidth, 720); compare(locus.testCardHeight, 580);
                settings.setSetting("locusScale", 0.75);
                settings.setSetting("locusTextScale", 0.7); wait(100);
                verify(locus.testSearchFont >= 7 && locus.testSearchFont <= 8, "minimum font scale");
                bounds();
                settings.setSetting("locusScale", 1.5);
                settings.setSetting("locusTextScale", 2);
                locus.testScreenWidth = 400; locus.testScreenHeight = 300; wait(200);
                compare(locus.testSearchFont, 42); bounds();
                verify(locus.testListHeight > 0, "scaled result list remains usable");
                verify(locus.testList.contentHeight > locus.testList.height, "result list can scroll");
                locus.categoryFilter = "Quick"; wait(200);
                bounds(); verify(locus.testQuickHeight > 0, "scaled Quick remains usable");
                verify(locus.testQuickContentHeight > locus.testQuickHeight, "Quick grid can scroll");
                locus.selectedIndex = locus.filteredQuickTiles.length - 1; wait(100);
                verify(locus.testQuickContentY > 0, "Quick selection scrolls into view");
                locus.categoryFilter = ""; wait(150);
                locus.testCard.forceActiveFocus(); wait(50);
                keyClick(Qt.Key_Minus, Qt.ControlModifier); wait(50);
                verify(near(settings.locusTextScale, 1.9), "Ctrl+- changes persisted text setting");
                keyClick(Qt.Key_Equal, Qt.ControlModifier); wait(50);
                compare(settings.locusTextScale, 1);
                console.log("locus geometry regression tests passed");
                Qt.quit();
            }
        }
    }
}''')
    isolated_home = temp / 'home'
    isolated_home.mkdir()
    cache = isolated_home / '.cache/quickshell/omni-menu'
    cache.mkdir(parents=True)
    (cache / 'state.json').write_text('{"favourites":[], "history":[]}')
    env = dict(os.environ, HOME=str(isolated_home), XDG_CONFIG_HOME=str(isolated_home / '.config'),
               XDG_STATE_HOME=str(isolated_home / '.local/state'), QT_QPA_PLATFORM='offscreen',
               QT_QUICK_BACKEND='software', QT_NO_XDG_DESKTOP_PORTAL='1')
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(config)], env=env,
                            capture_output=True, text=True, timeout=25)
    output = result.stdout + result.stderr
    if result.returncode or 'locus geometry regression tests passed' not in output or 'WARN scene:' in output or 'TypeError' in output or 'ReferenceError' in output or 'FAIL!' in output:
        print(output)
        print("exit code:", result.returncode)
        raise SystemExit(1)
    saved = json.loads((isolated_home / '.local/state/quickshell-desktop/settings.json').read_text())['settings']
    assert saved['normalWidth'] == 720 and saved['previewWidth'] == 1160 and saved['locusHeight'] == 580
    assert saved['locusTextScale'] == 1
    print('locus geometry regression tests passed')
