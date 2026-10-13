const assert = require("assert");
const Audio = require("../AudioModel.js");
const Notifications = require("../NotificationModel.js");

function node(name, volume, extra = {}) {
    return { name, volume: { left: { value: volume * 65536 / 100 }, right: { value: volume * 65536 / 100 } }, ...extra };
}
function snapshot(sinks, sources, sink, source, physical = "") {
    return JSON.stringify(sinks) + "\n__SOURCES__\n" + JSON.stringify(sources)
        + "\n__DEFAULTS__\n" + [sink, source, physical].join("\n");
}

const speakers = node("alsa_output.speakers", 72, { active_port: "analog-output-speaker", description: "Built-in", mute: true });
const headphones = node("bluez_output.headset", 38, { active_port: "headphone", mute: false });
const mic = node("alsa_input.mic", 24, { mute: true });
assert.deepStrictEqual(Audio.parseSnapshot(snapshot([speakers], [mic], speakers.name, mic.name)), {
    sinkName: speakers.name, volume: 72, muted: true, inputVolume: 24, inputMuted: true,
    description: "Built-in", type: "spk", port: "Speakers"
});
const eq = node("effect_input.eq", 100);
const eqState = Audio.parseSnapshot(snapshot([eq, speakers, headphones], [mic], eq.name, mic.name, headphones.name));
assert.strictEqual(eqState.sinkName, headphones.name);
assert.strictEqual(eqState.volume, 38);
assert.strictEqual(eqState.type, "hp");
assert.strictEqual(Audio.parseSnapshot(snapshot([speakers], [], speakers.name, "")).inputVolume, 0);
assert.strictEqual(Audio.parseSnapshot("malformed"), null);
assert.strictEqual(Audio.parseSnapshot(snapshot([], [], "missing", "")), null);
assert.strictEqual(Audio.parseSnapshot("[]\n__SOURCES__\ninvalid\n__DEFAULTS__\nx\ny"), null);
assert.strictEqual(Audio.volumePercent({ volume: { left: { value: 65536 }, right: { value: 0 } } }), 50);

assert.deepStrictEqual(Notifications.recentHashes({ old: 1000, edge: 2000, fresh: 4000 }, 5000), { fresh: 4000 });
assert.strictEqual(Notifications.outsideRetention(1000, 1000 + 30 * 86400000, 30), false);
assert.strictEqual(Notifications.outsideRetention(999, 1000 + 30 * 86400000, 30), true);
console.log("audio snapshots and notification retention tests passed");
