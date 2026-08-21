const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const modulePath = path.join(__dirname, '..', 'html', 'stacking.js');
assert.equal(fs.existsSync(modulePath), true, 'html/stacking.js must exist');
const stacking = require(modulePath);

const definitions = {
    bandage: { stackable: true, maxStack: 10, size: { w: 1, h: 1 } },
    crate: { stackable: true, maxStack: 5, size: { w: 2, h: 2 } },
    WEAPON_PISTOL: { size: { w: 2, h: 1 } }
};

assert.equal(
    stacking.getItemAtCell([{ name: 'crate', slot: 'c', x: 2, y: 2 }], definitions, 3, 3, null).slot,
    'c',
    'multi-cell items must be detected across their whole footprint'
);

assert.equal(
    stacking.canMerge(
        { name: 'bandage', count: 4, slot: 'a', metadata: {} },
        { name: 'bandage', count: 3, slot: 'b', metadata: {} },
        definitions
    ),
    true,
    'matching bandage stacks below maxStack must merge'
);

assert.equal(
    stacking.canMerge(
        { name: 'bandage', count: 4, slot: 'a', metadata: { quality: 90 } },
        { name: 'bandage', count: 3, slot: 'b', metadata: { quality: 80 } },
        definitions
    ),
    false,
    'different metadata must not merge'
);

assert.equal(
    stacking.canMerge(
        { name: 'bandage', count: 1, slot: 'a', metadata: {} },
        { name: 'bandage', count: 10, slot: 'b', metadata: {} },
        definitions
    ),
    false,
    'a full target stack must reject a merge'
);

assert.equal(
    stacking.canMerge(
        { name: 'WEAPON_PISTOL', count: 1, slot: 'a', metadata: {} },
        { name: 'WEAPON_PISTOL', count: 1, slot: 'b', metadata: {} },
        definitions
    ),
    false,
    'weapons without stackable=true must remain separate'
);

console.log('STACKING_UI_TESTS_PASS cases=5');
