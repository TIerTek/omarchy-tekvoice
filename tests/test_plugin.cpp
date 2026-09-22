#include <dlfcn.h>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <string>
#include <vector>
#include "../src/ladspa.h"
#include "pitch.h"

static const LADSPA_Descriptor *D = nullptr;

static void load() {
    void *h = dlopen("build/libtekvoice.so", RTLD_NOW);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); exit(1); }
    auto fn = (const LADSPA_Descriptor *(*)(unsigned long))dlsym(h, "ladspa_descriptor");
    assert(fn && "ladspa_descriptor not exported");
    D = fn(0);
    assert(D && "descriptor 0 missing");
}

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
    auto out = run_voice(in, 0, 0, 0, 0, 0, 0, 0, 0.f);
    for (size_t i = 0; i < in.size(); i++) assert(fabsf(out[i] - in[i]) < 1e-6f);
    printf("  ok bypass_is_bit_exact\n");
}

static void test_pitch_voice_shifts_fundamental() {
    std::vector<float> in(96000);
    for (size_t i = 0; i < in.size(); i++)
        in[i] = 0.5f * sinf(2.f * (float)M_PI * 150.f * i / 48000.f);
    auto out = run_voice(in, 7, 0, 0, 0, 0, 0, 0, 1.f);
    float hz = estimate_hz(out);
    float expect = 150.f * powf(2.f, 7.f / 12.f);
    printf("    pitched to %.1f Hz (expected %.1f)\n", hz, expect);
    assert(fabsf(hz - expect) / expect < 0.05f);
    printf("  ok pitch_voice_shifts_fundamental\n");
}

static void test_zero_latency_voice_has_no_shifter_delay() {
    std::vector<float> in(8192, 0.f); in[0] = 1.f;
    auto out = run_voice(in, 0, 0, 0, 0, 0, 55.f, 0, 1.f);
    int first = -1;
    for (size_t i = 0; i < out.size(); i++) if (fabsf(out[i]) > 1e-4f) { first = (int)i; break; }
    printf("    first energy at sample %d\n", first);
    assert(first >= 0 && first < 96);
    printf("  ok zero_latency_voice_has_no_shifter_delay\n");
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
    auto a = run_voice(in, 5, 2, 0.5f, 0.3f, 0.4f, 0, 0.3f, 1.f);
    auto b = run_voice(in, 5, 2, 0.5f, 0.3f, 0.4f, 0, 0.3f, 1.f);
    for (size_t i = 0; i < a.size(); i++) assert(a[i] == b[i]);
    printf("  ok is_deterministic\n");
}

static void test_block_size_invariance() {
    std::vector<float> in(98304);
    for (size_t i = 0; i < in.size(); i++)
        in[i] = 0.4f * sinf(2.f * (float)M_PI * 160.f * i / 48000.f);
    auto a = run_voice(in, 4, 0, 0, 0, 0, 0, 0, 1.f, 256);
    auto b = run_voice(in, 4, 0, 0, 0, 0, 0, 0, 1.f, 1024);
    float ha = estimate_hz(a), hb = estimate_hz(b);
    printf("    block 256 -> %.1f Hz, block 1024 -> %.1f Hz\n", ha, hb);
    assert(fabsf(ha - hb) < 4.f);
    printf("  ok block_size_invariance\n");
}

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);
    load();
    test_descriptor_shape();
    test_bypass_is_bit_exact();
    test_pitch_voice_shifts_fundamental();
    test_zero_latency_voice_has_no_shifter_delay();
    test_output_is_finite_and_unclipped();
    test_is_deterministic();
    test_block_size_invariance();
    printf("test_plugin: PASS\n");
    return 0;
}
