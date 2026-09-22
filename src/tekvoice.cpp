// TekVoice — a LADSPA voice changer hosted by PipeWire's filter-chain.
// SPDX-License-Identifier: GPL-3.0-or-later
#include "ladspa.h"
#include "dsp.h"
#include "shifter.h"
#include <cstring>
#include <cstdlib>
#include <algorithm>
#include <new>

static const int kMaxChunk = 8192;
static const float kFadeMs = 10.f;

enum { P_PITCH, P_FORMANT, P_BAND, P_TILT, P_GRIT, P_RING, P_NOISE, P_MIX, P_IN, P_OUT, P_N };

struct TekVoice {
    LADSPA_Data *c[P_N];
    unsigned long rate;

    tv::Shifter sh;
    tv::Biquad bpHi, bpLo, tilt;
    tv::Ring ring;
    tv::NoiseGate ng;
    tv::Delay dry;
    std::vector<float> wet;

    // Cached control values, so coefficients are recomputed only on change.
    float lastBand = -99.f, lastTilt = -99.f, lastRing = -99.f;
    float wetGain = 0.f;      // smoothed Mix
    float fadeStep = 0.f;
    bool  bypassed = true;

    void applyBand(float band) {
        if (band == lastBand) return;
        lastBand = band;
        if (band > 0.f) {
            bpHi.highpass((float)rate, 300.f, 0.707f);
            bpLo.lowpass((float)rate, 3400.f, 0.707f);
        } else {
            bpHi.identity(); bpLo.identity();
        }
        bpHi.reset(); bpLo.reset();
    }
    void applyTilt(float t) {
        if (t == lastTilt) return;
        lastTilt = t;
        if (t > 0.f)      tilt.peak((float)rate, 2200.f, 1.0f, t * 12.f);
        else if (t < 0.f) tilt.lowshelf((float)rate, 250.f, -t * 12.f);
        else              tilt.identity();
        tilt.reset();
    }
    void applyRing(float hz) {
        if (hz == lastRing) return;
        lastRing = hz;
        ring.set((float)rate, hz);
    }
};

static LADSPA_Handle tv_instantiate(const LADSPA_Descriptor *, unsigned long rate) {
    auto *t = new (std::nothrow) TekVoice();
    if (!t) return nullptr;
    memset(t->c, 0, sizeof(t->c));
    t->rate = rate;
    t->sh.init((float)rate);
    // 150 ms of dry headroom: comfortably more than the shifter can ever ask for.
    t->dry.init((int)(rate * 150 / 1000));
    t->wet.assign(kMaxChunk, 0.f);
    t->fadeStep = 1.f / (kFadeMs * 0.001f * (float)rate);
    return t;
}

static void tv_connect(LADSPA_Handle h, unsigned long port, LADSPA_Data *dp) {
    if (port < P_N) ((TekVoice *)h)->c[port] = dp;
}

static void tv_activate(LADSPA_Handle h) {
    auto *t = (TekVoice *)h;
    t->sh.reset(); t->ng.reset(); t->dry.reset(); t->ring.reset();
    t->bpHi.reset(); t->bpLo.reset(); t->tilt.reset();
    t->wetGain = 0.f; t->bypassed = true;
    t->lastBand = t->lastTilt = t->lastRing = -99.f;
}

static inline float ctl(const LADSPA_Data *p, float def) { return p ? *p : def; }

