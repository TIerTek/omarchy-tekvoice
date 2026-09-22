#!/usr/bin/env bash
# TekVoice installer. Everything lands under $HOME; this never needs sudo.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="tiertek.tekvoice"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
LADSPA_DIR="$HOME/.ladspa"

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

mkdir -p "$LADSPA_DIR"
install -m 0644 "$HERE/build/libtekvoice.so" "$LADSPA_DIR/libtekvoice.so"
echo "installed $LADSPA_DIR/libtekvoice.so"

mkdir -p "$(dirname "$PLUGIN_DIR")"
if [ -e "$PLUGIN_DIR" ] && [ ! -L "$PLUGIN_DIR" ]; then
  die "$PLUGIN_DIR exists and is not a symlink; move it aside first"
fi
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
