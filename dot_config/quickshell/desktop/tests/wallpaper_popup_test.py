"""Exercise wallpaper panel geometry with an isolated offscreen window."""
import os
from pathlib import Path
import subprocess
import tempfile
import shutil

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="qs-wallpaper-layout-") as directory:
    root = Path(directory)
    shutil.copy2(source / "SurfaceEffects.qml", root / "SurfaceEffects.qml")
    popup = (source / "WallpaperPopup.qml").read_text().replace("PanelWindow {", "Item {", 1)
    popup = popup.replace('    color: "transparent"\n', '', 1)
    popup = popup.replace('    anchors { top: true; bottom: true; left: true; right: true }', '    anchors.fill: parent', 1)
    popup = popup.replace('    PopupFocusGrab { window: wallpaperWindow }\n', '', 1)
    popup = "\n".join(line for line in popup.splitlines() if not line.strip().startswith(("exclusionMode:", "WlrLayershell.", "BackgroundEffect.")))
    popup = popup.replace('        refresh();\n        Qt.callLater(() => surface.forceActiveFocus());', '        Qt.callLater(() => surface.forceActiveFocus());', 1)
    popup = popup.replace('Quickshell.env("HOME") + "/.local/state/quickshell-desktop/wallpaper-favorites.json"', '"/tmp/qs-test-missing-wallpaper-favorites.json"')
    popup = popup.replace('    id: wallpaperWindow', '''    id: wallpaperWindow
    readonly property real testShelfWidth: surface.width
    readonly property real testShelfHeight: surface.height
    readonly property real testShelfY: surface.y
    readonly property real testShelfContentHeight: shelfColumn.implicitHeight
    readonly property var testEditor: wallpaperEditor
    readonly property var testEffects: wallpaperEffects''', 1)
    (root / 'WallpaperPopup.qml').write_text(popup)
    editor = (source / 'WallpaperEditor.qml').read_text().replace('    id: editor', '''    id: editor
    readonly property real testWidth: editorCard.width
    readonly property real testHeight: editorCard.height
    readonly property real testSidebarWidth: sidebar.width
    readonly property real testSidebarContentHeight: sidebarColumn.implicitHeight
    readonly property real testSidebarViewportHeight: sidebarViewport.height
    readonly property real testFooterWidth: footerContent.width''', 1)
    (root / 'WallpaperEditor.qml').write_text(editor)
    (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
  Window {
    width: 900; height: 700; visible: true
    Item {
      id: area; width: 900; height: 700
      QtObject {
        id: state
        property real panelScale: 1
        property real panelTextScale: 1
        property var panelOpacity: null
        property bool panelBlur: false
        property var wallpaperService: index
        property bool wallpapersVisible: false
        property string pendingWallpaperSort: ""
        property string barEdge: ""
        property real barOffset: 0
        property real cornerRadius: 4
        property string mono: "monospace"
        property color bg: "black"
        property color ink: "white"
        property color inkDeep: "gray"
        property color paper: "black"
        property color seal: "blue"
        property color sep: "gray"
      }
      QtObject {
        id: index
        property var wallpapers: [
          {name: "alpha", path: "/a", mtime: 1, btime: 1, size: 1},
          {name: "beta", path: "/b", mtime: 2, btime: 2, size: 2},
          {name: "alpine", path: "/c", mtime: 3, btime: 3, size: 3},
          {name: "amber", path: "/d", mtime: 4, btime: 4, size: 4}
        ]
        property bool hasIndex: true
        property string error: ""
        function enter() {}
        function requestRefresh(force) {}
      }
      WallpaperPopup { id: panel; root: state }
      Timer {
        interval: 200; repeat: true; running: true
        property int phase: 0
        function check(value, message) { if (!value) { console.error(message); Qt.exit(1); throw new Error(message); } }
        onTriggered: {
          if (phase++ === 0) {
            check(panel.testShelfHeight === 260, "default shelf height changed");
            panel.setSort("r");
            const original = panel.filteredWallpapers.map(x => x.path);
            panel.query = "a"; panel.rebuildList();
            check(panel.filteredWallpapers.map(x => x.path).join(",") === original.join(","), "search reshuffled random order");
            panel.query = "al"; panel.rebuildList();
            check(panel.filteredWallpapers.map(x => x.path).join(",") === original.filter(x => x === "/a" || x === "/c").join(","), "filtered random order changed");
            panel.query = ""; panel.rebuildList();
            check(panel.filteredWallpapers.map(x => x.path).join(",") === original.join(","), "clearing search reshuffled random order");
            state.panelScale = 1.5; state.panelTextScale = 2;
            state.panelOpacity = .3; state.panelBlur = true;
            area.width = 400; area.height = 360; panel.searchActive = true;
            panel.testEditor.active = true;
          } else {
            const e = panel.testEditor;
            check(Math.abs(panel.panelBackground.a - .3) < .001, "wallpaper panel opacity");
            check(panel.testEffects.targetSurface === e.effectSurface, "editor receives active blur region");
            check(panel.testShelfY >= 0 && panel.testShelfHeight <= area.height, "shelf is off-screen");
            check(panel.testShelfContentHeight > panel.testShelfHeight, "short shelf should scroll");
            check(e.testWidth <= area.width && e.testHeight <= area.height, "editor is off-screen");
            check(e.testSidebarWidth > 0 && e.testSidebarWidth < e.testWidth, "editor sidebar leaves no canvas");
            check(e.testSidebarContentHeight > e.testSidebarViewportHeight, "short sidebar should scroll");
            check(e.testFooterWidth > e.testWidth, "narrow editor actions should scroll");
            console.log("wallpaper popup geometry tests passed"); Qt.quit();
          }
        }
      }
    }
  }
}''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_NO_XDG_DESKTOP_PORTAL='1')
    result = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(root)], env=env, capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    if result.returncode or 'wallpaper popup geometry tests passed' not in output or 'WARN scene:' in output or 'TypeError' in output or 'ReferenceError' in output:
        print(output)
        raise SystemExit(1)
    print('wallpaper popup geometry tests passed')
