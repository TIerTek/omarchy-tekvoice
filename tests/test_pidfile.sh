#!/bin/sh
# Offline: the CLI must never act on a pid it did not start, and must never
# fall back to a shared /tmp state directory. No PipeWire needed.
set -e
T=$(mktemp -d)
PIDS=""
trap 'for p in $PIDS; do kill $p 2>/dev/null || true; done; rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
starttime() { python3 -c 'import sys; s=open("/proc/%s/stat" % sys.argv[1]).read(); print(s[s.rindex(")")+2:].split()[19])' "$1"; }
mkdir -p "$T/state" "$T/bin" "$T/py" "$T/site"

sleep 30 & VICTIM=$!; PIDS="$PIDS $VICTIM"
echo "$VICTIM $(starttime $VICTIM)" > "$T/state/pid"
out=$(TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice status)
echo "$out" | grep -q '^armed=no$' || fail "a non-pipewire pid must not count as armed"
TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice disarm --force >/dev/null
kill -0 "$VICTIM" 2>/dev/null || fail "disarm killed a process it did not start"

# A process whose comm IS "pipewire" but is not our filter - the pid-reuse
# case where the user's own PipeWire daemon inherits the number.
cp /usr/bin/sleep "$T/bin/pipewire"
"$T/bin/pipewire" 30 & IMPOSTOR=$!; PIDS="$PIDS $IMPOSTOR"
sleep 0.1
[ "$(cat /proc/$IMPOSTOR/comm)" = pipewire ] || fail "test setup: impostor comm"
echo "$IMPOSTOR $(starttime $IMPOSTOR)" > "$T/state/pid"
TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice status | grep -q '^armed=no$' \
    || fail "a pipewire process with the wrong command line must not count as armed"
TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice disarm --force >/dev/null
kill -0 "$IMPOSTOR" 2>/dev/null || fail "disarm killed an unrelated pipewire process"

# Our filter's exact identity: `pipewire -c filter-chain.conf` with our private
# config dir. A copied python stands in, parked by sitecustomize before -c runs.
cp "$(readlink -f "$(command -v python3)")" "$T/py/pipewire"
echo 'import time; time.sleep(30)' > "$T/site/sitecustomize.py"
(cd "$T" && PYTHONPATH="$T/site" PIPEWIRE_CONFIG_DIR="$T/state/pw" exec "$T/py/pipewire" -c filter-chain.conf) &
OURS=$!; PIDS="$PIDS $OURS"
sleep 0.3
[ "$(cat /proc/$OURS/comm)" = pipewire ] || fail "test setup: stand-in comm"
S=$(starttime $OURS)
echo "$OURS $((S + 1))" > "$T/state/pid"
TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice status | grep -q '^armed=no$' \
    || fail "a stale start time (pid reused) must not count as armed"
TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice disarm --force >/dev/null
kill -0 "$OURS" 2>/dev/null || fail "disarm killed a pid whose start time does not match"
echo "$OURS" > "$T/state/pid"
TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice status | grep -q '^armed=no$' \
    || fail "a pidfile without a start time must not count as armed"
echo "$OURS $S" > "$T/state/pid"
TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice status | grep -q '^armed=yes$' \
    || fail "our own filter process must count as armed"
TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice disarm --force >/dev/null
sleep 0.2
kill -0 "$OURS" 2>/dev/null && fail "disarm did not stop our own filter process"

echo "12abc 1" > "$T/state/pid"
TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice status | grep -q '^armed=no$' || fail "garbage pidfile must read as not armed"

env -u XDG_RUNTIME_DIR -u TEKVOICE_STATE_DIR ./bin/tekvoice status >"$T/out" 2>&1 \
    && fail "status must refuse to run without XDG_RUNTIME_DIR"
grep -q XDG_RUNTIME_DIR "$T/out" || fail "missing-runtime-dir error should name the variable"

echo "test_pidfile: PASS"
