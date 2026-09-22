const assert = require('assert');
const VM = require('../VoiceModel.js');
const { parseStatus, cycle, tint, describe } = VM;

const s = parseStatus('armed=yes\nconsumers=2\nvoice=quackers\nstrength=80\nmix=1\n');
assert.strictEqual(s.armed, true);
assert.strictEqual(s.voice, 'quackers');
assert.strictEqual(s.strength, 80);
assert.strictEqual(s.consumers, 2);
assert.strictEqual(s.mix, 1);
assert.strictEqual(s.live, true, 'armed + mix=1 means a voice is actually on air');

const panicked = parseStatus('armed=yes\nconsumers=1\nvoice=quackers\nstrength=80\nmix=0\n');
assert.strictEqual(panicked.live, false, 'mix=0 means the real voice is passing through');

const d = parseStatus('armed=no\n');
assert.strictEqual(d.armed, false);
assert.strictEqual(d.voice, null);
assert.strictEqual(d.strength, 100);
assert.strictEqual(d.consumers, 0);
assert.strictEqual(d.live, false);

assert.strictEqual(parseStatus('').armed, false, 'empty status must not throw');
assert.strictEqual(parseStatus(null).armed, false, 'null status must not throw');

const ids = ['chipper', 'quackers', 'deepsix'];
assert.strictEqual(cycle(ids, 'chipper', 1), 'quackers');
assert.strictEqual(cycle(ids, 'deepsix', 1), 'chipper');
assert.strictEqual(cycle(ids, 'chipper', -1), 'deepsix');
assert.strictEqual(cycle(ids, null, 1), 'chipper');
assert.strictEqual(cycle(ids, 'gone', 1), 'chipper', 'unknown current falls back to the first');
assert.strictEqual(cycle([], null, 1), null);

const voices = [{ id: 'quackers', name: 'Quackers', color: '#f28f3b', blurb: 'Squashed.' }];
assert.strictEqual(tint(voices, 'quackers'), '#f28f3b');
assert.strictEqual(tint(voices, 'nope'), null);
assert.strictEqual(tint([], null), null);
assert.strictEqual(describe(voices, 'quackers'), 'Quackers');
assert.strictEqual(describe(voices, null), 'No voice');

console.log('test_model: PASS');
