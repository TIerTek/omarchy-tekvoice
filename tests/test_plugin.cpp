#include <dlfcn.h>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <string>
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

int main() {
    load();
    test_descriptor_shape();
    test_bypass_is_bit_exact();
    printf("test_plugin: PASS\n");
    return 0;
}
