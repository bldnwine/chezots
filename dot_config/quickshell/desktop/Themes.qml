import QtQuick
import Quickshell
import Quickshell.Io
import "Data.js" as Data
import "Palette.js" as Palette

// Theme switcher. Probes both $OMARCHY_PATH/themes (official) and
// ~/.config/omarchy/themes (user) for theme directories, parses each
// theme's colors.toml into a swatch list, and marks the one whose
// colors.toml is byte-identical to ~/.config/omarchy/current/theme as
// active.
//
// The probe runs once per mode entry (cheap on a 24-theme machine).
// Selection drives the swatch preview through `swatches` on the
// selected item; Enter calls `omarchy-theme-set` via the parent's
// activate() special-case.
Item {
    id: themes

    required property bool active

    property var items: []
    property bool loaded: false
    readonly property bool running: probeProc.running

    function clear() {
        themes.items = [];
        themes.loaded = false;
    }

    function refresh() {
        // Emit one record per theme separated by a known sentinel so
        // JS only has to do one Process call + split. Header carries
        // name + marker (" " inactive, "*" active) + preview path, then
        // the colors.toml body. Preview is preview.png when the theme
        // ships one, otherwise the first file in the backgrounds/
        // subdir (sort+head for deterministic pick).
        probeProc.command = ["sh", "-c",
              "cur=$(cat \"$HOME/.config/aether/theme/colors.toml\" 2>/dev/null || cat \"$HOME/.config/omarchy/current/theme/colors.toml\" 2>/dev/null); "
            + "for d in \"$HOME/.config/aether/themes\"/*/ \"$OMARCHY_PATH/themes\"/*/ \"$HOME/.local/share/omarchy/themes\"/*/ \"$HOME/.config/omarchy/themes\"/*/; do "
            + "  [ -d \"$d\" ] || continue; "
            + "  name=$(basename \"$d\"); "
            + "  c=$(cat \"$d/colors.toml\" 2>/dev/null); "
            + "  marker=' '; [ -n \"$c\" ] && [ \"$c\" = \"$cur\" ] && marker='*'; "
            + "  prev=''; "
            + "  if [ -f \"$d/preview.png\" ]; then prev=\"$d/preview.png\"; "
            + "  elif [ -f \"$d/preview.jpg\" ]; then prev=\"$d/preview.jpg\"; "
            + "  elif [ -d \"$d/backgrounds\" ]; then "
            + "    for f in \"$d/backgrounds\"/*; do "
            + "      case \"$f\" in *.png|*.jpg|*.jpeg|*.webp|*.avif) prev=\"$f\"; break;; esac; "
            + "    done; "
            + "  fi; "
            + "  ts=$(stat -c %Y \"$d/colors.toml\" 2>/dev/null || stat -c %Y \"$d\" 2>/dev/null || echo 0); "
            + "  printf '===%s\\t%s\\t%s\\tTHEME\\t%s\\n%s\\n' \"$name\" \"$marker\" \"$prev\" \"$ts\" \"$c\"; "
            + "done; "
            + "for f in \"$HOME/.config/aether/blueprints\"/*.json; do "
            + "  [ -f \"$f\" ] || continue; "
            + "  name=$(basename \"$f\" .json); "
            + "  c=$(cat \"$f\" 2>/dev/null); "
            + "  printf '===%s\\t \\t\\tBLUEPRINT\\t0\\n%s\\n' \"$name\" \"$c\"; "
            + "done"];
        probeProc.running = false;
        probeProc.running = true;
    }

    // Background + foreground anchor the swatch pair; color1..color6 or
    // semantic names (red, green, blue...) fan out the accents.
    function paletteOf(toml) {
        const map = Palette.parseAll(toml);
        const want = ["background", "foreground", "color1", "color2", "color3", "color4", "color5", "color6", "red", "green", "yellow", "blue", "magenta", "cyan", "accent"];
        const out = [];
        for (let i = 0; i < want.length && out.length < 8; i++) {
            if (map[want[i]]) out.push(map[want[i]]);
        }
        if (out.length < 2) {
            for (let i = 0; i < 16 && out.length < 8; i++) {
                if (map["color" + i]) out.push(map["color" + i]);
            }
        }
        return out;
    }

    function ingest(text) {
        const chunks = (text || "").split("===");
        const out = [];
        const seen = {};
        for (let i = 0; i < chunks.length; i++) {
            const chunk = chunks[i];
            if (!chunk) continue;
            const nl = chunk.indexOf("\n");
            if (nl < 0) continue;
            const head = chunk.substring(0, nl);
            // header format: name<TAB>marker<TAB>previewPath<TAB>kind<TAB>timestamp
            const parts = head.split("\t");
            const name = parts[0] || "";
            const marker = parts[1] || " ";
            let previewImage = parts[2] || "";
            const kind = parts[3] || "THEME";
            let ts = parseInt(parts[4]) || 0;
            if (!name) continue;

            const body = chunk.substring(nl + 1);
            let swatches = [];
            const active = marker === "*";

            if (kind === "BLUEPRINT") {
                try {
                    const bp = JSON.parse(body);
                    if (bp) {
                        if (bp.timestamp) {
                            ts = (bp.timestamp > 1000000000000 ? Math.floor(bp.timestamp / 1000) : bp.timestamp);
                        }
                        if (bp.palette) {
                            const cols = bp.palette.colors || [];
                            if (cols.length >= 8) {
                                swatches = [
                                    cols[0],
                                    cols[7] || cols[15] || cols[0],
                                    cols[1],
                                    cols[2],
                                    cols[3],
                                    cols[4],
                                    cols[5],
                                    cols[6]
                                ];
                            }
                            if (!previewImage && bp.palette.wallpaper) {
                                previewImage = bp.palette.wallpaper;
                            }
                        }
                    }
                } catch (e) {}
            } else {
                swatches = themes.paletteOf(body);
            }

            const category = active ? "ACTIVE" : (kind === "BLUEPRINT" ? "BLUEPRINT" : "THEME");
            const kw = name + " " + (kind === "BLUEPRINT" ? "blueprint" : "theme") + " palette" + (active ? " active current" : "");
            const entry = {
                title: name,
                category: category,
                keywords: kw,
                icon: active ? "󰸌" : (kind === "BLUEPRINT" ? "󱥒" : "󰋩"),
                exec: "",
                themeName: name,
                isTheme: true,
                isActive: active,
                timestamp: ts,
                swatches: swatches,
                previewImage: previewImage,
                rawCategory: false,
                _t: name.toLowerCase(),
                _k: kw.toLowerCase(),
                _c: "theme"
            };

            const key = kind + ":" + name;
            if (seen[key] !== undefined) out[seen[key]] = entry;
            else { seen[key] = out.length; out.push(entry); }
        }
        // Active theme floats to the top. Then newest first (descending timestamp).
        out.sort((a, b) => {
            if (a.isActive !== b.isActive) return a.isActive ? -1 : 1;
            if (b.timestamp !== a.timestamp) return b.timestamp - a.timestamp;
            return a.title.localeCompare(b.title);
        });
        themes.items = out;
        themes.loaded = true;
    }

    // Refresh on entering the mode so the active marker stays honest
    // after the user swaps themes. Outside the mode we keep items
    // around so they remain searchable from root (typing "kanagawa"
    // outside the drill-in still surfaces the apply-theme row).
    onActiveChanged: { if (themes.active) themes.refresh(); }

    // Preload once at startup. Cheap (~24 small file reads), and means
    // theme rows are present in root search the first time the user
    // opens the palette, not just after entering the Themes drill-in.
    Component.onCompleted: themes.refresh()

    Process {
        id: probeProc
        running: false
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: { themes.ingest(this.text || ""); }
        }
    }
}
