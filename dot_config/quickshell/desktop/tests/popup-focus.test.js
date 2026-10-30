const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const stack = vm.createContext({});
vm.runInContext(fs.readFileSync(require.resolve('../PopupFocusStack.js'), 'utf8')
    .replace(/^\.pragma library\s*/, ''), stack);

const audio = { ownsInput: false };
const locus = { ownsInput: false };
const wallpapers = { ownsInput: false };

stack.show(audio);
assert.equal(audio.ownsInput, true);
stack.show(locus);
assert.equal(audio.ownsInput, false);
assert.equal(locus.ownsInput, true);
// Duplicate map notifications must preserve the current top popup.
stack.show(audio);
assert.equal(locus.ownsInput, true);
stack.hide(locus);
assert.equal(audio.ownsInput, true);
assert.equal(locus.ownsInput, false);

stack.show(wallpapers);
stack.hide(audio);
assert.equal(wallpapers.ownsInput, true);
stack.setBlocked(true);
assert.equal(wallpapers.ownsInput, false);
// A popup opened during authentication cannot take keyboard ownership.
stack.show(locus);
assert.equal(locus.ownsInput, false);
stack.hide(wallpapers);
stack.setBlocked(false);
assert.equal(locus.ownsInput, true);
stack.hide(locus);
stack.hide(locus);
assert.equal(locus.ownsInput, false);
assert.equal(stack.owners.length, 0);

console.log('popup focus ownership tests passed');
