"""Optional compositor-backed Locus resize-handle regression.

Requires a running Wayland compositor, QtTest and a private D-Bus session. All
settings and bookmarks are isolated in a temporary HOME. Only the isolated
fixture's global shortcuts and unrelated application probes are disabled.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
if not os.environ.get('WAYLAND_DISPLAY'):
    raise SystemExit('WAYLAND_DISPLAY is required for this optional test')
with tempfile.TemporaryDirectory(prefix='qs-locus-resize-wayland-') as directory:
    temp = Path(directory)
    config = temp / 'config'
    config.mkdir()
    for path in (*source.glob('*.qml'), *source.glob('*.js')):
        shutil.copy2(path, config / path.name)
    shutil.copytree(source / 'omni', config / 'omni')
    locus = (config / 'Locus.qml').read_text()
    start = locus.index('    // ---------- Global shortcuts ----------')
    end = locus.index('    // ---------- Panel ----------', start)
    locus = locus[:start] + locus[end:]
    locus = locus.replace('    id: root\n', '''    id: root
    readonly property real testCardWidth: card.width
    readonly property real testCardHeight: card.height
    readonly property real testCardY: card.y
    readonly property real testScreenWidth: panel.width
    readonly property real testScreenHeight: panel.height
    readonly property real testFillAlpha: locusEffects.fill.a
    readonly property bool testRequestingBlur: locusEffects.requestingBlur
    function testGrip(index) { return testGrips.itemAt(index); }
''', 1)
    locus = locus.replace('            Repeater {\n                model: [{h:-1,v:0}', '            Repeater {\n                id: testGrips\n                model: [{h:-1,v:0}', 1)
    # The fixture locates the same live MouseAreas; no rendering or handlers are changed.
    if 'locus-resize-grip-' not in locus:
        locus = locus.replace('                    id: grip\n', '''                    id: grip
                    objectName: "locus-resize-grip-" + modelData.h + "-" + modelData.v
''', 1)
    (config / 'Locus.qml').write_text(locus)
    (config / 'AppScan.qml').write_text('import QtQuick\nItem { property bool loaded: true; property var apps: []; signal scanned(); function refresh() {} function checkFreshness() {} }\n')
    (config / 'Tuis.qml').write_text('import QtQuick\nItem { property var items: [] }\n')
    (config / 'shell.qml').write_text('''import QtQuick
import QtTest
import Quickshell
ShellRoot {
    ShellSettings { id: settings }
    Theme { id: theme; settings: settings }
    Locus { id: locus; theme: theme; settings: settings }
    Window {
        id: testWindow; width: 50; height: 50; visible: true
        TestCase {
            name: "LocusWaylandResize"
            when: testWindow.visible && settings.ready
            function centered() {
                verify(Math.abs(locus.testCardY + locus.testCardHeight / 2 - locus.testScreenHeight / 2) < 1,
                       "card stays vertically centered");
            }
            function drag(grip, dx, dy) {
                const x = grip.width / 2, y = grip.height / 2;
                mousePress(grip, x, y, Qt.LeftButton);
                mouseMove(grip, x + dx, y + dy, 30); wait(50); centered();
                mouseRelease(grip, x + dx, y + dy, Qt.LeftButton); wait(150); centered();
            }
            function test_resize() {
                locus.visible_ = true; wait(400); centered();
                settings.setSetting("locusOpacity", 0.3);
                settings.setSetting("locusBlur", true); wait(150); centered();
                verify(Math.abs(locus.testFillAlpha - 0.3) < 0.01 && locus.testRequestingBlur,
                       "saved opacity and blur reach the real surface effect");
                const right = locus.testGrip(1);
                const top = locus.testGrip(2);
                const bottom = locus.testGrip(3);
                const corner = locus.testGrip(7);
                verify(right !== null && top !== null && bottom !== null && corner !== null, "resize grips found");
                settings.setSetting("locusHeight", 500); wait(150); centered();
                const initialWidth = locus.testCardWidth;
                const initialHeight = locus.testCardHeight;
                verify(initialWidth + 100 < locus.testScreenWidth, "screen has width for drag");
                verify(initialHeight + 50 < locus.testScreenHeight, "screen has height for drag");
                drag(right, 40, 0);
                verify(settings.normalWidth > initialWidth, "horizontal drag saved width");
                verify(locus.testCardWidth > initialWidth, "horizontal drag changed card width");
                drag(top, 0, -20);
                verify(settings.locusHeight > initialHeight && locus.testCardHeight > initialHeight, "top drag grows and saves height");
                const topHeight = locus.testCardHeight;
                drag(bottom, 0, 20);
                verify(settings.locusHeight > topHeight && locus.testCardHeight > topHeight, "bottom drag grows and saves height");
                const beforeCornerHeight = locus.testCardHeight;
                const beforeCornerWidth = locus.testCardWidth;
                drag(corner, 15, 15);
                verify(locus.testCardHeight > beforeCornerHeight && locus.testCardWidth > beforeCornerWidth, "corner drag grows both dimensions");
                compare(settings.locusHeight, locus.testCardHeight);
                compare(settings.normalWidth, locus.testCardWidth);
                verify(locus.testCardWidth <= locus.testScreenWidth && locus.testCardHeight <= locus.testScreenHeight,
                       "dragged card remains capped to screen");
                console.log("locus Wayland resize regression passed");
                Qt.quit();
            }
        }
    }
}''')
    isolated_home = temp / 'home'
    cache = isolated_home / '.cache/quickshell/omni-menu'
    cache.mkdir(parents=True)
    (cache / 'state.json').write_text('{"favourites":[],"history":[]}')
    env = dict(os.environ, HOME=str(isolated_home), XDG_CONFIG_HOME=str(isolated_home / '.config'),
               XDG_STATE_HOME=str(isolated_home / '.local/state'), QT_QPA_PLATFORM='wayland',
               QT_NO_XDG_DESKTOP_PORTAL='1')
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(config)], env=env,
                            capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    if result.returncode or 'locus Wayland resize regression passed' not in output or 'WARN scene:' in output or 'TypeError' in output or 'ReferenceError' in output or 'FAIL!' in output:
        print(output)
        print('exit code:', result.returncode)
        raise SystemExit(1)
    saved = json.loads((isolated_home / '.local/state/quickshell-desktop/settings.json').read_text())['settings']
    assert saved['normalWidth'] > 640 and saved['locusHeight'] > 0
    assert saved['locusOpacity'] == 0.3 and saved['locusBlur'] is True
    print('locus Wayland resize regression passed')
