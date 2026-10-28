// Exercise Navbar's real integration functions with an isolated compositor/worker.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../Navbar.qml'), 'utf8');
function functionSource(name) {
    const line = source.match(new RegExp('^    function ' + name + '\\(.*$', 'm'));
    if (line && /}\s*$/.test(line[0])) return line[0];
    const match = source.match(new RegExp('^    function ' + name + '\\([^]*?^    }', 'm'));
    assert(match, 'missing integration function ' + name);
    return match[0];
}
function fixture(outputs = ['eDP-1']) {
    const calls = [];
    const monitors = outputs.map(name => ({name, width: 1920, height: 1080, scale: 1, lastIpcObject: {refreshRate: 60}}));
    const root = {
        _displayRestored: false, _displayTouched: false, _brightnessTouched: {}, _brightnessRestoreQueued: {},
        _pendingBrightnessRestore: {}, _knownBrightnessOutputs: [], _displayBaselinePending: false,
        brightnessByOutput: {}, brightnessErrors: {}, nightlightPreviousByOutput: {}, nightlightOutput: '',
        displayVisible: false, displayOutput: '', displayAnchorItem: null, brightnessPct: 100,
        warmthK: 6500, gammaPct: 100, selectedPreset: 0, displayPresets: [1, 2, 3, 4],
        displayStatePath: '/temporary/display-state.json', ensureSunset: '', sunsetReady: false,
        runCommand(...args) { calls.push(['command', ...args]); },
        anchorPopupTo() {},
    };
    const brightnessService = {
        stateByOutput: {}, rememberedByOutput: {},
        setBrightness(...args) { calls.push(['set', ...args]); },
        stepBrightness(...args) { calls.push(['step', ...args]); },
        refresh(...args) { calls.push(['refresh', ...args]); },
        cancelOutput(...args) { calls.push(['cancel', ...args]); },
    };
    const context = vm.createContext({root, brightnessService, Hyprland: {focusedMonitor: monitors[0], monitors: {values: monitors}},
        displaySaveTimer: {restart() { calls.push(['save']); }}, displayStateQueue: {enqueue(...args) { calls.push(['persist', ...args]); }},
        Quickshell: {shellDir: '/staging'}, osdSurface: {show(...args) { calls.push(['osd', ...args]); }}});
    for (const name of ['focusedBrightnessOutput', 'syncBrightnessOutputs', 'touchBrightness', 'refreshDisplayMonitor',
        'restoreDisplayState', 'writeDisplayState', 'saveDisplayState', 'openDisplay', 'setBrightness', 'nudgeBrightness', 'applyPreset', 'resetDisplay']) {
        vm.runInContext(functionSource(name), context);
        root[name] = context[name];
    }
    const available = source.match(/readonly property bool brightnessAvailable: ([^]*?)\n    readonly property string brightnessError/)[1];
    Object.defineProperty(root, 'brightnessAvailable', {get() { return vm.runInContext(available, context); }});
    const handler = source.match(/onBrightnessChanged: function\(output, percentage\) \{([^]*?)^        }/m)[1];
    vm.runInContext('function receive(output, percentage) {' + handler + '}', context);
    function receive(kind, output, percentage) {
        context.current = {kind};
        brightnessService.stateByOutput[output] = percentage;
        context.receive(output, percentage);
    }
    return {root, calls, context, receive, brightnessService};
}
{
    const {root, calls} = fixture();
    root.syncBrightnessOutputs();
    assert.equal(calls.length, 0, 'startup probes raced saved state');
    root.nudgeBrightness(5);
    root.restoreDisplayState(JSON.stringify({bright: 80}));
    assert(!calls.some(c => c[0] === 'set'), 'startup restore overwrote newer key input');
}
{
    const first = fixture([]);
    first.root.restoreDisplayState(JSON.stringify({bright: 35}));
    first.root.writeDisplayState();
    const stored = JSON.parse(first.calls.find(c => c[0] === 'persist')[1][3]);
    const second = fixture();
    second.root.restoreDisplayState(JSON.stringify(stored));
    assert(second.calls.some(c => c[0] === 'set' && c[1] === 'eDP-1' && c[2] === 35), 'legacy value lost across disconnected startup');
}
{
    const {root, context, calls, receive} = fixture();
    root.restoreDisplayState(JSON.stringify({brightnessByOutput: {'eDP-1': 40}}));
    root.syncBrightnessOutputs();
    assert.equal(calls.filter(c => c[0] === 'set').length, 1, 'restore enqueued twice');
    context.Hyprland.monitors.values = [];
    root.syncBrightnessOutputs();
    assert(calls.some(c => c[0] === 'cancel'));
    assert.equal(root._pendingBrightnessRestore['eDP-1'], 40, 'unplug discarded pending restore');
    context.Hyprland.monitors.values = [{name: 'eDP-1'}];
    root.syncBrightnessOutputs();
    assert.equal(calls.filter(c => c[0] === 'set').length, 2, 'replug did not retry');
    receive('set', 'eDP-1', 40);
    assert.equal(root._pendingBrightnessRestore['eDP-1'], undefined, 'confirmed restore stayed pending');
}
{
    const {root, context, calls, receive} = fixture();
    root._displayRestored = true;
    root.syncBrightnessOutputs();
    root.openDisplay();
    const before = calls.length;
    root.applyPreset({warmth: 3000, gamma: 85, bright: 30});
    root.resetDisplay();
    assert.equal(calls.length, before, 'preset/reset raced baseline');
    receive('refresh', 'eDP-1', 42);
    context.Hyprland.focusedMonitor = {name: 'HDMI-A-1'};
    root.setBrightness(55);
    assert.equal(calls.at(-1)[1], 'eDP-1', 'popup followed changed focus');
    root.resetDisplay();
    assert(calls.some(c => c[0] === 'set' && c[1] === 'eDP-1' && c[2] === 42), 'reset did not use measured baseline');
}
assert(!/brightnessctl|ddcutil/.test(source), 'Navbar bypasses persistent brightness owner');
console.log('brightness integration tests passed');
