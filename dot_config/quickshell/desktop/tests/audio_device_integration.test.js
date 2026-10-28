// A failed optimistic device switch must reconcile its visible rows.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../Navbar.qml'), 'utf8');
for (const kind of ['Sink', 'Source']) {
    const plural = kind + 's';
    const root = {
        audioSinks: [], audioSources: [], audioDefaultSink: 'old', audioDefaultSource: 'old',
        _audioSinksSer: '', _audioSourcesSer: '', _lastSinkChangeTime: 0,
    };
    const rows = [
        {id: 'old', name: 'Old', port: '', portLabel: '', isDefault: true, isActive: true},
        {id: 'new', name: 'New', port: '', portLabel: '', isDefault: false, isActive: false},
    ];
    root['audio' + plural] = rows;
    root['_audio' + plural + 'Ser'] = JSON.stringify(rows);
    const context = vm.createContext({root, audioDeviceService: {selectDevice() {}}});
    const method = source.match(new RegExp('^    function setDefault' + kind + '\\([^]*?^    }', 'm'))[0];
    vm.runInContext(method, context);
    context['setDefault' + kind]('new', '');
    assert(root['audio' + plural].find(r => r.id === 'new').isActive);
    root._lastSinkChangeTime = 0; // final queue completion triggers reconciliation
    const probe = source.slice(source.indexOf('id: audio' + plural + 'Probe'));
    const parser = probe.match(/onStreamFinished: \{([^]*?)^            }/m)[1];
    const snapshot = JSON.stringify([{name: 'old', description: 'Old', ports: []}, {name: 'new', description: 'New', ports: []}])
        + '\n__DEFAULT__old\n__HPJACK__off\n';
    const parse = vm.runInContext('(function() {' + parser + '})', context);
    parse.call({text: snapshot});
    assert.equal(root['audioDefault' + kind], 'old');
    assert.equal(root['audio' + plural].find(r => r.id === 'old').isActive, true, kind + ' retained failed highlight');
    assert.equal(root['audio' + plural].find(r => r.id === 'new').isActive, false, kind + ' retained failed highlight');
}
console.log('audio device reconciliation tests passed');
