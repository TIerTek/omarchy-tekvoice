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

static void test_highpass_attenuates_below_cutoff() {
    Biquad b; b.highpass(48000.f, 2000.f, 0.707f);
    auto lo = sine(100.f, 4800);
    std::vector<float> out;
    for (float x : lo) out.push_back(b.process(x));
    std::vector<float> tail(out.end() - 2400, out.end());
    assert(rms(tail) < 0.1f * rms(lo));
    printf("  ok highpass_attenuates_below_cutoff\n");
}

static void test_shape_is_identity_at_zero_drive() {
    for (float x = -1.f; x <= 1.f; x += 0.05f) assert(fabsf(shape(x, 0.f) - x) < 1e-6f);
    printf("  ok shape_is_identity_at_zero_drive\n");
}

static void test_shape_compresses_peaks() {
    assert(fabsf(shape(1.0f, 1.0f)) <= 1.0f + 1e-6f);
    assert(fabsf(shape(0.9f, 1.0f)) > fabsf(shape(0.2f, 1.0f)));
    // A loud sample must gain less than a quiet one: that is compression.
    assert(shape(0.9f, 1.0f) / 0.9f < shape(0.2f, 1.0f) / 0.2f);
    printf("  ok shape_compresses_peaks\n");
}

static void test_ring_is_identity_when_disabled() {
    Ring r; r.set(48000.f, 0.f);
    auto s = sine(300.f, 512);
    for (float x : s) assert(fabsf(r.process(x) - x) < 1e-6f);
    printf("  ok ring_is_identity_when_disabled\n");
}

static void test_ring_suppresses_the_carrier() {
    Ring r; r.set(48000.f, 100.f);
    auto s = sine(300.f, 48000);
    std::vector<float> out; for (float x : s) out.push_back(r.process(x));
    double acc = 0;
    for (int i = 0; i < 48000; i++) acc += out[i] * sin(2.0 * M_PI * 300.0 * i / 48000.0);
    assert(fabs(acc / 48000.0) < 0.3);
    printf("  ok ring_suppresses_the_carrier\n");
}

static void test_noise_is_identity_at_zero() {
    NoiseGate g; auto s = sine(300.f, 512);
    for (float x : s) assert(fabsf(g.process(x, 0.f) - x) < 1e-6f);
    printf("  ok noise_is_identity_at_zero\n");
}

static void test_noise_only_appears_with_signal() {
    NoiseGate g; g.reset();
    std::vector<float> silence(4800, 0.f);
    float peak = 0.f;
    for (float x : silence) peak = fmaxf(peak, fabsf(g.process(x, 1.0f)));
    assert(peak < 1e-3f && "noise must be gated by the input envelope");
    printf("  ok noise_only_appears_with_signal\n");
}

static void test_noise_is_deterministic() {
    NoiseGate a, b; a.reset(); b.reset();
    auto s = sine(300.f, 2048);
    for (float x : s) assert(a.process(x, 0.5f) == b.process(x, 0.5f));
    printf("  ok noise_is_deterministic\n");
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
    test_highpass_attenuates_below_cutoff();
    test_shape_is_identity_at_zero_drive();
    test_shape_compresses_peaks();
    test_ring_is_identity_when_disabled();
    test_ring_suppresses_the_carrier();
    test_noise_is_identity_at_zero();
    test_noise_only_appears_with_signal();
    test_noise_is_deterministic();
    test_delay_delays_exactly();
    printf("test_dsp: PASS\n");
    return 0;
}
