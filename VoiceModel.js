// VoiceModel.js — pure helpers shared by the bar widget and the panel.
//
// No QML, no I/O, no Quickshell types, so the interesting logic can be unit
// tested (tests/test_model.cjs) instead of by opening the panel and squinting
// at it. The same file is loaded by QML and by Node; the export at the bottom
// is guarded for that reason.

// Parses the key=value block printed by `tekvoice status`.
//
// Anything missing gets a safe default: the widget is mounted for the whole
// session and must render sensibly before the first status call returns, and
// before PipeWire is even running.
function parseStatus(text) {
  var out = { armed: false, voice: null, strength: 100, mix: 0, consumers: 0, live: false };
  if (!text) return out;
  var lines = String(text).split("\n");
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    if (!line) continue;
    var eq = line.indexOf("=");
    if (eq < 1) continue;
    var k = line.slice(0, eq), v = line.slice(eq + 1);
    if (k === "armed") out.armed = (v === "yes");
    else if (k === "voice") out.voice = v || null;
    else if (k === "strength") out.strength = clampInt(v, 0, 100, 100);
    else if (k === "mix") out.mix = clampInt(v, 0, 1, 0);
    else if (k === "consumers") out.consumers = clampInt(v, 0, 9999, 0);
  }
  // "live" is the distinction that matters in the bar: armed only means the
  // device exists, whereas live means a disguised voice is actually on air.
  out.live = out.armed && out.mix > 0 && !!out.voice;
  return out;
}

// Whether anything a person would notice differs between two parsed statuses.
// The consumer count is left out: an app opening the mic does not make an
// earlier error about arming any less true.
function stateChanged(a, b) {
  if (!a || !b) return true;
  return a.armed !== b.armed || a.voice !== b.voice ||
         a.mix !== b.mix || a.strength !== b.strength;
}

function clampInt(v, lo, hi, def) {
  var n = parseInt(v, 10);
  if (isNaN(n)) return def;
  return n < lo ? lo : (n > hi ? hi : n);
}

// Next id in the list, wrapping. Falls back to the first entry when the
// current one is null or no longer present.
function cycle(ids, current, dir) {
  if (!ids || ids.length === 0) return null;
  var i = ids.indexOf(current);
  if (i < 0) return ids[0];
  var n = (i + (dir < 0 ? -1 : 1)) % ids.length;
  if (n < 0) n += ids.length;
  return ids[n];
}

function findVoice(voices, id) {
  if (!voices || !id) return null;
  for (var i = 0; i < voices.length; i++) if (voices[i].id === id) return voices[i];
  return null;
}

function tint(voices, id) {
  var v = findVoice(voices, id);
  return v ? v.color : null;
}

function describe(voices, id) {
  var v = findVoice(voices, id);
  return v ? v.name : "No voice";
}

function ids(voices) {
  var out = [];
  if (!voices) return out;
  for (var i = 0; i < voices.length; i++) out.push(voices[i].id);
  return out;
}

// ---------------------------------------------------------------- action queue
//
// The widget runs one CLI command at a time. Quickshell starts a Process on
// the next tick, so `running` is still false straight after it is set: a
// second command issued in the same tick (arm, then set) used to overwrite the
// first instead of waiting behind it. Actions queue instead.

var MAX_QUEUE = 8;

// Returns a new array — QML only notices a property change on reassignment.
// Full queues drop the newcomer: a spun scroll wheel must not queue a minute
// of voice changes.
function enqueue(queue, args) {
  if (queue.length >= MAX_QUEUE) return queue;
  return queue.concat([args]);
}

// After a command finishes. On failure the rest is dropped: every later step
// (a `set` after a failed `arm`) would only fail too and bury the real error.
// A null exit code means the command never started.
function afterExit(queue, exitCode) {
  return exitCode === 0 ? queue : [];
}

// The CLI's last stderr line, without its "tekvoice: " prefix, bounded
// because it lands in a tooltip.
function errorText(stderr) {
  var lines = String(stderr || "").split("\n");
  for (var i = lines.length - 1; i >= 0; i--) {
    var line = lines[i].trim();
    if (!line) continue;
    if (line.indexOf("tekvoice: ") === 0) line = line.slice(10);
    return line.length > 200 ? line.slice(0, 199) + "…" : line;
  }
  return "command failed";
}

if (typeof module !== "undefined") module.exports = {
  MAX_QUEUE: MAX_QUEUE,
  enqueue: enqueue,
  afterExit: afterExit,
  errorText: errorText,
  parseStatus: parseStatus,
  stateChanged: stateChanged,
  cycle: cycle,
  findVoice: findVoice,
  tint: tint,
  describe: describe,
  ids: ids
};
