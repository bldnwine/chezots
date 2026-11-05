"""Load bundled SVGs, check theme tinting, and suspend badges when hidden."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from PIL import Image

source = Path(__file__).resolve().parents[1]
names = sorted(path.stem for path in (source / 'icons/bar').glob('*.svg'))
with tempfile.TemporaryDirectory(prefix='qs-bar-icons-') as directory:
    root = Path(directory)
    for name in ('BarIcon.qml', 'BarIconMetrics.js', 'BarStatusIcon.qml', 'Module.qml', 'Bloom.qml'):
        shutil.copy2(source / name, root / name)
    (root / 'icons').symlink_to(source / 'icons', target_is_directory=True)
    preview = root / 'preview.png'
    harness = '''import QtQuick
import QtQuick.Window
import QtQuick.VectorImage
import QtQuick.Layouts
import Quickshell
ShellRoot {
    QtObject {
        id: horizontalRoot
        property bool isHorizontal: true
        property int barHeight: 22
        property int cornerRadius: 4
        property color ink: "#d8dee9"
        property color accent: "#a3be8c"
        property string mono: "sans-serif"
    }
    QtObject {
        id: verticalRoot
        property bool isHorizontal: false
        property int barHeight: 22
        property int cornerRadius: 4
        property color ink: "#d8dee9"
        property color accent: "#a3be8c"
        property string mono: "sans-serif"
    }
    Window {
        id: window
        visible: true
        width: 640; height: 240
        color: "#1c2028"
        flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
        Grid {
            x: 12; y: 12; columns: 16; spacing: 20
            Repeater {
                id: icons
                model: NAMES
                BarIcon {
                    required property string modelData
                    source: Qt.resolvedUrl("icons/bar/" + modelData + ".svg")
                    color: "#d8dee9"
                }
            }
        }
        Row {
            x: 12; y: 180; spacing: 24
            BarStatusIcon { id: working; source: Qt.resolvedUrl("icons/bar/smart_toy.svg"); badge: "working" }
            BarStatusIcon { source: Qt.resolvedUrl("icons/bar/smart_toy.svg"); badge: "finished" }
            BarStatusIcon { source: Qt.resolvedUrl("icons/bar/cloud_off.svg"); badge: "warning" }
            BarIcon { source: Qt.resolvedUrl("icons/bar/notifications.svg"); size: 28; color: "#88c0d0" }
        }
        RowLayout {
            x: 300; y: 180
            Module { id: horizontal; root: horizontalRoot; iconSource: Qt.resolvedUrl("icons/bar/network-wireless-signal-good-symbolic.svg") }
        }
        ColumnLayout {
            x: 350; y: 180
            Module { id: vertical; root: verticalRoot; iconSource: Qt.resolvedUrl("icons/bar/network-wireless-signal-good-symbolic.svg") }
        }
        Timer {
            interval: 700; running: true
            onTriggered: {
                if (horizontal.width !== 24 || horizontal.height !== 22 || vertical.width !== 22 || vertical.height !== 24) {
                    console.error("Icon module orientation geometry changed");
                    Qt.exit(1); return;
                }
                for (let i = 0; i < icons.count; ++i) {
                    const icon = icons.itemAt(i);
                    if (icon.status !== VectorImage.Ready || icon.width !== 14 || icon.height !== 14) {
                        console.error("Icon failed to load: " + icon.modelData);
                        Qt.exit(1); return;
                    }
                    const vector = icon.children[0];
                    if (!(vector instanceof VectorImage) || vector.preferredRendererType !== VectorImage.CurveRenderer) {
                        console.error("Icon regressed to bitmap or aliased geometry rendering");
                        Qt.exit(1); return;
                    }
                    const bounds = icon.inkBounds;
                    const centerX = icon.artworkX + (bounds[0] + bounds[2] / 2) * icon.renderSize;
                    const centerY = icon.artworkY + (bounds[1] + bounds[3] / 2) * icon.renderSize;
                    if (Math.abs(Math.max(icon.paintedWidth, icon.paintedHeight) - 14) > 0.001
                            || Math.abs(centerX - 7) > 0.001 || Math.abs(centerY - 7) > 0.001) {
                        console.error("Icon artwork size or centering changed: " + icon.modelData);
                        Qt.exit(1); return;
                    }
                }
                window.contentItem.grabToImage(function(result) {
                    if (!result.saveToFile(PREVIEW)) { Qt.exit(1); return; }
                    window.visible = false;
                    Qt.callLater(function() {
                        if (working.hostVisible) { Qt.exit(1); return; }
                        console.log("bar icon rendering passed"); Qt.quit();
                    });
                });
            }
        }
    }
    Timer { interval: 6000; running: true; onTriggered: Qt.exit(1) }
}
'''.replace('NAMES', json.dumps(names)).replace('PREVIEW', json.dumps(str(preview)))
    (root / 'shell.qml').write_text(harness)
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl',
               QT_NO_XDG_DESKTOP_PORTAL='1')
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(root)],
                            env=env, capture_output=True, text=True, timeout=12)
    output = result.stdout + result.stderr
    if result.returncode or 'bar icon rendering passed' not in output or 'WARN scene:' in output:
        print(output)
        raise SystemExit(1)
    pixels = Image.open(preview).convert('RGB')
    # The disconnected Bluetooth rune is intentionally dim; its X stays opaque.
    # Sample inside the upper vertical stem, away from the X and antialiased edge.
    metrics_text = (source / 'BarIconMetrics.js').read_text()
    metrics = json.loads(metrics_text.split('var inkBounds = ', 1)[1].split(';', 1)[0])
    name = 'bluetooth-disconnected-symbolic'
    bounds = metrics[name]
    render_size = 14 / max(bounds[2:])
    index = names.index(name)
    sample_x = 12 + (index % 16) * 34 + 7 + (0.5 - bounds[0] - bounds[2] / 2) * render_size
    sample_y = 12 + (index // 16) * 34 + 7 + (0.25 - bounds[1] - bounds[3] / 2) * render_size
    rgba = Image.open(preview).convert('RGBA')
    ratio = rgba.width / 640
    x, y = round(sample_x * ratio), round(sample_y * ratio)
    alpha = max(rgba.getpixel((x + dx, y + dy))[3] for dx in (-1, 0, 1) for dy in (-1, 0, 1))
    assert 40 < alpha < 120, f'Disconnected Bluetooth lost its original opacity: {alpha}'
    tinted = sum(all(abs(a - b) <= 2 for a, b in zip(pixel, (216, 222, 233)))
                 for pixel in pixels.get_flattened_data())
    if os.environ.get('QS_ICON_PREVIEW_PATH'):
        shutil.copy2(preview, os.environ['QS_ICON_PREVIEW_PATH'])
    assert tinted > 100, 'SVG masks did not render in the requested theme color'
    print(f'Bar icon rendering, tint, orientation, and hidden-window checks passed ({len(names)} assets)')
