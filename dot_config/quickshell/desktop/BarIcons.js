// Presentation mappings for the bundled bar icons; service glyphs remain unchanged.
function network(kind, strength, radioOn) {
    if (kind === "eth") return "network-wired-thin";
    if (kind !== "wifi") {
        return radioOn === false ? "network-wireless-hardware-disabled-symbolic"
                                 : "network-wireless-offline-symbolic";
    }
    return strength >= 66 ? "network-wireless-signal-good-symbolic"
         : strength >= 33 ? "network-wireless-signal-ok-symbolic"
                          : "network-wireless-signal-weak-symbolic";
}

function bluetooth(powered, count) {
    return !powered ? "bluetooth-disabled-symbolic"
         : count > 0 ? "bluetooth-active-symbolic"
                     : "bluetooth-disconnected-symbolic";
}

function audio(muted, device, volume) {
    if (muted) return "audio-volume-muted-symbolic";
    if (device === "hp") return "audio-headphones-breeze-medium";
    if (device === "bt") return "audio-speakers-symbolic";
    if (device === "hdmi") return "video-display-symbolic";
    return volume <= 0 ? "audio-volume-muted-symbolic"
         : volume < 34 ? "audio-volume-low-symbolic"
         : volume < 67 ? "audio-volume-medium-symbolic"
         : volume <= 100 ? "audio-volume-high-symbolic"
                         : "audio-volume-overamplified-symbolic";
}

function battery(state, percent) {
    const number = Number(percent);
    const level = Math.round(Math.max(0, Math.min(100, Number.isFinite(number) ? number : 0)) / 10) * 10;
    if (state === "Full") return "battery-level-100-charged-symbolic";
    const suffix = state === "Charging" ? (level === 100 ? "-charged" : "-charging")
                 : state === "Not charging" ? "-plugged-in" : "";
    return "battery-level-" + level + suffix + "-symbolic";
}

function notifications(dnd) { return dnd ? "notifications_off" : "notifications"; }
function warp(active) { return active ? "cloud" : "cloud_off"; }

const staticNames = ["memory", "smart_toy", "check", "priority_high", "media-record-symbolic"];

if (typeof module !== "undefined") module.exports = { network, bluetooth, audio, battery, notifications, warp, staticNames };
