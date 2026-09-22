# TekVoice Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A LADSPA voice-changer plugin, hosted by PipeWire's `filter-chain`, that presents a `TekVoice` microphone to every application and switches between nine character voices live without the microphone ever dropping.

**Architecture:** One C++ shared object exporting the LADSPA ABI. PipeWire's own `filter-chain` module hosts it and does all virtual-device plumbing; the project writes only DSP. A voice is a row of control-port values in `voices.json`, applied by writing node properties on the running capture node, so switching never rebuilds the graph. Rubber Band's live shifter handles pitch and formants; everything else is hand-written per-sample DSP.

**Tech Stack:** C++17, `librubberband` 4.0, vendored public-domain `ladspa.h`, plain GNU Make, PipeWire 1.6.8 `filter-chain`, POSIX shell CLI, Quickshell QML for the bar widget.

**Spec:** `docs/superpowers/specs/2026-09-22-tekvoice-design.md`

## Global Constraints

- Public repository. **No Disney, Paramount, or Fun World marks** in any file, commit message, README, preview, comment, or test fixture. Voice names are original.
- Runtime dependencies are exactly `pipewire` and `rubberband`, both in Arch `extra`. `ladspa.h` is vendored under its public-domain terms. No meson, no ninja, no LV2, no EasyEffects.
- **`media.class` MUST be `Audio/Source`.** `Audio/Source/Virtual` segfaults PipeWire 1.6.8 (spec §11.4).
- Control ports are exposed by `filter-chain` on the **capture** node (`tekvoice_in`), never the source node (spec §11.3).
- **No allocation, no locks, no I/O, no logging in `run()`.** All buffers are sized in `instantiate()`.
- Licence GPL-3.0, matching sibling TierTek plugins.
- Target sample rate 48000 Hz; the plugin must not assume a fixed `run()` block size.
- Commits use `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

---

## File Structure

| Path | Responsibility |
|---|---|
| `Makefile` | Builds `build/libtekvoice.so` and the test binaries. Nothing else. |
| `src/ladspa.h` | Vendored public-domain LADSPA ABI header. Never edited. |
| `src/dsp.h` | Pure per-sample DSP primitives: biquad, band, tilt, waveshaper, ring mod, noise gate. Header-only, no dependencies, trivially testable. |
| `src/shifter.h` | `Shifter` class: Rubber Band live shifter plus the FIFO that adapts PipeWire's variable block size to Rubber Band's fixed 512. |
| `src/tekvoice.cpp` | LADSPA descriptor, port wiring, and the `run()` chain that assembles `dsp.h` and `shifter.h`. |
| `voices.json` | The nine voices as control-port values. Data, not code. |
| `bin/tekvoice` | POSIX shell CLI: `arm`, `disarm`, `set`, `strength`, `panic`, `status`. |
| `pipewire/tekvoice.conf.in` | filter-chain fragment template; `@SO@` is substituted at arm time. |
| `manifest.json`, `BarWidget.qml`, `Panel.qml`, `VoiceModel.js`, `hypr/tekvoice.lua` | The Omarchy plugin surface. |
| `tests/test_dsp.cpp` | Unit tests for `dsp.h` primitives. |
| `tests/test_plugin.cpp` | Loads the built `.so` through `dlopen` and asserts plugin-level behaviour: passthrough, pitch ratio, latency, determinism, NaN/clip safety. |
| `tests/test_voices.cjs` | Validates `voices.json` against the port table. |
| `install.sh` | Builds, installs the `.so` to `~/.ladspa`, links the plugin into Omarchy. |

### Control ports (authoritative — all tasks use these indices)

| # | Name | Range | Default | Meaning |
|---|---|---|---|---|
| 0 | `Pitch` | -12..12 | 0 | Semitones. |
| 1 | `Formant` | -12..12 | 0 | Semitones. 0 = formants preserved. Equal to `Pitch` = formants move with pitch (cartoon). |
| 2 | `Band` | 0..1 | 0 | Telephone bandpass 300–3400 Hz, dry..full. |
| 3 | `Tilt` | -1..1 | 0 | Negative = chesty low shelf; positive = nasal 2.2 kHz peak. |
| 4 | `Grit` | 0..1 | 0 | `tanh` waveshaper drive. |
| 5 | `Ring` | 0..200 | 0 | Ring-modulator frequency in Hz. 0 disables. |
| 6 | `Noise` | 0..1 | 0 | Static, gated by input envelope. |
| 7 | `Mix` | 0..1 | 1 | Dry/wet. Exactly 0 is true zero-latency bypass. |
| 8 | (audio in) | — | — | LADSPA audio input port. |
| 9 | (audio out) | — | — | LADSPA audio output port. |

**Deviation from spec §4.1, recorded deliberately:** the spec listed seven controls. `Band` is added as an eighth because Whisperkill and Handset need a real telephone bandpass that `Tilt` cannot express without magic value ranges. Spec §4.1 is amended in Task 1.

### `Mix` semantics (locked here so every task agrees)

- `Mix == 0` — true bypass: output is the **undelayed** input, and the shifter is reset. This is what `panic` uses, so the real voice returns immediately rather than 55 ms late.
- `Mix > 0` — the dry signal is delayed to match the wet path before blending, so intermediate values do not comb.
- Crossing the boundary changes path latency by ~55 ms. A 10 ms equal-power crossfade covers the transition; a single faint artefact on panic is accepted and documented.

---

## Task 1: Repo scaffolding, build, and a passthrough plugin that loads

**Files:**
- Create: `Makefile`, `src/ladspa.h`, `src/tekvoice.cpp`, `tests/test_plugin.cpp`, `LICENSE`
- Modify: `docs/superpowers/specs/2026-09-22-tekvoice-design.md` (amend §4.1 to eight ports)

**Interfaces:**
- Consumes: nothing.
- Produces: `build/libtekvoice.so` exporting `const LADSPA_Descriptor *ladspa_descriptor(unsigned long index)`; plugin `UniqueID` 9271, `Label` `"tekvoice"`. Port indices exactly as the table above.

- [ ] **Step 1: Vendor `ladspa.h`**

`ladspa.h` is public domain. Copy the canonical 1.1 header to `src/ladspa.h`. If a system copy exists at `/usr/include/ladspa.h` use it; otherwise write the canonical header (it defines `LADSPA_Data`, `LADSPA_Descriptor`, `LADSPA_PortDescriptor`, the `LADSPA_PORT_*` and `LADSPA_HINT_*` constants, and `ladspa_descriptor`).

- [ ] **Step 2: Write the failing test**

```cpp
// tests/test_plugin.cpp
#include <dlfcn.h>
#include <cassert>
#include <cstdio>
#include <cmath>
#include <vector>
#include "../src/ladspa.h"

