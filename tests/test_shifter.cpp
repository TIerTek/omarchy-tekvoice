#include "../src/shifter.h"
#include <cassert>
#include <cstdio>
#include <cmath>
#include <vector>
#include "pitch.h"
using namespace tv;

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
    struct { float st; float expect; } cases[] = {
        {0.f, 150.f}, {7.f, 150.f * powf(2.f, 7.f/12.f)}, {-5.f, 150.f * powf(2.f, -5.f/12.f)}};
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
    assert(lat > 0 && lat < 48000 * 70 / 1000);
    printf("  ok latency_under_budget\n");
}

int main() {
    setvbuf(stdout, nullptr, _IONBF, 0);
    test_writes_every_block_size();
    test_pitch_ratio_is_correct();
    test_latency_under_budget();
    printf("test_shifter: PASS\n");
    return 0;
}
