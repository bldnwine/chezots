function defaults() {
    return {panelScale: 1, locusScale: 1, panelTextScale: 1, locusTextScale: 1,
        panelOpacity: null, locusOpacity: null, panelBlur: false, locusBlur: false,
        normalWidth: 640, previewWidth: 1000, locusHeight: 0, windowWidth: 900, windowHeight: 700};
}
function settings(input) {
    const out = defaults();
    const bounds = {panelScale: [.75, 1.5], locusScale: [.75, 1.5], panelTextScale: [.7, 2], locusTextScale: [.7, 2],
        panelOpacity: [0, 1], locusOpacity: [0, 1], normalWidth: [480, 4000], previewWidth: [800, 4000], locusHeight: [0, 4000], windowWidth: [760, 4000], windowHeight: [400, 4000]};
    if (!input || typeof input !== 'object' || Array.isArray(input)) return out;
    for (const key of Object.keys(out)) {
        let value = input[key];
        if (key === 'panelBlur' || key === 'locusBlur') {
            if (typeof value === 'boolean') out[key] = value;
            continue;
        }
        if (typeof value !== 'number' || !isFinite(value)) continue;
        value = Math.max(bounds[key][0], Math.min(bounds[key][1], value));
        if (key === "locusHeight" && value > 0 && value < 360) value = 360;
        out[key] = (key.indexOf('Scale') >= 0 || key.indexOf('Opacity') >= 0) ? value : Math.round(value);
    }
    return out;
}
function normalize(input) {
    if (!input || input.version !== 1 || !input.settings || typeof input.settings !== 'object' || Array.isArray(input.settings))
        throw new Error('Invalid settings.json format or unsupported version');
    return {version: 1, settings: settings(input.settings)};
}
function initial() { return {version: 1, settings: defaults()}; }
function sectionKeys(name) {
    return name === 'panels' ? ['panelScale', 'panelTextScale', 'panelOpacity', 'panelBlur'] : name === 'locus' ?
        ['locusScale', 'locusTextScale', 'locusOpacity', 'locusBlur', 'normalWidth', 'previewWidth', 'locusHeight'] : [];
}
if (typeof module !== 'undefined') module.exports = {defaults, settings, normalize, initial, sectionKeys};