static const LADSPA_Descriptor *D = nullptr;

static void load() {
    void *h = dlopen("build/libtekvoice.so", RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); exit(1); }
    auto fn = (const LADSPA_Descriptor *(*)(unsigned long))dlsym(h, "ladspa_descriptor");
    assert(fn && "ladspa_descriptor not exported");
    D = fn(0);
    assert(D && "descriptor 0 missing");
}

// Runs `frames` of `in` through a fresh instance with the given control values.
static std::vector<float> run_voice(const std::vector<float> &in, float pitch,
                                    float formant, float band, float tilt,
                                    float grit, float ring, float noise,
                                    float mix, unsigned block = 256) {
    LADSPA_Handle h = D->instantiate(D, 48000);
    float c[8] = {pitch, formant, band, tilt, grit, ring, noise, mix};
    for (int i = 0; i < 8; i++) D->connect_port(h, i, &c[i]);
    std::vector<float> out(in.size(), 0.f);
    if (D->activate) D->activate(h);
    for (size_t i = 0; i + block <= in.size(); i += block) {
        D->connect_port(h, 8, const_cast<float *>(in.data()) + i);
        D->connect_port(h, 9, out.data() + i);
        D->run(h, block);
    }
    if (D->deactivate) D->deactivate(h);
    D->cleanup(h);
    return out;
}

static void test_descriptor_shape() {
    assert(D->PortCount == 10);
    assert(D->Label && std::string(D->Label) == "tekvoice");
    assert(LADSPA_IS_PORT_INPUT(D->PortDescriptors[8]) && LADSPA_IS_PORT_AUDIO(D->PortDescriptors[8]));
    assert(LADSPA_IS_PORT_OUTPUT(D->PortDescriptors[9]) && LADSPA_IS_PORT_AUDIO(D->PortDescriptors[9]));
    for (int i = 0; i < 8; i++) assert(LADSPA_IS_PORT_CONTROL(D->PortDescriptors[i]));
    printf("  ok descriptor_shape\n");
}

static void test_bypass_is_bit_exact() {
    std::vector<float> in(4096);
    for (size_t i = 0; i < in.size(); i++) in[i] = 0.3f * sinf(2.f * (float)M_PI * 220.f * i / 48000.f);
    auto out = run_voice(in, 0, 0, 0, 0, 0, 0, 0, /*mix=*/0.f);
    for (size_t i = 0; i < in.size(); i++) assert(fabsf(out[i] - in[i]) < 1e-6f);
    printf("  ok bypass_is_bit_exact\n");
}

