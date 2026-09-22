const fs = require('fs');
const assert = require('assert');

const RANGES = { pitch:[-12,12], formant:[-12,12], band:[0,1], tilt:[-1,1],
                 grit:[0,1], ring:[0,200], noise:[0,1] };
const BANNED = /disney|donald|duck|ghostface|scream|paramount|fun\s*world|mickey|chipmunk|dalek|cylon/i;

const doc = JSON.parse(fs.readFileSync(`${__dirname}/../voices.json`, 'utf8'));
assert.strictEqual(doc.version, 1, 'version must be 1');
assert.strictEqual(doc.voices.length, 9, 'expected nine voices');

const ids = new Set();
for (const v of doc.voices) {
  assert.ok(/^[a-z0-9]+$/.test(v.id), `bad id: ${v.id}`);
  assert.ok(!ids.has(v.id), `duplicate id: ${v.id}`);
  ids.add(v.id);
  assert.ok(v.name && v.blurb && v.icon && v.color, `${v.id} missing display fields`);
  assert.ok(/^#[0-9a-fA-F]{6}$/.test(v.color), `${v.id} colour must be #rrggbb`);
  assert.ok(!('mix' in v), `${v.id} must not define mix`);
  for (const [k, [lo, hi]] of Object.entries(RANGES)) {
    assert.ok(typeof v[k] === 'number', `${v.id}.${k} missing`);
    assert.ok(v[k] >= lo && v[k] <= hi, `${v.id}.${k}=${v[k]} out of [${lo},${hi}]`);
  }
  const text = `${v.id} ${v.name} ${v.blurb}`;
  assert.ok(!BANNED.test(text), `${v.id} contains a third-party mark: ${text}`);
}

const zero = doc.voices.filter(v => v.pitch === 0 && v.formant === 0).map(v => v.id);
assert.deepStrictEqual(zero.sort(), ['handset', 'tinhead', 'toaster'],
  'exactly the three bypass voices must have no pitch shift');

console.log(`test_voices: PASS (${doc.voices.length} voices)`);
