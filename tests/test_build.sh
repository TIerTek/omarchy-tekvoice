#!/bin/sh
# Offline test of the first-run build: `omarchy plugin add` only runs
# `git clone`, so a marketplace install has sources and no libtekvoice.so.
# The CLI must build it itself, and say plainly what is missing when it cannot.
# No PipeWire needed; nothing is written outside a temp directory.
set -e
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

# A clean checkout: tracked files only, exactly what git clone delivers.
git ls-files -z | xargs -0 tar -cf - | tar -xf - -C "$T"
mkdir -p "$T/empty-ladspa" "$T/state"
TEKVOICE_LADSPA_DIR="$T/empty-ladspa"; export TEKVOICE_LADSPA_DIR
TEKVOICE_STATE_DIR="$T/state"; export TEKVOICE_STATE_DIR
unset TEKVOICE_SO

[ ! -e "$T/build/libtekvoice.so" ] || fail "fixture already has a built engine"

MAKE=tv-no-such-make "$T/bin/tekvoice" build >"$T/out" 2>&1 && fail "build should fail without make"
grep -q "pacman -S" "$T/out" || fail "missing-tool error should say what to install: $(cat "$T/out")"

"$T/bin/tekvoice" build >"$T/out" 2>&1 || fail "build failed: $(cat "$T/out")"
[ -f "$T/build/libtekvoice.so" ] || fail "build did not produce build/libtekvoice.so"
grep -q "$T/build/libtekvoice.so" "$T/out" || fail "build should print the engine path"

# Second run is a no-op, not a rebuild.
before=$(stat -c %Y "$T/build/libtekvoice.so")
"$T/bin/tekvoice" build >/dev/null 2>&1 || fail "second build failed"
[ "$(stat -c %Y "$T/build/libtekvoice.so")" = "$before" ] || fail "second build rebuilt needlessly"

echo "test_build: PASS"
