#!/usr/bin/env bash
# TekVoice installer. Everything lands under $HOME; this never needs sudo.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="tiertek.tekvoice"
PLUGIN_DIR="${TEKVOICE_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/$PLUGIN_ID}"
LADSPA_DIR="${TEKVOICE_LADSPA_DIR:-$HOME/.ladspa}"
SO="$LADSPA_DIR/libtekvoice.so"
# sha256 of the engine this script last installed. It is the proof that the
# file at $SO is ours: anything else there is left alone.
RECORD="$LADSPA_DIR/.libtekvoice.so.tekvoice"

die() { printf 'install: %s\n' "$1" >&2; exit 1; }

command -v pipewire >/dev/null 2>&1 || die "pipewire not found — install it with: sudo pacman -S pipewire"
command -v pw-cli   >/dev/null 2>&1 || die "pw-cli not found — install it with: sudo pacman -S pipewire"
command -v python3  >/dev/null 2>&1 || die "python3 not found — install it with: sudo pacman -S python"
pkg-config --exists rubberband 2>/dev/null \
  || die "librubberband development files not found — install them with: sudo pacman -S rubberband"
[ -f /usr/share/pipewire/filter-chain.conf ] \
  || die "/usr/share/pipewire/filter-chain.conf is missing — is pipewire fully installed?"

echo "building..."
make -C "$HERE" >/dev/null

sha() { sha256sum "$1" | cut -d' ' -f1; }
NEW="$HERE/build/libtekvoice.so"

is_tekvoice_dir() {
  [ -f "$1/manifest.json" ] && python3 - "$1/manifest.json" <<'PYEOF' 2>/dev/null
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("id") == "tiertek.tekvoice" else 1)
PYEOF
}

# Check everything before writing anything, so a refusal leaves no half-install.
# The engine: only one this script installed (its hash is in $RECORD) or one
# byte-identical to the new build. A symlink or any other file is not ours.
for f in "$SO" "$RECORD"; do
  if [ -L "$f" ]; then
    die "$f is a symlink TekVoice did not create; remove it yourself if it is safe to replace"
  elif [ -e "$f" ] && [ ! -f "$f" ]; then
    die "$f exists and is not a regular file; leaving it alone"
  fi
done
if [ -e "$SO" ]; then
  cur="$(sha "$SO")"
  if [ "$cur" != "$(sha "$NEW")" ] \
     && { [ ! -f "$RECORD" ] || [ "$cur" != "$(cat "$RECORD")" ]; }; then
    die "$SO was not installed by this script (or was modified since); remove it yourself if it is safe to replace"
  fi
fi
# The plugin link: only one that already points at a TekVoice checkout.
if [ -L "$PLUGIN_DIR" ]; then
  is_tekvoice_dir "$PLUGIN_DIR" \
    || die "$PLUGIN_DIR is a symlink to something other than TekVoice ($(readlink "$PLUGIN_DIR")); remove it yourself if it is safe to replace"
elif [ -e "$PLUGIN_DIR" ]; then
  die "$PLUGIN_DIR exists and is not a symlink; move it aside first"
fi

# Write to fresh temp files and rename over, so nothing is written through a link.
mkdir -p "$LADSPA_DIR"
tmp="$(mktemp "$LADSPA_DIR/.libtekvoice.XXXXXX")"
install -m 0644 "$NEW" "$tmp" && mv -f "$tmp" "$SO"
tmp="$(mktemp "$LADSPA_DIR/.libtekvoice.XXXXXX")"
sha "$SO" > "$tmp" && mv -f "$tmp" "$RECORD"
echo "installed $SO"

mkdir -p "$(dirname "$PLUGIN_DIR")"
ln -sfn "$HERE" "$PLUGIN_DIR"
echo "linked $PLUGIN_DIR -> $HERE"

cat <<'NOTE'

Done. Next:

  1. Add the TekVoice widget to your bar (Omarchy bar settings), then:
       omarchy restart shell
  2. Add the hotkeys: append hypr/tekvoice.lua to ~/.config/hypr/bindings.lua
       omarchy restart hyprland
  3. Try it from the terminal:
       bin/tekvoice arm
       bin/tekvoice set quackers
       bin/tekvoice panic
       bin/tekvoice disarm

Then pick "TekVoice" as your microphone in Zoom, Discord, Meet or OBS.

  Super+Alt+V        open the panel
  Super+Alt+Shift+V  next voice
  Super+Alt+X        panic — your real voice, immediately
NOTE
