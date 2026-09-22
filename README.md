# TekVoice

A live voice changer for [Omarchy](https://omarchy.org) that presents a **virtual
microphone** every application can select. Pick a voice in the bar and the person
on the other end of your call hears it — Zoom, Discord, Meet, OBS, Chrome.

Switching voices does not interrupt the call, and a panic key brings your real
voice back immediately.

## The voices

| Voice | Sounds like | Added latency |
|---|---|---|
| **Chipper** | Small, fast and far too pleased with itself | ~55 ms |
| **Quackers** | Squashed, nasal and permanently outraged | ~55 ms |
| **Deep Six** | Something enormous, speaking from the bottom of a well | ~55 ms |
| **Whisperkill** | A gravelly stranger on a bad phone line | ~55 ms |
| **Ascend** | Your voice lifted, formants held — a different person, not a cartoon | ~55 ms |
| **Descend** | Your voice lowered, formants held | ~55 ms |
| **Tinhead** | Clipped, metallic, without warmth | ~0 ms |
| **Toaster** | Harsher machine flutter | ~0 ms |
| **Handset** | Squeezed through a cheap radio, static and all | ~0 ms |

Voices live in `voices.json` as plain numbers. Adding one is a JSON edit — no rebuild.

## Latency, stated plainly

The six pitch-shifting voices add **about 55 ms**, measured on the development
machine as the impulse-response energy peak. You never hear it: TekVoice has no
local monitoring, so the delay lands only as extra one-way delay for the person
you are talking to, on top of the ~120 ms a call already has. The three voices
that do not shift pitch add essentially nothing.

## Install

Requires `pipewire` and `rubberband`, both in Arch `extra`. Nothing else —
`ladspa.h` is vendored, and the build uses plain `make`.

```sh
git clone https://github.com/TIerTek/omarchy-tekvoice
cd omarchy-tekvoice
./install.sh
```

`install.sh` never uses `sudo`; everything is installed under `$HOME`.

Then add the TekVoice widget to your bar, `omarchy restart shell`, and append
`hypr/tekvoice.lua` to `~/.config/hypr/bindings.lua`.

## Use

Click the microphone glyph in the bar, or:

```sh
tekvoice arm                # adds the "TekVoice" microphone
tekvoice set quackers       # switch voice, live, without dropping the mic
tekvoice next               # cycle
tekvoice strength 60        # pull the effect back toward your real voice
tekvoice panic              # real voice, immediately
tekvoice disarm             # remove the microphone
```

| Hotkey | Action |
|---|---|
| `Super+Alt+V` | Open the panel |
| `Super+Alt+Shift+V` | Next voice |
| `Super+Alt+X` | **Panic** — your real voice, immediately |

Middle-clicking the bar glyph is also panic.

Cycling and panic talk to PipeWire directly rather than through the shell, so
they keep working when the bar widget is disabled or the shell is restarting —
which is exactly when you are most likely to be reaching for panic.

## How it works

TekVoice is a LADSPA plugin hosted by PipeWire's own `filter-chain` module.
PipeWire does all the virtual-device plumbing; this project is only DSP.

That choice buys the property that matters: `filter-chain` exposes a hosted
plugin's control ports as live node properties, so changing voice is a single
property write on a running node. The node is never rebuilt, so **the microphone
never disappears mid-call** — verified in `tests/test_cli.sh`, which asserts the
source index is unchanged across a voice switch, a cycle and a panic.

Pitch and formants are handled by Rubber Band's live shifter, which is why
Ascend and Descend read as a different person rather than a chipmunk: the
formants are held while the pitch moves.

**Panic** sets the wet mix to zero rather than unloading anything. Your real
voice returns within a buffer and the remote application never sees its
microphone go away.

## Known issue: PipeWire and `Audio/Source/Virtual`

Setting `media.class = Audio/Source/Virtual` on a filter-chain **segfaults
PipeWire 1.6.8**, reliably, inside `libspa-audioconvert`. TekVoice uses
`media.class = Audio/Source`, which works. If you adapt this config, keep that
in mind.

## Development

```sh
make test       # DSP, shifter and plugin suites — no sound card needed
make test-cli   # live test against a running PipeWire
```

The DSP is tested offline: pitch ratios are asserted with a DFT peak estimator,
latency is a regression test, and the output is checked for NaN, clipping,
determinism and block-size invariance.

## Licence

GPL-3.0-or-later. `src/ladspa.h` is vendored public-domain.
