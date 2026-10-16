// Presentation mappings only; the shared service glyphs stay available.
function network(kind, strength) {
    if (kind === "eth") return "lan";
    if (kind !== "wifi") return "wifi_off";
    return strength >= 80 ? "wifi" : strength >= 40 ? "wifi_2_bar" : "wifi_1_bar";
}

function bluetooth(powered, count) {
    return !powered ? "bluetooth_disabled" : count > 0 ? "bluetooth_connected" : "bluetooth";
}

function audio(muted, device, volume) {
    if (muted) return "volume_off";
    if (device === "hp") return "headphones";
    if (device === "bt") return "speaker";
    if (device === "hdmi") return "monitor";
    return volume <= 0 ? "volume_mute" : volume < 67 ? "volume_down" : "volume_up";
}

function acPowered(state) {
    return state === "Charging" || state === "Full" || state === "Not charging";
}

function battery(state, percent) {
    if (acPowered(state)) return "power";
    const level = Math.max(0, Math.min(7, Math.floor((Number(percent) || 0) / 12.5)));
    return level === 7 ? "battery_full" : "battery_" + level + "_bar";
}

if (typeof module !== "undefined") module.exports = { network, bluetooth, audio, acPowered, battery };
