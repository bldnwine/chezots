"""Exercise the actual Theme and FileView using private palette files."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

DESKTOP = Path(__file__).resolve().parents[1]
COLORS = dict(paper='#123456', ink='#aabbcc', inkDeep='#112233', sumi='#223344',
              indigo='#334455', green='#445566', sealRaw='#556677', bg='#12345680',
              warn='#556677', sep='#aabbcc2e', rowHi='#aabbcc0f', rowSel='#5566772e')
LEGACY = '''background = "#101010"\nforeground = "#eeeeee"\ncolor7 = "#bbbbbb"\ncolor8 = "#777777"\naccent = "#225588"\ncolor2 = "#00aa00"\ncolor1 = "#aa0000"\n'''
QML = r'''import QtQuick
import Quickshell
import Quickshell.Io
import "@DESKTOP@" as Desktop
ShellRoot {
    Desktop.Theme { id: theme }
    FileView { id: dedicated; path: theme.colorsPath; atomicWrites: true; blockWrites: true; printErrors: false }
    FileView { id: generic; path: theme.legacyColorsPath; atomicWrites: true; blockWrites: true; printErrors: false }
    Timer {
        property int stage: 0
        property var original: @COLORS@
        property var draft: Object.assign({}, original, {paper:"#abcdef", bg:"#abcdef40"})
        property string mode: Quickshell.env("TEST_MODE")
        function check(ok, message) { if (!ok) { console.error("ASSERT: " + message); Qt.exit(1); } return ok; }
        function doc(revision, colors) { return JSON.stringify({version:1, revision:revision, colors:colors}); }
        interval: 400; running: true; repeat: true
        onTriggered: {
            stage++;
            if (mode === "fallback") {
                if (stage === 2) {
                    if (!check(String(theme.paper) === "#101010", "legacy fallback " + theme.paper)) return;
                    if (!check(!theme.dedicatedPresent && theme.paletteRevision === "legacy", "fallback source")) return;
                    console.log("theme fallback passed"); Qt.quit();
                }
                return;
            }
            if (stage === 2) {
                if (!check(String(theme.paper) === "#123456", "dedicated startup " + theme.paper)) return;
                if (!check(String(theme.bg) === "#80123456", "alpha-last conversion " + theme.bg)) return;
                if (!check(theme.paletteRevision === "r1", "startup revision")) return;
                theme.previewPalette(draft);
                if (!check(String(theme.paper) === "#abcdef" && String(theme.bg) === "#40abcdef", "preview values")) return;
                theme.cancelPreview();
                if (!check(String(theme.paper) === "#123456", "cancel preview")) return;
                theme.previewPalette(draft);
                generic.setText('background = "#999999"\n');
                theme.reloadPalette();
            } else if (stage === 4) {
                if (!check(String(theme.paper) === "#abcdef" && theme.previewColors !== null, "same revision reload preserves preview")) return;
                if (!check(theme.paletteRevision === "r1", "generic reload did not replace dedicated")) return;
                dedicated.setText('{"version":1,"colors":{"paper":"#fedcba"}}');
            } else if (stage === 6) {
                if (!check(theme.paletteError !== "" && theme.paletteRevision === "r1" && theme.appliedPalette.paper === "#123456" && theme.appliedPalette.bg === "#12345680", "partial dedicated retained last palette")) return;
                if (!check(String(theme.paper) === "#abcdef" && theme.previewColors !== null, "invalid file retained preview")) return;
                dedicated.setText('{bad json');
            } else if (stage === 8) {
                if (!check(theme.paletteError !== "" && String(theme.paper) === "#abcdef" && theme.appliedPalette.paper === "#123456", "malformed dedicated retained palette")) return;
                const changed = Object.assign({}, original, {paper:"#2468ac", bg:"#2468ac40"});
                dedicated.setText(doc("r2", changed));
            } else if (stage === 10) {
                if (!check(theme.paletteRevision === "r2" && String(theme.paper) === "#2468ac", "atomic replacement source switch " + theme.paletteRevision + " " + theme.paper)) return;
                if (!check(theme.previewColors === null && String(theme.bg) === "#402468ac", "source switch cancelled preview and alpha")) return;
                theme.previewPalette(Object.assign({}, original, {paper:"#ababab"}));
                theme.acceptPalette(Object.assign({}, original, {paper:"#2468ac", bg:"#2468ac40"}), "r2");
                if (!check(String(theme.paper) === "#ababab", "duplicate commit cancelled preview")) return;
                theme.acceptPalette(original, "r3");
                if (!check(theme.previewColors === null && String(theme.paper) === "#123456", "new revision cancelled preview")) return;
                console.log("theme palette passed"); Qt.quit();
            }
        }
    }
}
'''


def run(mode):
    with tempfile.TemporaryDirectory(prefix='qs-theme-test-') as temp:
        root = Path(temp)
        config = root / 'config'
        path = config / 'aether/theme'
        path.mkdir(parents=True)
        (path / 'colors.toml').write_text(LEGACY)
        if mode == 'dedicated':
            (path / 'quickshell.json').write_text(json.dumps(dict(version=1, revision='r1', colors=COLORS)))
        fixture = QML.replace('@DESKTOP@', DESKTOP.as_uri()).replace('@COLORS@', json.dumps(COLORS))
        (root / 'shell.qml').write_text(fixture)
        env = dict(os.environ, HOME=temp, XDG_CONFIG_HOME=str(config), XDG_RUNTIME_DIR=temp,
                   QT_QPA_PLATFORM='offscreen', QT_NO_XDG_DESKTOP_PORTAL='1', TEST_MODE=mode)
        result = subprocess.run(['qs', '-p', temp], env=env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        if result.returncode or 'theme ' + ('fallback' if mode == 'fallback' else 'palette') + ' passed' not in output or 'ASSERT:' in output:
            print(output)
            raise SystemExit(1)

run('fallback')
run('dedicated')
print('theme palette runtime tests passed')
