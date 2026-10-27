const assert = require('node:assert/strict');
const model = require('../BarSettingsModel.js');
const migrated = model.migrate({'bar-edge':'left','bar-height':'32','bar-transparent':'1',
    'bar-opacity':'.7','bar-air':'20','bar-type':'notch','bar-template':'desk',
    'bar-templates.json':JSON.stringify({desk:{height:28,opacity:.8,type:'slab'}})});
assert.equal(migrated.settings.edge, 'left');
assert.equal(migrated.settings.height,32);
assert.equal(migrated.settings.transparent,true);
assert.equal(migrated.selectedTemplate,'desk');
assert.equal(migrated.templates.desk.edge,undefined);
assert.deepEqual(model.normalize(migrated),migrated);
assert.deepEqual(model.migrate({}),model.initial());
assert.equal(model.migrate({'bar-height':'bad','bar-opacity':'99'}).settings.height,26);
assert.equal(model.migrate({'bar-opacity':'99'}).settings.opacity,1);
assert.equal(model.normalize({...migrated, selectedTemplate:'missing'}).selectedTemplate,'zen');
for (const input of [null, [], {}, {...migrated,version:2}, {...migrated,templates:[]}])
    assert.throws(()=>model.normalize(input));
assert.deepEqual(model.templates({zen:{},'bad/name':{},valid:null}),{});
assert.equal(model.settings({height:Infinity,rounding:-5,air:999}).rounding,0);
assert.equal(model.settings({air:999}).air,360);
console.log('bar settings model tests passed');
