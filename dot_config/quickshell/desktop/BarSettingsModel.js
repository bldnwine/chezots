// Plain JSON model, shared by migration, persistence and regression tests.
function defaults() {
    return {variant: "zen", type: "floating", transparent: false, opacity: 1,
            height: 26, air: 5, rounding: 6, edge: "top"};
}
function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function settings(input) {
    const out = defaults();
    if (!object(input)) return out;
    for (const key of ["variant", "type", "edge"]) {
        const allowed = {variant: ["zen"], type: ["floating", "slab", "notch"], edge: ["top", "right", "bottom", "left"]};
        if (allowed[key].indexOf(input[key]) !== -1) out[key] = input[key];
    }
    if (typeof input.transparent === "boolean") out.transparent = input.transparent;
    for (const key of ["opacity", "height", "air", "rounding"]) {
        if (typeof input[key] !== "number" || !isFinite(input[key])) continue;
        const bounds = {opacity: [0.2, 1], height: [22, 40], air: [0, 360], rounding: [0, 12]};
        const v = key === "opacity" ? input[key] : Math.round(input[key]);
        out[key] = Math.max(bounds[key][0], Math.min(bounds[key][1], v));
    }
    return out;
}
function templates(input) {
    const out = {};
    if (!object(input)) return out;
    for (const name of Object.keys(input)) {
        if (name === "zen" || !/^[A-Za-z0-9 _-]{1,24}$/.test(name) || !object(input[name])) continue;
        // Old templates without an edge retain the current edge when applied.
        out[name] = settings(input[name]);
        if (input[name].edge === undefined) delete out[name].edge;
    }
    return out;
}
function normalize(input) {
    if (!object(input) || input.version !== 1 || !object(input.settings) || !object(input.templates))
        throw new Error("Invalid bar.json format or unsupported version");
    const saved = templates(input.templates);
    const selected = input.selectedTemplate === "zen" || Object.prototype.hasOwnProperty.call(saved, input.selectedTemplate)
        ? input.selectedTemplate : "zen";
    return {version: 1, settings: settings(input.settings), templates: saved, selectedTemplate: selected};
}
function initial() { return {version: 1, settings: defaults(), templates: {}, selectedTemplate: "zen"}; }
function migrate(files) {
    const input = {};
    for (const key of Object.keys(defaults())) {
        const raw = files["bar-" + key];
        if (raw === undefined) continue;
        if (key === "transparent") input[key] = raw === "1";
        else if (["opacity", "height", "air", "rounding"].indexOf(key) !== -1) input[key] = parseFloat(raw);
        else input[key] = raw;
    }
    let saved = {};
    try { saved = JSON.parse(files["bar-templates.json"] || "{}"); } catch (_) {}
    return normalize({version: 1, settings: input, templates: object(saved) ? saved : {}, selectedTemplate: files["bar-template"] || "zen"});
}
if (typeof module !== "undefined") module.exports = {defaults, settings, templates, normalize, initial, migrate};