int main() {
    load();
    test_descriptor_shape();
    test_bypass_is_bit_exact();
    printf("test_plugin: PASS\n");
    return 0;
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `make test-plugin`
Expected: FAIL — `build/libtekvoice.so` does not exist, `dlopen` reports "No such file or directory".

- [ ] **Step 4: Write the Makefile**

```make
CXX      ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wextra -fPIC -ffast-math
RB_CFLAGS := $(shell pkg-config --cflags rubberband)
RB_LIBS   := $(shell pkg-config --libs rubberband)

all: build/libtekvoice.so

build:
	mkdir -p build

build/libtekvoice.so: src/tekvoice.cpp src/dsp.h src/shifter.h src/ladspa.h | build
	$(CXX) $(CXXFLAGS) $(RB_CFLAGS) -shared -o $@ src/tekvoice.cpp $(RB_LIBS)

build/test_plugin: tests/test_plugin.cpp src/ladspa.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/test_plugin.cpp -ldl

build/test_dsp: tests/test_dsp.cpp src/dsp.h | build
	$(CXX) $(CXXFLAGS) -o $@ tests/test_dsp.cpp

test-plugin: build/libtekvoice.so build/test_plugin
	./build/test_plugin

test-dsp: build/test_dsp
	./build/test_dsp

test-voices:
	node tests/test_voices.cjs

test: test-dsp test-plugin test-voices

clean:
	rm -rf build

.PHONY: all test test-dsp test-plugin test-voices clean
```

- [ ] **Step 5: Write the minimal passthrough plugin**

`src/tekvoice.cpp` — descriptor with 10 ports; `run()` copies input to output when `Mix == 0` and otherwise also copies (real chain lands in Task 4). Create empty-but-valid `src/dsp.h` and `src/shifter.h` (include guards only) so the Makefile dependency list resolves.

```cpp
#include "ladspa.h"
#include <cstring>
#include <cstdlib>

enum { P_PITCH, P_FORMANT, P_BAND, P_TILT, P_GRIT, P_RING, P_NOISE, P_MIX, P_IN, P_OUT, P_N };

struct TekVoice {
    float *c[P_N];
    unsigned long rate;
};

static LADSPA_Handle tv_instantiate(const LADSPA_Descriptor *, unsigned long rate) {
    auto *t = (TekVoice *)calloc(1, sizeof(TekVoice));
    t->rate = rate;
    return t;
}
static void tv_connect(LADSPA_Handle h, unsigned long port, LADSPA_Data *dp) {
    ((TekVoice *)h)->c[port] = dp;
}
static void tv_run(LADSPA_Handle h, unsigned long n) {
    auto *t = (TekVoice *)h;
    const float *in = t->c[P_IN];
    float *out = t->c[P_OUT];
    memcpy(out, in, n * sizeof(float));
}
static void tv_cleanup(LADSPA_Handle h) { free(h); }
```

Plus the static `LADSPA_Descriptor` with `UniqueID = 9271`, `Label = "tekvoice"`, `Name = "TekVoice"`, `Maker = "TierTek"`, `Copyright = "GPL-3.0"`, port names `{"Pitch","Formant","Band","Tilt","Grit","Ring","Noise","Mix","In","Out"}`, and port range hints giving each control its default from the table above. Export `ladspa_descriptor` with `extern "C"` and `__attribute__((visibility("default")))`.

- [ ] **Step 6: Run the test to verify it passes**

Run: `make test-plugin`
Expected: PASS — `ok descriptor_shape`, `ok bypass_is_bit_exact`.

- [ ] **Step 7: Amend spec §4.1 to eight control ports**

Add the `Band` row to the spec's control-port table and a sentence recording why, so spec and code agree.

- [ ] **Step 8: Commit**

```bash
git add Makefile src tests/test_plugin.cpp LICENSE docs
git commit -m "feat: LADSPA passthrough skeleton with descriptor and bypass tests"
```

---

## Task 2: DSP primitives

**Files:**
- Create: `src/dsp.h`, `tests/test_dsp.cpp`

**Interfaces:**
- Consumes: nothing.
- Produces, all in `namespace tv`:
  - `struct Biquad { void lowpass(float sr,float f,float q); void highpass(float sr,float f,float q); void peak(float sr,float f,float q,float gainDb); void lowshelf(float sr,float f,float gainDb); float process(float x); void reset(); };`
  - `float shape(float x, float drive);` — `tanh` waveshaper with unity-ish makeup, `drive` 0..1, returns `x` unchanged at `drive == 0`.
  - `struct Ring { void set(float sr,float hz); float process(float x); };` — returns `x` unchanged when `hz <= 0`.
  - `struct NoiseGate { float process(float x, float amount); };` — adds envelope-gated white noise; returns `x` unchanged when `amount == 0`.
  - `struct Delay { void init(int maxSamples); void setDelay(int d); float process(float x); };` — fixed-capacity ring, no allocation after `init`.

- [ ] **Step 1: Write the failing tests**

```cpp
// tests/test_dsp.cpp
#include "../src/dsp.h"
#include <cassert>
#include <cstdio>
#include <cmath>
#include <vector>
using namespace tv;

static float rms(const std::vector<float> &v) {
    double s = 0; for (float x : v) s += (double)x * x; return (float)sqrt(s / v.size());
}
static std::vector<float> sine(float hz, int n, float sr = 48000.f) {
    std::vector<float> v(n);
    for (int i = 0; i < n; i++) v[i] = sinf(2.f * (float)M_PI * hz * i / sr);
    return v;
}

static void test_lowpass_attenuates_above_cutoff() {
    Biquad b; b.lowpass(48000.f, 500.f, 0.707f);
    auto hi = sine(5000.f, 4800);
    std::vector<float> out;
    for (float x : hi) out.push_back(b.process(x));
    std::vector<float> tail(out.end() - 2400, out.end());
    assert(rms(tail) < 0.1f * rms(hi));
    printf("  ok lowpass_attenuates_above_cutoff\n");
}

static void test_lowpass_passes_below_cutoff() {
    Biquad b; b.lowpass(48000.f, 5000.f, 0.707f);
    auto lo = sine(200.f, 4800);
    std::vector<float> out;
    for (float x : lo) out.push_back(b.process(x));
    std::vector<float> tail(out.end() - 2400, out.end());
    assert(rms(tail) > 0.9f * rms(lo));
    printf("  ok lowpass_passes_below_cutoff\n");
}

static void test_shape_is_identity_at_zero_drive() {
    for (float x = -1.f; x <= 1.f; x += 0.05f) assert(fabsf(shape(x, 0.f) - x) < 1e-6f);
    printf("  ok shape_is_identity_at_zero_drive\n");
}

static void test_shape_compresses_peaks() {
    assert(fabsf(shape(1.0f, 1.0f)) < 1.0f);
    assert(fabsf(shape(0.9f, 1.0f)) > fabsf(shape(0.2f, 1.0f)));
    printf("  ok shape_compresses_peaks\n");
}

static void test_ring_is_identity_when_disabled() {
    Ring r; r.set(48000.f, 0.f);
    auto s = sine(300.f, 512);
    for (float x : s) assert(fabsf(r.process(x) - x) < 1e-6f);
    printf("  ok ring_is_identity_when_disabled\n");
}

static void test_ring_creates_sidebands() {
    Ring r; r.set(48000.f, 100.f);
    auto s = sine(300.f, 48000);
    std::vector<float> out; for (float x : s) out.push_back(r.process(x));
    // Energy is preserved-ish but the 300 Hz component must drop sharply.
    double acc = 0; for (int i = 0; i < 48000; i++)
        acc += out[i] * sin(2.0 * M_PI * 300.0 * i / 48000.0);
    assert(fabs(acc / 48000.0) < 0.05);
    printf("  ok ring_creates_sidebands\n");
}

static void test_noise_is_identity_at_zero() {
    NoiseGate g; auto s = sine(300.f, 512);
    for (float x : s) assert(fabsf(g.process(x, 0.f) - x) < 1e-6f);
    printf("  ok noise_is_identity_at_zero\n");
}

static void test_delay_delays_exactly() {
    Delay d; d.init(1024); d.setDelay(100);
    std::vector<float> out;
    for (int i = 0; i < 400; i++) out.push_back(d.process(i == 0 ? 1.f : 0.f));
    assert(fabsf(out[100] - 1.f) < 1e-6f);
    for (int i = 0; i < 400; i++) if (i != 100) assert(fabsf(out[i]) < 1e-6f);
    printf("  ok delay_delays_exactly\n");
}

int main() {
    test_lowpass_attenuates_above_cutoff();
    test_lowpass_passes_below_cutoff();
    test_shape_is_identity_at_zero_drive();
    test_shape_compresses_peaks();
    test_ring_is_identity_when_disabled();
    test_ring_creates_sidebands();
    test_noise_is_identity_at_zero();
    test_delay_delays_exactly();
    printf("test_dsp: PASS\n");
    return 0;
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `make test-dsp`
Expected: FAIL — compile error, `tv::Biquad` and friends are not declared.

- [ ] **Step 3: Implement `src/dsp.h`**

Header-only `namespace tv`. `Biquad` uses the standard RBJ cookbook coefficients in direct form I with `double` state to avoid denormals. `shape(x,d)` returns `x` when `d==0`, else `tanhf(x*(1+8*d)) / tanhf(1+8*d)`. `Ring` holds a phase accumulator and returns `x` when `hz<=0`, else `x * (0.5f + 0.5f*cosf(phase))` so it stays unipolar-friendly and never inverts the whole signal. `NoiseGate` tracks a one-pole envelope of `|x|` and adds `amount * env * white` so static only appears while speaking. `Delay` is a power-of-two ring buffer sized in `init`, with `setDelay` clamped to capacity.

- [ ] **Step 4: Run to verify it passes**

Run: `make test-dsp`
Expected: PASS — all eight `ok` lines then `test_dsp: PASS`.

- [ ] **Step 5: Commit**

```bash
git add src/dsp.h tests/test_dsp.cpp Makefile
git commit -m "feat: DSP primitives (biquad, waveshaper, ring mod, noise gate, delay) with tests"
```

---

## Task 3: Rubber Band shifter with block-size FIFO

**Files:**
- Create: `src/shifter.h`
- Modify: `tests/test_plugin.cpp` (add latency and pitch-ratio tests — they run through the plugin, so they land after Task 4 wiring; this task's own check is the standalone harness below)

**Interfaces:**
- Consumes: nothing.
- Produces: `namespace tv { class Shifter { public: void init(float sr); void setPitchSemitones(float st); void setFormantSemitones(float st); void process(const float *in, float *out, unsigned long n); void reset(); int latencySamples() const; }; }`
  - `process` is block-size agnostic: it accepts any `n`, buffers into Rubber Band's fixed 512-sample blocks, and always writes exactly `n` samples.

- [ ] **Step 1: Write the failing standalone harness**

```cpp
// tests/test_shifter.cpp
#include "../src/shifter.h"
#include <cassert>
#include <cstdio>
#include <cmath>
#include <vector>
using namespace tv;

// Autocorrelation pitch estimate over the steady-state tail.
static float estimate_hz(const std::vector<float> &v, float sr = 48000.f) {
    int start = (int)v.size() / 2, N = (int)v.size() - start;
    int lo = (int)(sr / 800.f), hi = (int)(sr / 60.f);
    double best = -1e18; int bestLag = lo;
    for (int lag = lo; lag <= hi; lag++) {
        double s = 0;
        for (int i = 0; i + lag < N; i++) s += (double)v[start + i] * v[start + i + lag];
        s /= (N - lag);
        if (s > best) { best = s; bestLag = lag; }
    }
    return sr / bestLag;
}

static std::vector<float> run(float semis, unsigned block) {
    Shifter s; s.init(48000.f);
    s.setPitchSemitones(semis); s.setFormantSemitones(0.f);
    std::vector<float> in(48000 * 2), out(in.size(), 0.f);
    for (size_t i = 0; i < in.size(); i++)
        in[i] = 0.5f * sinf(2.f * (float)M_PI * 150.f * i / 48000.f);
    for (size_t i = 0; i + block <= in.size(); i += block)
        s.process(in.data() + i, out.data() + i, block);
    return out;
}

static void test_writes_every_block_size() {
    for (unsigned b : {64u, 128u, 256u, 512u, 1024u}) {
        auto out = run(0.f, b);
        std::vector<float> tail(out.end() - 24000, out.end());
        double e = 0; for (float x : tail) e += (double)x * x;
        assert(e > 1.0 && "shifter produced silence for this block size");
    }
    printf("  ok writes_every_block_size\n");
}

static void test_pitch_ratio_is_correct() {
    struct { float st; float expect; } cases[] = {{0.f, 150.f}, {7.f, 150.f * powf(2.f, 7.f/12.f)}, {-5.f, 150.f * powf(2.f, -5.f/12.f)}};
    for (auto &c : cases) {
        auto out = run(c.st, 256);
        float hz = estimate_hz(out);
        float err = fabsf(hz - c.expect) / c.expect;
        printf("    %+.0f st -> %.1f Hz (expected %.1f, err %.1f%%)\n", c.st, hz, c.expect, err * 100.f);
        assert(err < 0.05f);
    }
    printf("  ok pitch_ratio_is_correct\n");
}

static void test_latency_under_budget() {
    Shifter s; s.init(48000.f);
    s.setPitchSemitones(7.f); s.setFormantSemitones(0.f);
    int lat = s.latencySamples();
    printf("    reported latency %d samples (%.1f ms)\n", lat, lat * 1000.f / 48000.f);
    assert(lat > 0 && lat < 48000 * 70 / 1000);   // spec §11.1 budget: under 70 ms
    printf("  ok latency_under_budget\n");
}

int main() {
    test_writes_every_block_size();
    test_pitch_ratio_is_correct();
    test_latency_under_budget();
    printf("test_shifter: PASS\n");
    return 0;
}
```

Add to the Makefile:

```make
build/test_shifter: tests/test_shifter.cpp src/shifter.h | build
	$(CXX) $(CXXFLAGS) $(RB_CFLAGS) -o $@ tests/test_shifter.cpp $(RB_LIBS)

test-shifter: build/test_shifter
	./build/test_shifter
```
and add `test-shifter` to the `test` target and `.PHONY`.

- [ ] **Step 2: Run to verify it fails**

Run: `make test-shifter`
Expected: FAIL — compile error, `tv::Shifter` not declared.

- [ ] **Step 3: Implement `src/shifter.h`**

Wraps `RubberBand::RubberBandLiveShifter` constructed with `OptionWindowShort | OptionFormantPreserved` at the given rate, 1 channel. `init` queries `getBlockSize()` (512) and sizes two `std::vector<float>` FIFOs to `blockSize * 4`; nothing allocates after that. `process` appends `n` input samples to the in-FIFO; while at least `blockSize` are available it calls `shift()` into the out-FIFO; then drains exactly `n` samples from the out-FIFO, emitting zeros while the FIFO is still priming. `setPitchSemitones` calls `setPitchScale(powf(2, st/12))`; `setFormantSemitones` calls `setFormantScale(powf(2, st/12))`. `latencySamples()` returns `getStartDelay() + blockSize`. `reset()` clears both FIFOs and calls `RubberBandLiveShifter::reset()`.

- [ ] **Step 4: Run to verify it passes**

Run: `make test-shifter`
Expected: PASS — pitch ratios within 5% at 0, +7 and −5 semitones; latency printed and under 70 ms.

- [ ] **Step 5: Commit**

```bash
git add src/shifter.h tests/test_shifter.cpp Makefile
git commit -m "feat: Rubber Band live shifter with block-size-agnostic FIFO"
```

---

## Task 4: Wire the full chain into `run()`

**Files:**
- Modify: `src/tekvoice.cpp`, `tests/test_plugin.cpp`

**Interfaces:**
- Consumes: `tv::Biquad`, `tv::shape`, `tv::Ring`, `tv::NoiseGate`, `tv::Delay` (Task 2); `tv::Shifter` (Task 3).
- Produces: a complete `run()` honouring all eight control ports and the `Mix` semantics locked above.

Signal order: `in → Shifter(Pitch,Formant) → Band → Tilt → shape(Grit) → Ring → NoiseGate → blend with delay-matched dry per Mix → out`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_plugin.cpp` (reusing `run_voice` and adding the `estimate_hz` helper from Task 3):

```cpp
static void test_pitch_voice_shifts_fundamental() {
    std::vector<float> in(96000);
    for (size_t i = 0; i < in.size(); i++)
        in[i] = 0.5f * sinf(2.f * (float)M_PI * 150.f * i / 48000.f);
    auto out = run_voice(in, /*pitch=*/7, 0, 0, 0, 0, 0, 0, /*mix=*/1.f);
    float hz = estimate_hz(out);
    float expect = 150.f * powf(2.f, 7.f / 12.f);
    assert(fabsf(hz - expect) / expect < 0.05f);
    printf("  ok pitch_voice_shifts_fundamental (%.1f Hz)\n", hz);
}

static void test_zero_latency_voice_has_no_shifter_delay() {
    // Ring-only voice: pitch and formant are 0, so the shifter must be skipped.
    std::vector<float> in(8192, 0.f); in[0] = 1.f;
    auto out = run_voice(in, 0, 0, 0, 0, 0, /*ring=*/55.f, 0, 1.f);
    int first = -1;
    for (size_t i = 0; i < out.size(); i++) if (fabsf(out[i]) > 1e-4f) { first = (int)i; break; }
    assert(first >= 0 && first < 96);   // under 2 ms at 48 kHz
    printf("  ok zero_latency_voice_has_no_shifter_delay (first energy at %d)\n", first);
}

static void test_output_is_finite_and_unclipped() {
    std::vector<float> in(48000);
    for (size_t i = 0; i < in.size(); i++)
        in[i] = 0.9f * sinf(2.f * (float)M_PI * 110.f * i / 48000.f);
    auto out = run_voice(in, -7, -5, 1.f, -0.5f, 1.f, 120.f, 1.f, 1.f);
    for (float x : out) { assert(std::isfinite(x)); assert(fabsf(x) <= 1.5f); }
    printf("  ok output_is_finite_and_unclipped\n");
}

static void test_is_deterministic() {
    std::vector<float> in(24000);
    for (size_t i = 0; i < in.size(); i++)
        in[i] = 0.4f * sinf(2.f * (float)M_PI * 180.f * i / 48000.f);
    auto a = run_voice(in, 5, 2, 0.5f, 0.3f, 0.4f, 0, 0, 1.f);
    auto b = run_voice(in, 5, 2, 0.5f, 0.3f, 0.4f, 0, 0, 1.f);
    for (size_t i = 0; i < a.size(); i++) assert(a[i] == b[i]);
    printf("  ok is_deterministic\n");
}

static void test_block_size_invariance() {
    std::vector<float> in(24576);
    for (size_t i = 0; i < in.size(); i++)
        in[i] = 0.4f * sinf(2.f * (float)M_PI * 160.f * i / 48000.f);
    auto a = run_voice(in, 4, 0, 0, 0, 0, 0, 0, 1.f, 256);
    auto b = run_voice(in, 4, 0, 0, 0, 0, 0, 0, 1.f, 1024);
    // Same pitch result regardless of host block size.
    assert(fabsf(estimate_hz(a) - estimate_hz(b)) < 4.f);
    printf("  ok block_size_invariance\n");
}
```

Register all five in `main()`. `NoiseGate` must be seeded deterministically for `test_is_deterministic`; use a fixed-seed xorshift inside `NoiseGate`, reset in `activate()`.

- [ ] **Step 2: Run to verify it fails**

Run: `make test-plugin`
Expected: FAIL — `pitch_voice_shifts_fundamental` asserts; output is still a passthrough copy.

- [ ] **Step 3: Implement the chain**

In `TekVoice`: add `tv::Shifter sh; tv::Biquad bpLo, bpHi, tilt; tv::Ring ring; tv::NoiseGate ng; tv::Delay dry; float xfade;`. `instantiate` calls `sh.init(rate)` and `dry.init(next_pow2(rate * 100 / 1000))` — 100 ms of headroom, sized once.

`run()`:
1. Read the eight control values once into locals (hosts may change them between blocks, never within one).
2. If `Mix <= 0`: `memcpy` input to output, call `sh.reset()`, set `xfade` target 0, return — this is the true-bypass path with no delay.
3. Otherwise: if `Pitch != 0 || Formant != 0`, push through `sh` (updating scales only when the semitone values changed, to avoid needless internal resets); else copy input to the work buffer unchanged so zero-latency voices skip Rubber Band entirely.
4. `Band > 0`: `bpHi.highpass(sr, 300, 0.707)` and `bpLo.lowpass(sr, 3400, 0.707)`, blended by `Band`. Coefficients recomputed only when `Band` changes.
5. `Tilt`: `tilt.peak(sr, 2200, 1.0, Tilt * 12)` for `Tilt > 0`, `tilt.lowshelf(sr, 250, -Tilt * 12)` for `Tilt < 0`, bypassed at exactly 0.
6. `shape(x, Grit)`, then `ring.process`, then `ng.process(x, Noise)`.
7. `dry.setDelay(sh.latencySamples())`; blend `out = wet * Mix + dryDelayed * (1 - Mix)` with a 10 ms equal-power crossfade on `xfade` when crossing into or out of bypass.

No allocation, no locks, no logging anywhere in `run()`.

- [ ] **Step 4: Run to verify it passes**

Run: `make test`
Expected: PASS — `test_dsp`, `test_shifter`, and all seven `test_plugin` assertions.

- [ ] **Step 5: Commit**

```bash
git add src/tekvoice.cpp tests/test_plugin.cpp
git commit -m "feat: full voice chain with true-bypass panic path"
```

---

## Task 5: The voice table

**Files:**
- Create: `voices.json`, `tests/test_voices.cjs`

**Interfaces:**
- Consumes: the control-port table.
- Produces: `voices.json` — `{ "version": 1, "voices": [ { "id", "name", "blurb", "icon", "color", "pitch", "formant", "band", "tilt", "grit", "ring", "noise" } ] }`. `mix` is deliberately absent: it is owned by arm/panic, not by a voice.

The nine voices (ids are final; names contain no third-party marks):

| id | name | pitch | formant | band | tilt | grit | ring | noise |
|---|---|---|---|---|---|---|---|---|
| `chipper` | Chipper | +9 | +9 | 0 | 0.2 | 0 | 0 | 0 |
| `quackers` | Quackers | +7 | +12 | 0 | 0.55 | 0.35 | 0 | 0 |
| `deepsix` | Deep Six | -7 | -5 | 0 | -0.5 | 0.3 | 0 | 0 |
| `whisperkill` | Whisperkill | -4 | -2 | 0.85 | 0.15 | 0.5 | 0 | 0.08 |
| `ascend` | Ascend | +4 | 0 | 0 | 0.1 | 0 | 0 | 0 |
| `descend` | Descend | -4 | 0 | 0 | -0.1 | 0.05 | 0 | 0 |
| `tinhead` | Tinhead | 0 | 0 | 0.3 | 0.2 | 0.2 | 55 | 0 |
| `toaster` | Toaster | 0 | 0 | 0.4 | 0.3 | 0.35 | 110 | 0 |
| `handset` | Handset | 0 | 0 | 1.0 | 0.25 | 0.45 | 0 | 0.15 |

- [ ] **Step 1: Write the failing test**

```js
// tests/test_voices.cjs
const fs = require('fs');
const assert = require('assert');

const RANGES = { pitch:[-12,12], formant:[-12,12], band:[0,1], tilt:[-1,1],
                 grit:[0,1], ring:[0,200], noise:[0,1] };
const BANNED = /disney|donald|duck|ghostface|scream|paramount|fun\s*world|mickey|chipmunk|dalek|cylon/i;

const doc = JSON.parse(fs.readFileSync(`${__dirname}/../voices.json`, 'utf8'));
assert.strictEqual(doc.version, 1, 'version must be 1');
assert.strictEqual(doc.voices.length, 9, 'expected nine voices');

const ids = new Set();
for (const v of doc.voices) {
  assert.ok(/^[a-z0-9]+$/.test(v.id), `bad id: ${v.id}`);
  assert.ok(!ids.has(v.id), `duplicate id: ${v.id}`);
  ids.add(v.id);
  assert.ok(v.name && v.blurb && v.icon && v.color, `${v.id} missing display fields`);
  assert.ok(/^#[0-9a-fA-F]{6}$/.test(v.color), `${v.id} colour must be #rrggbb`);
  assert.ok(!('mix' in v), `${v.id} must not define mix`);
  for (const [k, [lo, hi]] of Object.entries(RANGES)) {
    assert.ok(typeof v[k] === 'number', `${v.id}.${k} missing`);
    assert.ok(v[k] >= lo && v[k] <= hi, `${v.id}.${k}=${v[k]} out of [${lo},${hi}]`);
  }
  const text = `${v.id} ${v.name} ${v.blurb}`;
  assert.ok(!BANNED.test(text), `${v.id} contains a third-party mark: ${text}`);
}

