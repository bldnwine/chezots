const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

// Exercise the real resolver without starting the desktop or scanning apps.
const source = fs.readFileSync(path.join(__dirname, "../Locus.qml"), "utf8");
const functions = source.match(/    function (?:resolveIconUrl|rejectIcon)\(raw\) \{[\s\S]*?\n    \}/g);
assert.strictEqual(functions.length, 2);
let lookups = 0;
const context = {
    root: { _iconCache: {} },
    Quickshell: { iconPath: name => { lookups++; return name === "missing" ? "" : "image://icon/" + name; } }
};
vm.createContext(context);
vm.runInContext(functions.join("\n"), context);

assert.strictEqual(context.resolveIconUrl("missing"), "");
assert.strictEqual(context.resolveIconUrl("missing"), "");
assert.strictEqual(lookups, 1, "missing icons should be resolved only once");
assert.strictEqual(context.resolveIconUrl("app"), "image://icon/app");
assert.strictEqual(context.resolveIconUrl("app"), "image://icon/app");
assert.strictEqual(lookups, 2);
for (const raw of ["/tmp/icon.png", "file:///tmp/icon.png", "image://icon/broken"]) {
    assert.ok(context.resolveIconUrl(raw));
    const before = context.root._iconCache;
    context.rejectIcon(raw);
    assert.notStrictEqual(context.root._iconCache, before, "image errors should notify existing rows");
    assert.strictEqual(context.resolveIconUrl(raw), "", "failed images should use the glyph fallback");
    const rejected = context.root._iconCache;
    context.rejectIcon(raw);
    assert.strictEqual(context.root._iconCache, rejected, "repeated errors should not notify again");
}
context.root._iconCache = {};
assert.strictEqual(context.resolveIconUrl("missing"), "");
assert.strictEqual(lookups, 3, "cache invalidation should allow a retry");
console.log("Locus icon cache tests passed");
