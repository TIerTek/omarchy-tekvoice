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

// Action queue. Picking a voice while disarmed is two commands issued in the
// same tick; the second must wait behind the first, not replace it.
const { enqueue, afterExit, errorText, MAX_QUEUE } = VM;
let q = [];
q = enqueue(q, ['arm']);
q = enqueue(q, ['set', 'quackers']);
assert.deepStrictEqual(q, [['arm'], ['set', 'quackers']], 'arm then set, in order');
assert.deepStrictEqual(enqueue([], ['x']), [['x']]);
const before = [['a']];
enqueue(before, ['b']);
assert.deepStrictEqual(before, [['a']], 'enqueue must not mutate (QML only notices reassignment)');

let full = [];
for (let i = 0; i < MAX_QUEUE + 5; i++) full = enqueue(full, ['next']);
assert.strictEqual(full.length, MAX_QUEUE, 'a spun scroll wheel must not queue unbounded work');

assert.deepStrictEqual(afterExit([['set', 'quackers']], 0), [['set', 'quackers']], 'success carries on');
assert.deepStrictEqual(afterExit([['set', 'quackers']], 1), [], 'failure drops the rest so the real error is not buried');
assert.deepStrictEqual(afterExit([['set', 'quackers']], null), [], 'a command that never started counts as failed');

assert.strictEqual(errorText('tekvoice: not armed - run \'tekvoice arm\' first\n'), 'not armed - run \'tekvoice arm\' first');
assert.strictEqual(errorText('building...\ntekvoice: build failed; see /x/build.log\n\n'), 'build failed; see /x/build.log', 'last line wins');
assert.strictEqual(errorText(''), 'command failed');
assert.strictEqual(errorText(null), 'command failed');
assert.ok(errorText('x'.repeat(1000)).length <= 200, 'bounded, it lands in a tooltip');

console.log('test_model: PASS');