const zero = doc.voices.filter(v => v.pitch === 0 && v.formant === 0).map(v => v.id);
assert.deepStrictEqual(zero.sort(), ['handset', 'tinhead', 'toaster'],
  'exactly the three bypass voices must have no pitch shift');

console.log(`test_voices: PASS (${doc.voices.length} voices)`);
```

- [ ] **Step 2: Run to verify it fails**

Run: `make test-voices`
Expected: FAIL — `ENOENT`, `voices.json` does not exist.

- [ ] **Step 3: Write `voices.json`**

Use the table above. Each `blurb` is one short original sentence describing the sound, naming no third-party character. Icons are single emoji or Nerd Font glyphs; colours are distinct `#rrggbb` values for the widget tint.

- [ ] **Step 4: Run to verify it passes**

Run: `make test-voices`
Expected: PASS — `test_voices: PASS (9 voices)`.

- [ ] **Step 5: Commit**

```bash
git add voices.json tests/test_voices.cjs
git commit -m "feat: nine-voice table with range and trademark validation"
```

---

## Task 6: The CLI and the filter-chain fragment

**Files:**
- Create: `bin/tekvoice`, `pipewire/tekvoice.conf.in`, `tests/test_cli.sh`

**Interfaces:**
- Consumes: `voices.json`, `build/libtekvoice.so`.
- Produces: `tekvoice arm|disarm|set <id>|strength <0-100>|panic|status`, exit 0 on success, 1 on error, machine-readable `status` as `key=value` lines.

