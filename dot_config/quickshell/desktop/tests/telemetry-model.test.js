const assert = require("assert");
const Model = require("../TelemetryModel.js");

const before = Model.cpuCounters("cpu 100 20 30 500 10 5 15 0 1000 1000\ncpu0 1 2 3\n");
const after = Model.cpuCounters("cpu 140 20 50 540 10 5 15 0 2000 2000\n");
assert.deepStrictEqual(before, [100, 20, 30, 500, 10, 5, 15, 0]);
assert.strictEqual(Model.cpuPercent(before, after), 60, "guest time must not be counted twice");
assert.strictEqual(Model.cpuPercent(before, before), 0);
assert.strictEqual(Model.cpuPercent(after, before), null, "counter resets must not publish bogus CPU");
assert.strictEqual(Model.cpuCounters("cpu0 1 2 3 4 5 6 7 8"), null);
assert.strictEqual(Model.cpuCounters("cpu 1 2 3 4 5 6 7"), null);
assert.strictEqual(Model.cpuCounters("cpu 1 2 3 NaN 5 6 7 8"), null);
assert.strictEqual(Model.cpuCounters(null), null);
assert.strictEqual(Model.memoryPercent("MemTotal: 1000 kB\nMemAvailable: 251 kB\n"), 74);
for (const text of ["", "MemTotal: 0 kB\nMemAvailable: 0 kB", "MemTotal: 10 kB",
    "MemTotal: 10 kB\nMemAvailable: 11 kB"]) assert.strictEqual(Model.memoryPercent(text), null);

function network(rows) {
    const header = "Inter-| Receive | Transmit\n face | bytes packets errs drop fifo frame compressed multicast | bytes packets errs drop fifo colls carrier compressed\n";
    return Model.networkCounters(header + rows.map(([name, rx, tx]) =>
        ` ${name}: ${rx} 0 0 0 0 0 0 0 ${tx} 0 0 0 0 0 0 0`).join("\n"));
}
const netBefore = network([["lo", 99999999, 99999999], ["eth0", 100, 200], ["proton0", 10, 20]]);
const netAfter = network([["eth0", 150, 230], ["proton0", 15, 25]]);
assert.strictEqual(netBefore.total, 330, "loopback is excluded, VPN interfaces remain included");
assert.strictEqual(Model.networkDelta(netBefore, netAfter), 90);
assert.strictEqual(Model.networkDelta(netBefore, netBefore), 0);
assert.strictEqual(Model.networkDelta(null, netAfter), null);
assert.strictEqual(Model.networkDelta(netBefore, network([["eth0", 999999, 999999]])), null);
assert.strictEqual(Model.networkDelta(netBefore, network([["eth0", 999999, 999999], ["tun0", 10, 20]])), null);
assert.strictEqual(Model.networkDelta(netBefore, network([["eth0", 99, 999999], ["proton0", 10, 20]])), null,
    "a reset must not be masked by growth in another counter");
assert.strictEqual(Model.networkCounters("corrupt"), null);
assert.strictEqual(Model.networkCounters("Inter-\nbytes\neth0: 1 2"), null);
assert.strictEqual(Model.networkCounters("Inter-\nbytes\neth0: bad 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0"), null);
console.log("telemetry parser and counter regression tests passed");
