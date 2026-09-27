#!/bin/sh
# Offline test of install.sh's ownership checks: it may only replace an engine
# it installed itself (hash in the record file) or a link that already points at
# a TekVoice checkout, and a refusal must leave nothing half-installed.
# Nothing is written outside a temp directory; $HOME is never faked.
set -e
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

git ls-files -z | xargs -0 tar -cf - | tar -xf - -C "$T"
mkdir -p "$T/other"
L="$T/ladspa"; P="$T/plugins/tiertek.tekvoice"
TEKVOICE_LADSPA_DIR="$L"; export TEKVOICE_LADSPA_DIR
TEKVOICE_PLUGIN_DIR="$P"; export TEKVOICE_PLUGIN_DIR
SO="$L/libtekvoice.so"; REC="$L/.libtekvoice.so.tekvoice"
inst() { bash "$T/install.sh" >"$T/out" 2>&1; }
reset() { rm -rf "$L" "$T/plugins"; }

inst || fail "fresh install failed: $(cat "$T/out")"
cmp -s "$SO" "$T/build/libtekvoice.so" || fail "engine not installed"
[ "$(cat "$REC")" = "$(sha256sum "$SO" | cut -d' ' -f1)" ] || fail "record does not hold the engine hash"
[ "$(readlink "$P")" = "$T" ] || fail "plugin link not created"
inst || fail "re-running over its own install failed: $(cat "$T/out")"
[ -z "$(find "$L" -name '.libtekvoice.??????')" ] || fail "temp files left behind"

# An older engine this script installed (hash on record) is upgraded.
echo old-engine > "$SO"; sha256sum "$SO" | cut -d' ' -f1 > "$REC"
inst || fail "upgrading a recorded engine failed: $(cat "$T/out")"
cmp -s "$SO" "$T/build/libtekvoice.so" || fail "recorded engine not upgraded"

# A foreign file at the engine path is refused, and the link is not touched either.
reset; mkdir -p "$L"; echo users-own > "$SO"
inst && fail "overwrote a foreign libtekvoice.so"
[ "$(cat "$SO")" = users-own ] || fail "foreign engine modified"
[ ! -e "$P" ] && [ ! -L "$P" ] || fail "refusal still created the plugin link"

# Modified since install: the hash no longer matches the record.
reset; inst; echo tampered >> "$SO"
inst && fail "overwrote an engine modified since install"
grep -q tampered "$SO" || fail "modified engine replaced"

# Symlinks at the engine or record path are refused; their targets are untouched.
reset; mkdir -p "$L"; echo target > "$T/other/lib"; ln -s "$T/other/lib" "$SO"
inst && fail "replaced a symlinked engine"
[ "$(cat "$T/other/lib")" = target ] && [ -L "$SO" ] || fail "symlinked engine or its target modified"
reset; mkdir -p "$L"; echo target > "$T/other/rec"; ln -s "$T/other/rec" "$REC"
inst && fail "wrote through a symlinked record"
[ "$(cat "$T/other/rec")" = target ] || fail "record symlink target modified"
[ ! -e "$SO" ] || fail "refusal still installed the engine"

# A plugin link pointing somewhere else is refused, before the engine is written.
reset; mkdir -p "$T/plugins"; ln -s "$T/other" "$P"
inst && fail "replaced a link to a non-TekVoice directory"
[ "$(readlink "$P")" = "$T/other" ] || fail "foreign plugin link changed"
[ ! -e "$SO" ] || fail "refusal still installed the engine"
rm "$P"; ln -s "$T/missing" "$P"
inst && fail "replaced a dangling plugin link"

# A link to another TekVoice checkout is ours to move.
reset; mkdir -p "$T/plugins" "$T/elsewhere"; cp "$T/manifest.json" "$T/elsewhere/"
ln -s "$T/elsewhere" "$P"
inst || fail "moving a link from another TekVoice checkout failed: $(cat "$T/out")"
[ "$(readlink "$P")" = "$T" ] || fail "TekVoice link not moved"

# A real directory is never replaced.
reset; mkdir -p "$P"
inst && fail "replaced a real plugin directory"
[ -d "$P" ] && [ ! -L "$P" ] || fail "real plugin directory changed"

echo "test_install: PASS"