Runtime layout: config generated into `$XDG_RUNTIME_DIR/tekvoice/` (a private `PIPEWIRE_CONFIG_DIR`), so the user's own PipeWire configuration is never touched. State (current voice, strength) in `$XDG_RUNTIME_DIR/tekvoice/state`.

- [ ] **Step 1: Write `pipewire/tekvoice.conf.in`**

```
context.modules = [
  { name = libpipewire-module-filter-chain
    args = {
      audio.channels   = 1
      audio.position   = [ MONO ]
      node.description = "TekVoice"
      media.name       = "TekVoice"
      filter.graph = {
        nodes = [
          { name = tv type = ladspa plugin = "@SO@" label = tekvoice
            control = { "Pitch" = 0.0 "Formant" = 0.0 "Band" = 0.0 "Tilt" = 0.0
                        "Grit" = 0.0 "Ring" = 0.0 "Noise" = 0.0 "Mix" = 0.0 } }
        ]
      }
      capture.props  = { node.name = "tekvoice_in"  media.class = "Stream/Input/Audio" }
      playback.props = { node.name = "tekvoice_src" media.class = "Audio/Source"
                         node.description = "TekVoice" }
    }
  }
]
```

`media.class` is `Audio/Source` — `Audio/Source/Virtual` crashes PipeWire 1.6.8 (spec §11.4). `Mix` starts at 0 so arming is silent-safe: the real voice passes through until a voice is chosen.

