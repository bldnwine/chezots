import QtQuick
import Quickshell.Io
import "Data.js" as Data

// Scans XDG application directories and provides demand-driven freshness checking.
// configparser handles the gnarly bits — section headers, continuation lines,
// encodings, comments, mixed quoting. Result is cached on `apps` (annotated)
// and re-evaluates on demand via refresh() or checkFreshness().
Item {
    id: appScan

    property var apps: []
    property bool loaded: false
    property string lastFingerprint: ""

    signal scanned()

    function refresh() {
        proc.running = false;
        proc.running = true;
    }

    function checkFreshness() {
        if (!proc.running && !mtimeChecker.running) {
            mtimeChecker.running = true;
        }
    }

    // Asynchronous demand-driven freshness check (Tofi model).
    // Checks timestamps of XDG application directories and user .desktop files (~4ms).
    // Completely non-blocking and zero idle CPU.
    Process {
        id: mtimeChecker
        running: false
        command: ["bash", "-c",
            "stat -c %Y $HOME/.local/share/applications $HOME/.local/share/applications/*.desktop /usr/share/applications /var/lib/flatpak/exports/share/applications $HOME/.local/share/flatpak/exports/share/applications /var/lib/snapd/desktop/applications 2>/dev/null | sort -n | tail -n 5 | tr '\\n' '|'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const fp = this.text.trim();
                if (!appScan.lastFingerprint) {
                    appScan.lastFingerprint = fp;
                } else if (fp !== appScan.lastFingerprint) {
                    console.log("[AppScan] Freshness mismatch detected (" + fp + " vs " + appScan.lastFingerprint + "), refreshing apps");
                    appScan.lastFingerprint = fp;
                    appScan.refresh();
                }
            }
        }
    }

    Process {
        id: proc
        running: false
        command: ["python3", "-c", "import os, re, configparser, sys\n" +
            "dirs = [\n" +
            "    os.path.expanduser('~/.local/share/applications'),\n" +
            "    '/usr/share/applications',\n" +
            "    '/var/lib/flatpak/exports/share/applications',\n" +
            "    os.path.expanduser('~/.local/share/flatpak/exports/share/applications'),\n" +
            "    '/var/lib/snapd/desktop/applications',\n" +
            "]\n" +
            "rx = re.compile(r'%[fFuUdDnNickvm]')\n" +
            "seen = set()\n" +
            "out = []\n" +
            "for d in dirs:\n" +
            "    if not os.path.isdir(d):\n" +
            "        continue\n" +
            "    dir_files = []\n" +
            "    for root_dir, _, files in os.walk(d):\n" +
            "        for f in files:\n" +
            "            if f.endswith('.desktop'):\n" +
            "                dir_files.append(os.path.join(root_dir, f))\n" +
            "    dir_files.sort()\n" +
            "    for full_path in dir_files:\n" +
            "        cp = configparser.RawConfigParser(strict=False, interpolation=None)\n" +
            "        try:\n" +
            "            cp.read(full_path, encoding='utf-8')\n" +
            "        except Exception:\n" +
            "            continue\n" +
            "        if 'Desktop Entry' not in cp:\n" +
            "            continue\n" +
            "        de = cp['Desktop Entry']\n" +
            "        if de.get('NoDisplay', '').lower() == 'true':\n" +
            "            continue\n" +
            "        if de.get('Hidden', '').lower() == 'true':\n" +
            "            continue\n" +
            "        if de.get('Type', 'Application').strip() != 'Application':\n" +
            "            continue\n" +
            "        name = de.get('Name', '').strip()\n" +
            "        if not name:\n" +
            "            continue\n" +
            "        key = name.lower()\n" +
            "        if key in seen:\n" +
            "            continue\n" +
            "        seen.add(key)\n" +
            "        comment = de.get('Comment', '').strip()\n" +
            "        keywords = de.get('Keywords', '').strip().replace(';', ' ')\n" +
            "        categories = de.get('Categories', '').strip().replace(';', ' ')\n" +
            "        exe = rx.sub('', de.get('Exec', '').strip()).strip()\n" +
            "        if not exe:\n" +
            "            continue\n" +
            "        icon = de.get('Icon', '').strip()\n" +
            "        gname = de.get('GenericName', '').strip()\n" +
            "        term = '1' if de.get('Terminal', '').lower() == 'true' else ''\n" +
            "        def s(x):\n" +
            "            return x.replace('\\t', ' ').replace('\\n', ' ').replace('\\r', ' ')\n" +
            "        out.append('\\t'.join([s(name), s(comment), s(keywords), s(categories), s(exe), s(icon), s(gname), term]))\n" +
            "sys.stdout.write('\\n'.join(out))\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(s => s.length > 0);
                const apps = new Array(lines.length);
                let n = 0;
                for (let i = 0; i < lines.length; i++) {
                    const p = lines[i].split("\t");
                    if (p.length < 7) continue;
                    apps[n++] = {
                        title: p[0],
                        comment: p[1],
                        keywords: (p[2] + " " + p[3] + " " + p[6] + " " + p[1]).toLowerCase(),
                        category: "App",
                        icon: "󰀻",
                        exec: p[4],
                        rawIcon: p[5],
                        // Terminal=true in the .desktop entry — apps like
                        // cliamp need a TTY to render; without one they
                        // exit immediately when launched detached.
                        tui: p[7] === "1" ? "omarchy-launch-tui" : ""
                    };
                }
                apps.length = n;
                appScan.apps = Data.annotate(apps);
                appScan.loaded = true;
                console.log("[AppScan] Scanned " + appScan.apps.length + " applications");
                appScan.scanned();
                if (!appScan.lastFingerprint) {
                    appScan.checkFreshness();
                }
            }
        }
    }

    Component.onCompleted: appScan.refresh()
}
