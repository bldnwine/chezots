"""Optional isolated compositor-backed SurfaceEffects protocol regression."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
if not os.environ.get('WAYLAND_DISPLAY'):
    raise SystemExit('WAYLAND_DISPLAY is required')
with tempfile.TemporaryDirectory(prefix='qs-effects-wayland-') as directory:
    root = Path(directory)
    shutil.copy2(source / 'SurfaceEffects.qml', root)
    (root / 'shell.qml').write_text('''import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
ShellRoot {
    PanelWindow {
        id: panel
        anchors { top: true; left: true; right: true; bottom: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        BackgroundEffect.blurRegion: fx.blurRegion
        Rectangle {
            id: card; x: 50; y: 80; width: 300; height: 180
            property real testScale: 1
            property real testOffset: 0
            transform: [Scale { xScale: card.testScale; yScale: card.testScale }, Translate { y: card.testOffset }]
            color: fx.fill; radius: 20
            Text { id: label; text: "Readable"; opacity: 0.7 }
        }
        SurfaceEffects { id: fx; targetSurface: card; background: "#80ffffff"; cornerRadius: card.radius
            scaleFactor: card.testScale; scaleOrigin: Qt.point(0, 0); translation: Qt.point(0, card.testOffset)
        }
        TestCase {
            name: "SurfaceEffects"
            when: panel.visible
            function test_effects() {
                verify(Math.abs(fx.fill.a - 0.502) < 0.01); compare(fx.blurRegion, null);
                for (let alpha of [0, 0.3, 1]) {
                    fx.opacityOverride = alpha; verify(Math.abs(fx.fill.a - alpha) < 0.01);
                    verify(Math.abs(label.opacity - 0.7) < 0.01);
                }
                fx.opacityOverride = 0.3; fx.blurEnabled = true; wait(300);
                verify(fx.blurRegion !== null);
                compare(fx.blurRegion.radius, 20);
                card.x = 75; card.y = 100; card.width = 320; card.height = 200; card.radius = 12; wait(300);
                compare(fx.blurRegion.width, 320); compare(fx.blurRegion.radius, 12);
                card.testScale = 0.94; card.testOffset = 12; wait(300);
                fx.shown = false; wait(100); compare(fx.blurRegion, null);
                fx.shown = true; fx.opacityOverride = 1; wait(100); compare(fx.blurRegion, null);
                fx.opacityOverride = null; verify(Math.abs(fx.fill.a - 0.502) < 0.01);
                fx.blurEnabled = false; compare(fx.blurRegion, null);
                console.log("SURFACE_EFFECTS_PASS"); Qt.quit();
            }
        }
    }
}''')
    home = root / 'home'
    home.mkdir()
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
               XDG_STATE_HOME=str(home / '.local/state'), QT_QPA_PLATFORM='wayland',
               QT_NO_XDG_DESKTOP_PORTAL='1', WAYLAND_DEBUG='client')
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(root)],
                            env=env, capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    if result.returncode or 'SURFACE_EFFECTS_PASS' not in output or re.search(r'FAIL!|TypeError|ReferenceError|WARN scene:', output):
        print(output)
        raise SystemExit(f'fixture failed: {result.returncode}')
    if 'ext_background_effect_manager_v1' not in output:
        print('SurfaceEffects API passed; compositor did not advertise native background effect protocol')
    else:
        # Wayland object IDs can be reused after destroy. Associate rectangles
        # with each request in order, rather than collecting by ID across time.
        regions = {}
        requests = []
        for line in output.splitlines():
            created = re.search(r'create_region\(new id wl_region#(\d+)\)', line)
            if created:
                regions[created[1]] = []
            added = re.search(r'wl_region#(\d+)\.add\((-?\d+), (-?\d+), (\d+), (\d+)\)', line)
            if added:
                regions.setdefault(added[1], []).append(tuple(map(int, added.groups()[1:])))
            requested = re.search(r'ext_background_effect_surface_v1#\d+\.set_blur_region\(wl_region#(\d+)\)', line)
            if requested:
                requests.append(list(regions.get(requested[1], [])))
        assert len(requests) >= 3, "native region requests missing"
        for rows, bounds in zip(requests[:2], [(50, 80, 300, 180), (75, 100, 320, 200)]):
            x, y, w, h = bounds
            assert rows and all(x <= a and y <= b and a + c <= x + w and b + d <= y + h
                                for a, b, c, d in rows), (bounds, rows)
            assert min(a for a, b, c, d in rows) == x and max(a + c for a, b, c, d in rows) == x + w
            assert min(b for a, b, c, d in rows) == y and max(b + d for a, b, c, d in rows) == y + h
            assert rows[0][2] < w, "top edge should have rounded corners"
        rows = requests[2]
        actual = (min(a for a, b, c, d in rows), min(b for a, b, c, d in rows),
                  max(a + c for a, b, c, d in rows), max(b + d for a, b, c, d in rows))
        assert all(abs(a - b) <= 1 for a, b in zip(actual, (75, 112, 376, 300))), f'transformed bounds: {actual}'
        assert re.search(r'ext_background_effect_surface_v1#\d+\.set_blur_region\(nil\)', output)
        print('SurfaceEffects API and native blur-region protocol passed')
