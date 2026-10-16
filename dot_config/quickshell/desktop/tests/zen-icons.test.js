const assert = require("assert");
const fs = require("fs");
const path = require("path");
const Icons = require("../ZenIcons.js");
const Metrics = require("../MaterialMetrics.js");

// Connection state takes precedence over signal data left from a previous link.
assert.strictEqual(Icons.network("none", 100), "wifi_off");
assert.strictEqual(Icons.network("eth", 0), "lan");
for (const [strength, name] of [[0, "wifi_1_bar"], [39, "wifi_1_bar"],
    [40, "wifi_2_bar"], [79, "wifi_2_bar"], [80, "wifi"], [100, "wifi"]]) {
    assert.strictEqual(Icons.network("wifi", strength), name);
}
assert.strictEqual(Icons.bluetooth(false, 2), "bluetooth_disabled");
assert.strictEqual(Icons.bluetooth(true, 0), "bluetooth");
assert.strictEqual(Icons.bluetooth(true, 1), "bluetooth_connected");

// Muting must remain visible for every output type; device identity wins at zero.
for (const device of ["hp", "bt", "hdmi", "spk"]) {
    assert.strictEqual(Icons.audio(true, device, 100), "volume_off");
}
for (const [device, name] of [["hp", "headphones"], ["bt", "speaker"], ["hdmi", "monitor"]]) {
    assert.strictEqual(Icons.audio(false, device, 0), name);
}
for (const [volume, name] of [[0, "volume_mute"], [1, "volume_down"],
    [66, "volume_down"], [67, "volume_up"], [150, "volume_up"]]) {
    assert.strictEqual(Icons.audio(false, "spk", volume), name);
}

// Full and Not charging still represent external power, rather than discharge.
for (const state of ["Charging", "Full", "Not charging"]) {
    assert.strictEqual(Icons.acPowered(state), true);
    assert.strictEqual(Icons.battery(state, 0), "power");
}
assert.strictEqual(Icons.acPowered("Discharging"), false);
for (const [percent, name] of [[0, "battery_0_bar"], [12, "battery_0_bar"],
    [12.5, "battery_1_bar"], [75, "battery_6_bar"], [87.5, "battery_full"],
    [100, "battery_full"], [-1, "battery_0_bar"], [101, "battery_full"],
    [undefined, "battery_0_bar"]]) {
    assert.strictEqual(Icons.battery("Discharging", percent), name);
}

// Every mapped symbol must work offline in both fill states.
const names = new Set(["memory", "smart_toy", "notifications", "notifications_off",
    "cloud", "cloud_off", "videocam", "music_note", "check", "priority_high"]);
for (const kind of ["none", "eth", "wifi"]) {
    for (const signal of [0, 40, 80]) names.add(Icons.network(kind, signal));
}
for (const powered of [false, true]) {
    for (const count of [0, 1]) names.add(Icons.bluetooth(powered, count));
}
for (const muted of [false, true]) {
    for (const device of ["spk", "hp", "bt", "hdmi"]) {
        for (const volume of [0, 1, 67]) names.add(Icons.audio(muted, device, volume));
    }
}
for (const percent of [0, 12.5, 25, 37.5, 50, 62.5, 75, 100]) {
    names.add(Icons.battery("Discharging", percent));
}
names.add(Icons.battery("Charging", 50));
for (const name of names) {
    const bounds = Metrics.bounds(name);
    assert(bounds[2] > 0 && bounds[3] > 0, name + " needs measured SVG bounds");
    assert(Object.hasOwn(Metrics.inkBounds, name), name + " is missing its geometry");
    for (const suffix of ["", "_fill1"]) {
        const svg = fs.readFileSync(path.join(__dirname, "../icons/material-rounded",
            name + suffix + "_20px.svg"), "utf8");
        assert.match(svg, /<svg[^>]*viewBox="0 -960 960 960"/);
        assert.match(svg, /<path /);
    }
}
// Low signal must retain the full icon's scale, rather than becoming a huge dot.
assert.deepStrictEqual(Metrics.bounds("wifi_1_bar"), Metrics.bounds("wifi"));
assert.deepStrictEqual(Metrics.bounds("wifi_2_bar"), Metrics.bounds("wifi"));
console.log(`Zen icon mappings and ${names.size * 2} local SVG variants passed`);
