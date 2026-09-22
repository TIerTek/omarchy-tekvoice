# TekVoice — Design Spec

- **Date:** 2026-09-22
- **Plugin id:** `tiertek.tekvoice`
- **Repo:** `~/Documents/AiProjects/omarchy-tekvoice` (sarial), public at `github.com/TIerTek/omarchy-tekvoice`
- **Status:** approved design, pre-implementation

## 1. Purpose

A fun Omarchy bar plugin that disguises the user's voice in real time on a
**virtual microphone** that every application can select — Zoom, Discord, Meet,
Chrome, OBS. The user picks a voice in a bar widget and the person on the other
end of a live call hears it.

Success means all three of:

1. A source named `TekVoice` appears in any app's microphone list while armed.
2. Switching voices mid-sentence does not interrupt the call.
3. Added latency is low enough that normal conversation is not disrupted.

Usability is a gate, not a preference: latency and mic stability outrank every
voice in the roster.

## 2. Non-goals

- Not a general audio-effects rack. No user-facing DSP graph editor.
- No speech synthesis, no voice cloning, no AI models.
- No bundled third-party character art, names, or samples (see §8).
- Phase 1 does not include the animated HUD; that is phase 2.

## 3. Architecture

The native code is a **LADSPA plugin hosted by PipeWire's own `filter-chain`
module**, not a standalone application. PipeWire performs all virtual-microphone
plumbing through its audited code path; this project writes only DSP.

The decisive property: `filter-chain` exposes a hosted plugin's control ports as
live node properties. Changing a voice is a property write on a running node, so
**the node is never torn down and the microphone never drops mid-call**. A
design that rebuilds the filter graph per voice change cannot offer this.

```
real mic ──▶ filter-chain node "TekVoice" ──▶ virtual source ──▶ Zoom / Discord / Chrome
                      │
              libtekvoice.so  ◀── control ports (pitch, formant, tilt,
                                   grit, ring, noise, mix)
                      ▲
              pw-cli property write ◀── bin/tekvoice ◀── bar widget / hotkey
```

### 3.1 Components

| Unit | What it is | Depends on |
|---|---|---|
| `src/tekvoice.c` → `libtekvoice.so` | LADSPA plugin. One `run()`: Rubber Band live shifter (pitch + formant) → biquad bank → waveshaper → ring mod → noise/gate → dry/wet mix. No allocation after `instantiate()`. | `rubberband` only. `ladspa.h` is public domain and is vendored, so nothing must be installed. |
| `bin/tekvoice` | POSIX shell CLI: `arm`, `disarm`, `set <voice>`, `strength <0-100>`, `panic`, `status`. `arm` loads the filter-chain config; everything else is a live property write via `pw-cli`. | `pipewire` |
| `voices.json` | Data table mapping a voice name to its seven control values. Adding a voice is a JSON edit, no rebuild. | — |
| `BarWidget.qml`, `Panel.qml` | Quickshell bar widget and voice picker. Calls the CLI, reads status. | Omarchy shell |
| `tests/` | Offline DSP harness plus JS model tests. | `gcc` |

Each unit is independently testable: the `.so` through the offline WAV harness,
the CLI through its `status` output against a running graph, the QML model
through a plain JS unit test in the shape of Scratchpad Deck's
`tests/test-slot-model.cjs`.

### 3.2 Build

A plain `Makefile` invoking `gcc` and `pkg-config rubberband`. Deliberately no
meson/ninja: neither is installed on the target machines, and a single shared
object does not justify a build-system dependency.

## 4. The voice roster

Names are original. The pitch-engine column determines the latency each voice
carries.

| Voice | Character | Pitch engine? | Added latency |
|---|---|---|---|
| Chipper | Chipmunk | yes | shifter |
| Quackers | Duck | yes, most extreme formant push | shifter; first to cut |
| Deep Six | Giant / demon | yes | shifter |
| Whisperkill | Horror-movie phone voice | yes | shifter |
| Ascend | Voice shifted feminine-ward, formants preserved | yes | shifter |
| Descend | Voice shifted masculine-ward, formants preserved | yes | shifter |
| Tinhead | Robot | no | ~0 |
| Toaster | Metallic flutter | no | ~0 |
| Handset | CB / walkie-talkie | no | ~0 |

Tinhead, Toaster and Handset bypass Rubber Band entirely — ring modulation,
comb filtering, band-limiting and noise are all sample-by-sample. **These three
remain usable on a call regardless of the phase 0 outcome**, so the plugin is
worth shipping even in the worst case.

