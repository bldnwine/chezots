.pragma library

// WANTED is the single source of truth for which raw colors.toml keys map
// onto this shell's semantic slots. Both the startup FileView read and the
// IPC push path translate through it.
const WANTED = {
    background: "paper",
    foreground: "ink",
    color7:     "inkDeep",
    color8:     "sumi",
    accent:     "indigo",
    color2:     "green",
    color1:     "sealRaw",
};

const LINE = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/;

function parseAll(text) {
    const out = {};
    if (!text) return out;
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
        const m = lines[i].match(LINE);
        if (m) out[m[1].toLowerCase()] = m[2];
    }
    return out;
}

function mapKeys(raw) {
    const out = {};
    if (!raw) return out;
    for (const key in WANTED) {
        if (validColor(raw[key])) out[WANTED[key]] = raw[key];
    }
    return out;
}

const ROLES = ["paper", "ink", "inkDeep", "sumi", "indigo", "green", "sealRaw",
               "bg", "warn", "sep", "rowHi", "rowSel"];

function validColor(value) {
    return typeof value === "string" && /^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(value);
}

// Files and the headless Aether API use web-style RGBA, with alpha last.
// QML's QColor string parser expects alpha first instead.
function qmlColor(value) {
    return value.length === 9 ? "#" + value.slice(7, 9) + value.slice(1, 7) : value;
}

function withAlpha(value, alpha) { return value.slice(0, 7) + alpha; }

function complete(input) {
    const out = {};
    for (const key of ROLES) {
        if (validColor(input[key])) out[key] = input[key].toLowerCase();
    }
    if (!out.bg && out.paper) out.bg = withAlpha(out.paper, "f0");
    if (!out.warn && out.sealRaw) out.warn = out.sealRaw;
    if (!out.sep && out.ink) out.sep = withAlpha(out.ink, "2e");
    if (!out.rowHi && out.ink) out.rowHi = withAlpha(out.ink, "0f");
    if (!out.rowSel && out.sealRaw) out.rowSel = withAlpha(out.sealRaw, "2e");
    return out;
}

function decode(text) {
    const document = JSON.parse(text);
    if (!document || document.version !== 1 || !document.colors)
        throw new Error("Unsupported Quickshell palette");
    for (const key of ROLES) {
        if (!validColor(document.colors[key])) throw new Error("Invalid palette color: " + key);
    }
    return {colors: complete(document.colors), revision: String(document.revision || "")};
}

function parse(text) {
    return mapKeys(parseAll(text));
}

// Write a parsed palette onto a Theme.qml instance. Missing slots are left
// at their current value so a partial palette never blanks the live theme.
function apply(theme, palette) {
    if (typeof theme.acceptPalette === "function") {
        theme.acceptPalette(complete(palette));
        return;
    }
    if (palette.paper)   theme.paper   = palette.paper;
    if (palette.ink)     theme.ink     = palette.ink;
    if (palette.inkDeep) theme.inkDeep = palette.inkDeep;
    if (palette.sumi)    theme.sumi    = palette.sumi;
    if (palette.indigo)  theme.indigo  = palette.indigo;
    if (palette.green)   theme.green   = palette.green;
    if (palette.sealRaw) theme.sealRaw = palette.sealRaw;
}