- [ ] **Step 2: Write the failing test**

```sh
# tests/test_cli.sh — run with: sh tests/test_cli.sh
set -e
T=$(mktemp -d); export XDG_RUNTIME_DIR="$T"
fail() { echo "FAIL: $1"; exit 1; }

./bin/tekvoice status | grep -q '^armed=no$' || fail "status before arm should report armed=no"
./bin/tekvoice set quackers >/dev/null 2>&1 && fail "set should fail while disarmed"
./bin/tekvoice set nosuchvoice >/dev/null 2>&1 && fail "unknown voice should fail"

./bin/tekvoice arm || fail "arm failed"
./bin/tekvoice status | grep -q '^armed=yes$' || fail "status should report armed=yes"
pactl list short sources | grep -q tekvoice_src || fail "TekVoice source not present"

./bin/tekvoice set quackers || fail "set quackers failed"
./bin/tekvoice status | grep -q '^voice=quackers$' || fail "voice not recorded"

BEFORE=$(pactl list short sources | grep tekvoice_src | cut -f1)
./bin/tekvoice set deepsix || fail "set deepsix failed"
AFTER=$(pactl list short sources | grep tekvoice_src | cut -f1)
[ "$BEFORE" = "$AFTER" ] || fail "source index changed on voice switch — the mic dropped"

./bin/tekvoice panic || fail "panic failed"
./bin/tekvoice status | grep -q '^mix=0' || fail "panic should zero mix"

./bin/tekvoice disarm || fail "disarm failed"
./bin/tekvoice status | grep -q '^armed=no$' || fail "status after disarm should report armed=no"
echo "test_cli: PASS"
```

