// Parsers shared by the asynchronous /proc readers and their regression tests.
function cpuCounters(text) {
    const match = String(text || "").match(/^cpu[ \t]+([^\r\n]+)/m);
    if (!match) return null;
    const values = match[1].trim().split(/\s+/).slice(0, 8).map(Number);
    if (values.length !== 8 || values.some(v => !isFinite(v) || v < 0)) return null;
    // guest and guest_nice are already included in user and nice.
    return values;
}

function cpuPercent(before, after) {
    if (!before || !after) return null;
    let total = 0;
    let busy = 0;
    for (let i = 0; i < 8; i++) {
        const delta = after[i] - before[i];
        if (delta < 0) return null;
        total += delta;
        if (i !== 3 && i !== 4) busy += delta;
    }
    return total > 0 ? Math.floor(busy * 100 / total) : 0;
}

function memoryPercent(text) {
    const total = String(text || "").match(/^MemTotal:\s+(\d+)\s+kB\s*$/m);
    const available = String(text || "").match(/^MemAvailable:\s+(\d+)\s+kB\s*$/m);
    if (!total || !available) return null;
    const t = Number(total[1]);
    const a = Number(available[1]);
    return isFinite(t) && isFinite(a) && t > 0 && a <= t ? Math.floor((t - a) * 100 / t) : null;
}

function networkCounters(text) {
    const lines = String(text || "").trim().split("\n");
    if (lines.length < 2 || lines[0].indexOf("Inter-") < 0 || lines[1].indexOf("bytes") < 0) return null;
    const interfaces = Object.create(null);
    let total = 0;
    for (let i = 2; i < lines.length; i++) {
        if (!lines[i].trim()) continue;
        const match = lines[i].match(/^\s*([^:]+):\s*(.*)$/);
        if (!match) return null;
        const name = match[1].trim();
        if (name === "lo") continue;
        const fields = match[2].trim().split(/\s+/);
        if (fields.length < 16) return null;
        const rx = Number(fields[0]);
        const tx = Number(fields[8]);
        if (!isFinite(rx) || !isFinite(tx) || rx < 0 || tx < 0) return null;
        interfaces[name] = { rx: rx, tx: tx };
        total += rx + tx;
    }
    return { interfaces: interfaces, total: total };
}

function networkDelta(before, after) {
    if (!before || !after) return null;
    const names = Object.keys(after.interfaces);
    if (names.length !== Object.keys(before.interfaces).length) return null;
    for (let i = 0; i < names.length; i++) {
        const old = before.interfaces[names[i]];
        const next = after.interfaces[names[i]];
        if (!old || next.rx < old.rx || next.tx < old.tx) return null;
    }
    return after.total - before.total;
}

if (typeof module !== "undefined") module.exports = { cpuCounters, cpuPercent, memoryPercent, networkCounters, networkDelta };
