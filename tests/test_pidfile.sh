#!/bin/sh
# Offline: the CLI must never act on a pid it did not start, and must never
# fall back to a shared /tmp state directory. No PipeWire needed.
set -e
T=$(mktemp -d)
sleep 30 & VICTIM=$!
trap 'kill $VICTIM 2>/dev/null || true; rm -rf "$T"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

mkdir -p "$T/state"
echo "$VICTIM" > "$T/state/pid"
out=$(TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice status)
echo "$out" | grep -q '^armed=no$' || fail "a non-pipewire pid must not count as armed"
TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice disarm --force >/dev/null
kill -0 "$VICTIM" 2>/dev/null || fail "disarm killed a process it did not start"

echo "12abc" > "$T/state/pid"
TEKVOICE_STATE_DIR="$T/state" ./bin/tekvoice status | grep -q '^armed=no$' || fail "garbage pidfile must read as not armed"

env -u XDG_RUNTIME_DIR -u TEKVOICE_STATE_DIR ./bin/tekvoice status >"$T/out" 2>&1 \
    && fail "status must refuse to run without XDG_RUNTIME_DIR"
grep -q XDG_RUNTIME_DIR "$T/out" || fail "missing-runtime-dir error should name the variable"

echo "test_pidfile: PASS"
