// TekVoice — a LADSPA voice changer hosted by PipeWire's filter-chain.
// SPDX-License-Identifier: GPL-3.0-or-later
#include "ladspa.h"
#include "dsp.h"
#include "shifter.h"
#include <cstring>
#include <cstdlib>

enum { P_PITCH, P_FORMANT, P_BAND, P_TILT, P_GRIT, P_RING, P_NOISE, P_MIX, P_IN, P_OUT, P_N };

struct TekVoice {
    LADSPA_Data *c[P_N];
    unsigned long rate;
};

static LADSPA_Handle tv_instantiate(const LADSPA_Descriptor *, unsigned long rate) {
    auto *t = (TekVoice *)calloc(1, sizeof(TekVoice));
    if (!t) return nullptr;
    t->rate = rate;
    return t;
}

static void tv_connect(LADSPA_Handle h, unsigned long port, LADSPA_Data *dp) {
    if (port < P_N) ((TekVoice *)h)->c[port] = dp;
}

static void tv_run(LADSPA_Handle h, unsigned long n) {
    auto *t = (TekVoice *)h;
    const LADSPA_Data *in = t->c[P_IN];
    LADSPA_Data *out = t->c[P_OUT];
    if (!in || !out) return;
    memmove(out, in, n * sizeof(LADSPA_Data));
}

static void tv_cleanup(LADSPA_Handle h) { free(h); }

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
    tv_instantiate, tv_connect, nullptr, tv_run,
    nullptr, nullptr, nullptr, tv_cleanup
};

extern "C" __attribute__((visibility("default")))
const LADSPA_Descriptor *ladspa_descriptor(unsigned long index) {
    return index == 0 ? &kDescriptor : nullptr;
}