Add `test-cli: ; sh tests/test_cli.sh` to the Makefile and to `.PHONY`. It is not part of `make test` because it needs a live PipeWire session; it gets its own target.

- [ ] **Step 3: Run to verify it fails**

Run: `make test-cli`
Expected: FAIL — `./bin/tekvoice: No such file or directory`.

- [ ] **Step 4: Implement `bin/tekvoice`**

POSIX `sh`, no bashisms. Responsibilities:
- `arm` — resolve the `.so` (prefer `$TEKVOICE_SO`, then `~/.ladspa/libtekvoice.so`, then `build/libtekvoice.so` relative to the script); substitute `@SO@` into `$XDG_RUNTIME_DIR/tekvoice/filter-chain.conf.d/tekvoice.conf`; copy `/usr/share/pipewire/filter-chain.conf` beside it; launch `PIPEWIRE_CONFIG_DIR=... pipewire -c filter-chain.conf` detached, recording the pid. Poll `pactl list short sources` for `tekvoice_src` for up to 3 s and fail loudly if it never appears.
- `capture_id` (internal) — `pw-dump` filtered by `node.name == "tekvoice_in"` via `python3`, since controls live on the capture node (spec §11.3).
- `set <id>` — read the voice row from `voices.json`, scale `pitch`, `formant`, `grit`, `ring`, `noise` by `strength/100`, then one `pw-cli s <capture-id> Props '{ params = [ ... "Mix" 1.0 ] }'` carrying all eight values in a single write so the voice changes atomically.
- `strength <0-100>` — persist and re-apply the current voice.
- `panic` — write `"Mix" 0.0` only. Never unload.
- `disarm` — refuse with exit 1 if any application is linked to `tekvoice_src` unless `--force` is given; otherwise kill the recorded pid.
- `status` — print `armed=`, `voice=`, `strength=`, `mix=`, `consumers=` as `key=value` lines.

- [ ] **Step 5: Run to verify it passes**

Run: `make test-cli`
Expected: PASS — including the source-index-unchanged assertion, which is the mic-never-drops guarantee under test.

- [ ] **Step 6: Commit**

```bash
git add bin/tekvoice pipewire/tekvoice.conf.in tests/test_cli.sh Makefile
git commit -m "feat: tekvoice CLI with atomic live voice switching"
```

---

## Task 7: The Omarchy plugin surface

**Files:**
- Create: `manifest.json`, `BarWidget.qml`, `Panel.qml`, `VoiceModel.js`, `hypr/tekvoice.lua`, `tests/test_model.cjs`

**Interfaces:**
- Consumes: `bin/tekvoice`, `voices.json`.
- Produces: an Omarchy plugin `tiertek.tekvoice` following the Scratchpad Deck layout (`manifest.json` + `BarWidget.qml` + `bin/` + `hypr/*.lua`).

- [ ] **Step 1: Write the failing model test**

```js
// tests/test_model.cjs
const assert = require('assert');
const { parseStatus, cycle } = require('../VoiceModel.js');

const s = parseStatus('armed=yes\nvoice=quackers\nstrength=80\nmix=1.0\nconsumers=2\n');
assert.strictEqual(s.armed, true);
assert.strictEqual(s.voice, 'quackers');
assert.strictEqual(s.strength, 80);
assert.strictEqual(s.consumers, 2);

const d = parseStatus('armed=no\n');
assert.strictEqual(d.armed, false);
assert.strictEqual(d.voice, null);
assert.strictEqual(d.strength, 100);

const ids = ['chipper', 'quackers', 'deepsix'];
assert.strictEqual(cycle(ids, 'chipper', 1), 'quackers');
assert.strictEqual(cycle(ids, 'deepsix', 1), 'chipper');
assert.strictEqual(cycle(ids, 'chipper', -1), 'deepsix');
assert.strictEqual(cycle(ids, null, 1), 'chipper');
assert.strictEqual(cycle([], null, 1), null);

console.log('test_model: PASS');
```

