.pragma library

// Static base list for the Quick-mode tile grid. Order matches the
// Samsung-style quick panel - most glanced (battery/audio/wifi/bt)
// first. The Repeater's 12 delegates are built once from this array and
// never torn down; per-tile live data lives in the parallel `dyn` map
// the QuickContainer builds from navbar telemetry on every tick.
var base = [
    { key: "battery",     keywords: "battery power charge plugged ac percent watt",
      action: "omarchy-menu power" },
    { key: "audio",       keywords: "audio sound speaker volume mute pulse pipewire",
      action: "omarchy-launch-audio", longAction: "pamixer -t" },
    { key: "network",     keywords: "wifi wireless network internet ssid signal ethernet eth",
      action: "omarchy-launch-wifi" },
    { key: "bluetooth",   keywords: "bluetooth bt pair device headset speaker keyboard",
      action: "omarchy-launch-bluetooth" },
    { key: "weather",     keywords: "weather forecast temperature wttr rain sun wind",
      action: "qs -c desktop ipc call weather toggle",
      longAction: "qs -c desktop ipc call weather refresh" },
    { key: "display",     keywords: "display monitor brightness warmth gamma night light blue temperature dim",
      action: "qs -c desktop ipc call display toggle",
      longAction: "qs -c desktop ipc call display reset" },
    { key: "aether",      keywords: "aether theme blueprint palette swatch picker wallpaper",
      action: "qs -c desktop ipc call aether toggle",
      longAction: "sh -c 'aether --generate \"$(aether --random-wallpaper)\"'" },
    { key: "cpu",         keywords: "cpu processor memory monitor btop top htop performance load",
      action: "omarchy-launch-or-focus-tui btop" },
    { key: "calendar",    keywords: "calendar date month day today schedule planner",
      action: "qs -c desktop ipc call calendar toggle" },
    { key: "screenshots", keywords: "screenshots shots browse pictures captures images gallery",
      action: "qs -c desktop ipc call screenshots toggle",
      longAction: "omarchy-capture-screenshot" },
    { key: "videos",      keywords: "videos films clips recordings browse gallery library",
      action: "qs -c desktop ipc call videos toggle" },
    { key: "power",       keywords: "power menu suspend hibernate logout restart shutdown lock",
      action: "omarchy-menu power" }
];

// Build the per-tile dynamic map (glyph/label/sub/tone) from live
// navbar state. Caller passes the navbar instance; this function does
// not retain it. Returns {} when navbar is missing so delegate
// bindings can still chain `.glyph`/`.sub` reads via `({}).foo`.
function buildDyn(n) {
    if (!n) return ({});
    const chargingTag = n.batState === "Charging"    ? " · CHARGING"
                      : n.batState === "Full"        ? " · FULL"
                      : n.batState === "Not charging" ? " · PLUGGED"
                      : "";
    return {
        battery: {
            glyph: n.batteryIcon(),
            label: "BATTERY",
            sub: n.batVal + "%" + chargingTag
                 + (n.batPower >= 0.05
                    ? "  " + n.batPower.toFixed(1) + "W"
                    : ""),
            tone: n.batVal <= 10 ? n.seal
                                 : n.batVal <= 20 ? n.indigo
                                                  : n.ink
        },
        audio: {
            glyph: n.audioIcon,
            label: "AUDIO",
            sub: n.audioMuted ? "MUTED" : (n.audioVol + "%"),
            tone: n.audioMuted ? n.seal : n.ink
        },
        network: {
            glyph: n.netIcon,
            label: n.netKind === "wifi" ? "WI-FI"
                   : n.netKind === "eth"  ? "ETHERNET"
                                          : "OFFLINE",
            sub: n.netKind === "wifi"
                 ? ((n.wifiSsid || "(hidden)") + " · " + n.wifiSignal + "%")
                 : n.netKind === "eth" ? "CONNECTED" : "—",
            tone: n.netKind === "none" ? n.inkDeep : n.ink
        },
        bluetooth: {
            glyph: n.btIcon,
            label: "BLUETOOTH",
            sub: !n.btPowered ? "OFF"
                              : (n.btCount > 0 ? n.btCount + " CONN" : "ON"),
            tone: !n.btPowered ? n.inkDeep : n.ink
        },
        weather: {
            glyph: n.weatherUnavailable ? "?"
                 : (n.weatherLoaded ? n.weatherIcon : "·"),
            label: "WEATHER",
            sub: n.weatherUnavailable ? "OFFLINE"
                 : (n.weatherLoaded ? Math.round(n.weatherTempC) + "°C" : "…"),
            tone: n.weatherUnavailable ? n.inkDeep : n.ink
        },
        display: {
            glyph: n.icoDisplay,
            label: "DISPLAY",
            sub: n.brightnessPct + "%"
                 + (n.warmthK < 6500 ? "  " + n.warmthK + "K" : ""),
            tone: (n.warmthK < 6500 || n.gammaPct !== 100 || n.brightnessPct < 100)
                  ? n.seal : n.ink
        },
        aether:      { glyph: n.icoAether, label: "AETHER", sub: "THEMES", tone: n.ink },
        cpu: {
            glyph: "󰍛",
            label: "CPU",
            sub: Math.round(n.cpuVal) + "%",
            tone: n.cpuVal > 80 ? n.seal : n.ink
        },
        calendar:    { glyph: "󰃭",          label: "CALENDAR",    sub: n.dd + " " + n.mon, tone: n.ink },
        screenshots: { glyph: n.icoCamera,  label: "SHOTS",       sub: "BROWSE",           tone: n.ink },
        videos:      { glyph: n.icoFilm,    label: "VIDEOS",      sub: "BROWSE",           tone: n.ink },
        power:       { glyph: n.icoPower,   label: "POWER",       sub: "MENU",             tone: n.ink }
    };
}
