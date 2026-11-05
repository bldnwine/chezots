const assert = require("assert");
const fs = require("fs");
const path = require("path");
const icons = require("../BarIcons.js");
const metrics = require("../BarIconMetrics.js");

assert.strictEqual(icons.network("eth", 0, false), "network-wired-thin");
assert.strictEqual(icons.network("none", 100, false), "network-wireless-hardware-disabled-symbolic");
assert.strictEqual(icons.network("none", 100, true), "network-wireless-offline-symbolic");
for (const [strength, level] of [[0, "weak"], [32, "weak"], [33, "ok"], [65, "ok"], [66, "good"], [100, "good"]]) {
    assert.strictEqual(icons.network("wifi", strength, true), `network-wireless-signal-${level}-symbolic`);
}
assert.strictEqual(icons.bluetooth(false, 1), "bluetooth-disabled-symbolic");
assert.strictEqual(icons.bluetooth(true, 0), "bluetooth-disconnected-symbolic");
assert.strictEqual(icons.bluetooth(true, 1), "bluetooth-active-symbolic");
for (const device of ["spk", "hp", "bt", "hdmi"]) {
    assert.strictEqual(icons.audio(true, device, 100), "audio-volume-muted-symbolic");
}
for (const [device, name] of [["hp", "audio-headphones-breeze-medium"], ["bt", "audio-speakers-symbolic"], ["hdmi", "video-display-symbolic"]]) {
    assert.strictEqual(icons.audio(false, device, 0), name);
}
for (const [volume, level] of [[0, "muted"], [1, "low"], [33, "low"], [34, "medium"], [66, "medium"], [67, "high"], [100, "high"], [101, "overamplified"]]) {
    assert.strictEqual(icons.audio(false, "spk", volume), `audio-volume-${level}-symbolic`);
}
for (const [percent, level] of [[-1, 0], [0, 0], [4, 0], [5, 10], [94, 90], [95, 100], [101, 100], [NaN, 0], [Infinity, 0], [undefined, 0]]) {
    assert.strictEqual(icons.battery("Discharging", percent), `battery-level-${level}-symbolic`);
    assert.strictEqual(icons.battery("Not charging", percent), `battery-level-${level}-plugged-in-symbolic`);
    assert.strictEqual(icons.battery("Charging", percent), `battery-level-${level}-${level === 100 ? "charged" : "charging"}-symbolic`);
    assert.strictEqual(icons.battery("Full", percent), "battery-level-100-charged-symbolic");
}
assert.strictEqual(icons.notifications(true), "notifications_off");
assert.strictEqual(icons.notifications(false), "notifications");
assert.strictEqual(icons.warp(true), "cloud");
assert.strictEqual(icons.warp(false), "cloud_off");

// Exercise all variants and require each mapping to resolve to a local SVG.
const names = new Set(icons.staticNames);
for (const kind of ["none", "eth", "wifi"]) for (const radio of [false, true]) for (const strength of [0, 33, 66]) names.add(icons.network(kind, strength, radio));
for (const powered of [false, true]) for (const count of [0, 1]) names.add(icons.bluetooth(powered, count));
for (const muted of [false, true]) for (const device of ["spk", "hp", "bt", "hdmi"]) for (const volume of [0, 1, 34, 67, 101]) names.add(icons.audio(muted, device, volume));
for (const state of ["Discharging", "Charging", "Full", "Not charging"]) for (let level = 0; level <= 100; level += 10) names.add(icons.battery(state, level));
for (const active of [false, true]) { names.add(icons.notifications(active)); names.add(icons.warp(active)); }
for (const name of names) {
    const file = path.join(__dirname, "../icons/bar", name + ".svg");
    assert(Object.hasOwn(metrics.inkBounds, name), `missing geometry: ${name}`);
    const bounds = metrics.bounds(name);
    assert(bounds.every(Number.isFinite) && bounds[2] > 0 && bounds[3] > 0, `invalid geometry: ${name}`);
    assert(fs.existsSync(file), `missing bar icon: ${name}`);
    assert.match(fs.readFileSync(file, "utf8"), /<svg\b/, `invalid SVG: ${name}`);
}
console.log(`Bar icon mappings and ${names.size} local SVG assets passed`);

// State variants share one frame, so disappearing details never grow the icon.
for (const prefix of ["network-wireless-", "bluetooth-", "audio-volume-", "battery-level-"]) {
    const family = Object.keys(metrics.inkBounds).filter(name => name.startsWith(prefix));
    for (const name of family) assert.deepStrictEqual(metrics.bounds(name), metrics.bounds(family[0]));
}
assert.deepStrictEqual(metrics.bounds("notifications"), metrics.bounds("notifications_off"));
assert.deepStrictEqual(metrics.bounds("cloud"), metrics.bounds("cloud_off"));
assert.deepStrictEqual(metrics.bounds("unknown"), [0, 0, 1, 1]);
console.log("Bar artwork geometry and stable variant frames passed");

const wired = fs.readFileSync(path.join(__dirname, "../icons/bar/network-wired-thin.svg"), "utf8");
assert(wired.includes('fill="none"') && wired.includes('stroke="currentColor"'));