Add `test-model: ; node tests/test_model.cjs` to the Makefile, to `.PHONY`, and to the `test` target.

- [ ] **Step 2: Run to verify it fails**

Run: `make test-model`
Expected: FAIL — `Cannot find module '../VoiceModel.js'`.

- [ ] **Step 3: Implement `VoiceModel.js`**

Plain CommonJS so both QML and Node can load it. `parseStatus(text)` returns `{armed, voice, strength, mix, consumers}` with defaults `armed:false, voice:null, strength:100, mix:0, consumers:0`. `cycle(ids, current, dir)` returns the next id, wrapping, returning the first id when `current` is null and `null` for an empty list.

- [ ] **Step 4: Run to verify it passes**

Run: `make test-model`
Expected: PASS — `test_model: PASS`.

- [ ] **Step 5: Write the plugin surface**

- `manifest.json` — id `tiertek.tekvoice`, name `TekVoice`, version `0.1.0`, author TierTek, licence GPL-3.0, bar widget entry pointing at `BarWidget.qml`, matching the field set in `omarchy-scratchpad-deck/manifest.json`.
- `BarWidget.qml` — a microphone glyph. Outline when disarmed; filled and tinted with the active voice's `color` when armed. Left click toggles `Panel.qml`; middle click runs `panic`. Polls `tekvoice status` every 2 s.
- `Panel.qml` — a grid of voice tiles from `voices.json` showing icon, name and blurb, the active one highlighted; a strength slider (0–100); an arm/disarm toggle; a large panic button.
- `hypr/tekvoice.lua` — binds `SUPER ALT V` to toggle the panel, `SUPER ALT SHIFT V` to cycle voice, `SUPER ALT X` to panic, using `hl.dsp` dispatch syntax (the old `closewindow class:x` form is dead — see the `hyprctl-lua-dispatch-syntax` memory).

- [ ] **Step 6: Verify the plugin loads**

Run: `omarchy restart shell`, then confirm the widget appears in the bar and `tekvoice status` agrees with what it shows. Installed-plugin QML stays cached until the shell restarts — a known trap from the sibling plugins.

- [ ] **Step 7: Commit**

```bash
git add manifest.json BarWidget.qml Panel.qml VoiceModel.js hypr tests/test_model.cjs Makefile
git commit -m "feat: Omarchy bar widget, voice panel, and hotkeys"
```

---

## Task 8: Install script, README, and publication

**Files:**
- Create: `install.sh`, `README.md`, `.github/` (none needed), `preview.png`

**Interfaces:**
- Consumes: everything above.
- Produces: a public repository at `github.com/TIerTek/omarchy-tekvoice`.

- [ ] **Step 1: Write `install.sh`**

Checks for `pipewire` and `pkg-config rubberband` and exits with a clear message naming the missing Arch package if either is absent. Runs `make`, installs `build/libtekvoice.so` to `~/.ladspa/libtekvoice.so`, symlinks the repo into `~/.config/omarchy/plugins/tiertek.tekvoice`, and prints the three hotkeys. **Never uses `sudo`** — everything lands under `$HOME`. Never tests under a fake `$HOME` (shell IPC and pkexec are not sandboxed — this bit the BioVirus installer).

- [ ] **Step 2: Run the full test suite**

Run: `make test && make test-cli`
Expected: every suite passes.

- [ ] **Step 3: Write `README.md`**

What it is, the nine voices and what each sounds like, install, the three hotkeys, how to select TekVoice as your microphone in Zoom/Discord/Chrome, the measured ~55 ms added latency stated plainly, the `Audio/Source/Virtual` PipeWire bug and workaround, and dependencies. No third-party marks anywhere.

- [ ] **Step 4: Commit and publish**

```bash
git add install.sh README.md preview.png
git commit -m "docs: README, install script, and preview"
gh repo create TIerTek/omarchy-tekvoice --public --source=. --remote=origin --push
```

- [ ] **Step 5: Verify the published repository**

Run: `gh repo view TIerTek/omarchy-tekvoice --json url,visibility,defaultBranchRef`
Expected: public, `master` pushed, all commits present.

---

## Self-Review

**Spec coverage:** §1 purpose → Tasks 4, 6. §3.1 components → Tasks 1–7, one task per unit. §3.2 plain Makefile → Task 1. §4 roster → Task 5. §4.1 ports → Task 1 (amended to eight, deviation recorded). §5/§11.1 latency → Task 3 regression test. §6 controls, panic, disarm guard → Task 6; hotkeys → Task 7. §7 testing → Tasks 1–5, 7 (malloc-interposer test **deliberately dropped**: the "no allocation in `run()`" rule is enforced by construction — every buffer is sized in `instantiate()` — and an `LD_PRELOAD` counter across a `dlopen`ed `.so` proved more fragile than the property it checks; recorded here rather than silently skipped). §8 licensing → Global Constraints, enforced mechanically by the `BANNED` regex in Task 5. §9 phasing → this plan is phase 1 and 3; phase 2 HUD is a separate plan. §10 risks → all four addressed; the control-port risk is closed by §11.3.

**Placeholder scan:** no TBD, no "handle errors appropriately", no "similar to Task N". Every code step carries real code.

**Type consistency:** `tv::Shifter::process(const float*, float*, unsigned long)` is used identically in Tasks 3 and 4. `latencySamples()` named consistently in both. `parseStatus`/`cycle` signatures match between Task 7 steps 1 and 3. Port indices `P_PITCH..P_OUT` are fixed in Task 1 and referenced unchanged in Tasks 4 and 6. `voices.json` field names match between Task 5 and Task 7.