### 4.1 Control ports

Seven controls, shared by every voice; a voice is a set of values for them.

| Port | Range | Meaning |
|---|---|---|
| `pitch` | -12..+12 semitones | Rubber Band pitch scale. 0 bypasses the shifter. |
| `formant` | -12..+12 semitones | Formant scale, independent of pitch. 0 with `pitch != 0` means formants preserved. |
| `tilt` | -1..+1 | Spectral tilt / band emphasis through the biquad bank. |
| `grit` | 0..1 | Waveshaper drive. |
| `ring` | 0..200 Hz | Ring-modulator frequency. 0 disables. |
| `noise` | 0..1 | Added static, gated by input level. |
| `mix` | 0..1 | Dry/wet. `panic` sets this to 0. |

`strength` in the CLI scales a voice's `pitch`, `formant`, `grit`, `ring` and
`noise` toward their dry values; it does not alter `mix`.

## 5. Phase 0 — the latency gate (runs first, blocking)

Measure Rubber Band's live block size and start delay on the target machine,
impulse in to first output sample out.

- **≤25 ms** — proceed as designed.
- **25–40 ms** — proceed, and report the measured number so the user can judge
  it against a real call.
- **>40 ms** — **stop and consult the user.** The fallback is a
  granular/overlap-add shifter written in-project, whose latency is chosen
  directly (~10 ms) at the cost of a slight warble. That trade is the user's
  decision, not the implementer's.

The measurement becomes a permanent regression test (§7).

## 6. Controls, UX, and the safety valve

- Bar widget: a microphone glyph. Outline when off; filled and voice-tinted when
  armed.
- Click opens the panel: a grid of voice tiles, a strength slider, an arm toggle.
- Hotkeys via `hypr/tekvoice.lua`: `SUPER+ALT+V` panel, `SUPER+ALT+SHIFT+V`
  cycle voice, `SUPER+ALT+X` panic.
- **Panic sets `mix` to 0. It does not unload the node.** The real voice returns
  within one buffer and the remote application never sees its microphone
  disappear.
- `disarm` refuses while a consumer is attached to `TekVoice`, unless `--force`
  is given, for the same reason.
- `status` reports which application is currently consuming `TekVoice`, so the
  user always knows whether they are live.

## 7. Testing

The DSP is fully testable with no sound card in the loop.

- `tests/selftest` links the same `.so` and runs `in.wav → voice → out.wav`
  offline. Per-voice acoustic assertions: fundamental frequency moved by the
  expected ratio (autocorrelation); spectral centroid moved or held as the voice
  specifies; no NaN; no clipping; deterministic output across runs.
- An impulse test asserting measured latency stays under the phase 0 budget.
- `run()` executed under a malloc interposer, asserting zero allocations in the
  audio path.
- A plain JS unit test for voice-model and `voices.json` parsing.

Development follows TDD: each voice's acoustic signature is asserted before its
DSP is written.

## 8. Naming and licensing constraints

The repository is public. Therefore:

- No Disney, Paramount, or Fun World marks appear in any file, commit message,
  README, or preview — not in a preset name, comment, or test fixture. The
  *sound* of a cartoon duck is not protected; the *name* is.
- No bundled third-party art or audio samples. Preview art is original.
- Runtime dependencies are `pipewire` and `rubberband`, both in Arch `extra`.
  `ladspa.h` is vendored under its public-domain terms.
- Licence: GPL-3.0, matching the sibling TierTek plugins.

## 9. Phasing

- **Phase 0** — latency gate. Blocking.
- **Phase 1** — DSP, voices, CLI, minimal bar widget. Usable and funny.
- **Phase 2** — the animated HUD: live meter, per-voice art, transitions.
- **Phase 3** — public GitHub repo, README, previews.

A marketplace submission issue is explicitly **out of scope** unless separately
requested; the user chose publication without a listing.

## 10. Risks

| Risk | Handling |
|---|---|
| Rubber Band live latency too high for conversation | Phase 0 gate; granular fallback; three zero-latency voices survive regardless. |
| `filter-chain` will not expose control ports as writable properties on this PipeWire build | Verify in phase 0 alongside latency; if unavailable the voice switch costs a node rebuild and the mic-stability promise must be renegotiated with the user. |
| Engine crash kills a live call's microphone | No allocation and no unbounded reads in the audio path; `panic` is a mix change, not an unload; `disarm` refuses while consumers are attached. |
| CPU cost on battery | Measured in phase 1; the three bypass voices are near-free. |