static void tv_run(LADSPA_Handle h, unsigned long n) {
    auto *t = (TekVoice *)h;
    const LADSPA_Data *in = t->c[P_IN];
    LADSPA_Data *out = t->c[P_OUT];
    if (!in || !out) return;

    // Controls are sampled once per block; hosts never change them mid-block.
    const float pitch   = ctl(t->c[P_PITCH],   0.f);
    const float formant = ctl(t->c[P_FORMANT], 0.f);
    const float band    = ctl(t->c[P_BAND],    0.f);
    const float tiltAmt = ctl(t->c[P_TILT],    0.f);
    const float grit    = ctl(t->c[P_GRIT],    0.f);
    const float ringHz  = ctl(t->c[P_RING],    0.f);
    const float noise   = ctl(t->c[P_NOISE],   0.f);
    const float mix     = std::min(1.f, std::max(0.f, ctl(t->c[P_MIX], 0.f)));

    // True bypass: undelayed dry, shifter parked. This is what panic uses, so
    // the real voice returns immediately rather than one shifter-latency late.
    if (mix <= 0.f && t->wetGain <= 0.f) {
        if (!t->bypassed) { t->sh.reset(); t->bypassed = true; }
        memmove(out, in, n * sizeof(LADSPA_Data));
        return;
    }
    t->bypassed = false;

    const bool usesShifter = (pitch != 0.f || formant != 0.f);
    t->applyBand(band);
    t->applyTilt(tiltAmt);
    t->applyRing(ringHz);
    if (usesShifter) {
        t->sh.setPitchSemitones(pitch);
        t->sh.setFormantSemitones(formant);
    }
    t->dry.setDelay(usesShifter ? t->sh.latencySamples() : 0);

    unsigned long done = 0;
    while (done < n) {
        unsigned long chunk = std::min<unsigned long>(n - done, kMaxChunk);
        float *w = t->wet.data();

        if (usesShifter) t->sh.process(in + done, w, chunk);
        else             memcpy(w, in + done, chunk * sizeof(float));

        for (unsigned long i = 0; i < chunk; i++) {
            float x = w[i];
            if (band > 0.f) {
                float b = t->bpLo.process(t->bpHi.process(x));
                x = x + band * (b - x);
            }
            if (tiltAmt != 0.f) x = t->tilt.process(x);
            x = tv::shape(x, grit);
            x = t->ring.process(x);
            x = t->ng.process(x, noise);

            float d = t->dry.process(in[done + i]);

            // Ramp the wet gain so panic and voice arming do not click.
            if (t->wetGain < mix) t->wetGain = std::min(mix, t->wetGain + t->fadeStep);
            else if (t->wetGain > mix) t->wetGain = std::max(mix, t->wetGain - t->fadeStep);

            float y = x * t->wetGain + d * (1.f - t->wetGain);
            out[done + i] = std::min(1.5f, std::max(-1.5f, y));
        }
        done += chunk;
    }
}

static void tv_cleanup(LADSPA_Handle h) { delete (TekVoice *)h; }

static const char *const kPortNames[P_N] = {
    "Pitch", "Formant", "Band", "Tilt", "Grit", "Ring", "Noise", "Mix", "In", "Out"
};

static const LADSPA_PortDescriptor kPortDescriptors[P_N] = {
    LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL, LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
    LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL, LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
    LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL, LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
    LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL, LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
    LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO,   LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO
};

#define BOUNDED (LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE)
static const LADSPA_PortRangeHint kPortRangeHints[P_N] = {
    { BOUNDED | LADSPA_HINT_DEFAULT_0,   -12.0f, 12.0f },  // Pitch
    { BOUNDED | LADSPA_HINT_DEFAULT_0,   -12.0f, 12.0f },  // Formant
    { BOUNDED | LADSPA_HINT_DEFAULT_0,     0.0f,  1.0f },  // Band
    { BOUNDED | LADSPA_HINT_DEFAULT_0,    -1.0f,  1.0f },  // Tilt
    { BOUNDED | LADSPA_HINT_DEFAULT_0,     0.0f,  1.0f },  // Grit
    { BOUNDED | LADSPA_HINT_DEFAULT_0,     0.0f, 200.0f }, // Ring
    { BOUNDED | LADSPA_HINT_DEFAULT_0,     0.0f,  1.0f },  // Noise
    { BOUNDED | LADSPA_HINT_DEFAULT_0,     0.0f,  1.0f },  // Mix
    { 0, 0.0f, 0.0f },
    { 0, 0.0f, 0.0f }
};

static LADSPA_Descriptor kDescriptor = {
    9271, "tekvoice", LADSPA_PROPERTY_HARD_RT_CAPABLE,
    "TekVoice", "TierTek", "GPL-3.0-or-later",
    P_N, kPortDescriptors, kPortNames, kPortRangeHints,
    nullptr,
    tv_instantiate, tv_connect, tv_activate, tv_run,
    nullptr, nullptr, nullptr, tv_cleanup
};

extern "C" __attribute__((visibility("default")))
const LADSPA_Descriptor *ladspa_descriptor(unsigned long index) {
    return index == 0 ? &kDescriptor : nullptr;
}
