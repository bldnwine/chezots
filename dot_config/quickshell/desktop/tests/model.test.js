const assert = require("assert")
const Model = require("../WarpModel.js")

function test(name, fn) {
  try {
    fn()
    console.log("  ok ", name)
  } catch (err) {
    console.error("FAIL ", name)
    console.error(err)
    process.exitCode = 1
  }
}

test("humanize turns CLI identifiers into prose", () => {
  assert.strictEqual(Model.humanize("RegistrationMissing"), "Registration missing")
  assert.strictEqual(Model.humanize("always_on"), "Always on")
  assert.strictEqual(Model.humanize("tunnel_only"), "Tunnel only")
  assert.strictEqual(Model.humanize(""), "")
})

test("isDaemonDown recognizes all daemon error formats", () => {
  assert.strictEqual(Model.isDaemonDown(JSON.stringify({ code: "FailedToConnectToDaemon", error: "No such file or directory (os error 2)" })), true)
  assert.strictEqual(Model.isDaemonDown("Unable to connect to the CloudflareWARP daemon"), true)
  assert.strictEqual(Model.isDaemonDown("daemon is not running"), true)
})

test("parseStatus reads a connected daemon", () => {
  const parsed = Model.parseStatus(JSON.stringify({ status: "Connected" }), 0, "")
  assert.strictEqual(parsed.ok, true)
  assert.strictEqual(parsed.connected, true)
  assert.strictEqual(parsed.daemonDown, false)
  assert.strictEqual(parsed.statusText, "Connected")
})

test("parseStatus handles daemon down gracefully", () => {
  const parsed = Model.parseStatus(JSON.stringify({ code: "FailedToConnectToDaemon", error: "No such file or directory (os error 2)" }), 1, "")
  assert.strictEqual(parsed.ok, true)
  assert.strictEqual(parsed.connected, false)
  assert.strictEqual(parsed.daemonDown, true)
  assert.strictEqual(parsed.statusText, "WARP daemon is not running")
})

test("mode helpers cover tunnel_only and Quad9 annotations", () => {
  const rows = Model.modeRows("tunnel_only")
  assert.strictEqual(rows.length, 7)
  const tunnelOnly = rows.find(r => r.id === "tunnel_only")
  assert.strictEqual(tunnelOnly.current, true)
  assert.strictEqual(tunnelOnly.tunnel, true)
  assert.strictEqual(tunnelOnly.description, "Tunnel traffic, leave Quad9 / system DNS alone")
})

test("formatBytes and formatLatency stay compact", () => {
  assert.strictEqual(Model.formatBytes(0), "0 B")
  assert.strictEqual(Model.formatBytes(512), "512 B")
  assert.strictEqual(Model.formatBytes(1536), "1.5 KB")
  assert.strictEqual(Model.formatBytes(10485760), "10 MB")
  assert.strictEqual(Model.formatLatency(3.42), "3.4 ms")
  assert.strictEqual(Model.formatLatency(42.1), "42 ms")
})

console.log("\nall desktop WarpModel tests passed\n")
