#!/bin/sh
# Live-session CLI test. Needs a running PipeWire.
set -e
T=$(mktemp -d)
TEKVOICE_STATE_DIR="$T/state"; export TEKVOICE_STATE_DIR
TEKVOICE_SO="$PWD/build/libtekvoice.so"; export TEKVOICE_SO
trap './bin/tekvoice disarm --force >/dev/null 2>&1 || true; rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

./bin/tekvoice status | grep -q '^armed=no$' || fail "status before arm should report armed=no"
./bin/tekvoice set quackers >/dev/null 2>&1 && fail "set should fail while disarmed"
./bin/tekvoice arm || fail "arm failed"
./bin/tekvoice set nosuchvoice >/dev/null 2>&1 && fail "unknown voice should fail"
./bin/tekvoice status | grep -q '^armed=yes$' || fail "status should report armed=yes"
pactl list short sources | grep -q tekvoice_src || fail "TekVoice source not present"

./bin/tekvoice set quackers || fail "set quackers failed"
./bin/tekvoice status | grep -q '^voice=quackers$' || fail "voice not recorded"

BEFORE=$(pactl list short sources | grep tekvoice_src | cut -f1)
./bin/tekvoice set deepsix || fail "set deepsix failed"
AFTER=$(pactl list short sources | grep tekvoice_src | cut -f1)
[ "$BEFORE" = "$AFTER" ] || fail "source index changed on voice switch - the mic dropped"
./bin/tekvoice status | grep -q '^voice=deepsix$' || fail "voice did not change"

./bin/tekvoice strength 50 || fail "strength failed"
./bin/tekvoice status | grep -q '^strength=50$' || fail "strength not recorded"

./bin/tekvoice panic || fail "panic failed"
./bin/tekvoice status | grep -q '^mix=0' || fail "panic should zero mix"
AFTER2=$(pactl list short sources | grep tekvoice_src | cut -f1)
[ "$BEFORE" = "$AFTER2" ] || fail "source index changed on panic - the mic dropped"

./bin/tekvoice disarm || fail "disarm failed"
./bin/tekvoice status | grep -q '^armed=no$' || fail "status after disarm should report armed=no"
echo "test_cli: PASS"
