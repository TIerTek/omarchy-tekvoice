// TekVoice DSP primitives. Header-only, dependency-free, allocation-free
// after init(). SPDX-License-Identifier: GPL-3.0-or-later
#ifndef TV_DSP_H
#define TV_DSP_H

#include <cmath>
#include <cstdint>
#include <vector>

namespace tv {

// Direct-form-I biquad with double state, using the RBJ cookbook coefficients.
struct Biquad {
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;

    void reset() { x1 = x2 = y1 = y2 = 0; }
    void identity() { b0 = 1; b1 = b2 = a1 = a2 = 0; }

    void setNormalized(double B0, double B1, double B2, double A0, double A1, double A2) {
        b0 = B0 / A0; b1 = B1 / A0; b2 = B2 / A0; a1 = A1 / A0; a2 = A2 / A0;
    }

    void lowpass(float sr, float f, float q) {
        double w = 2.0 * M_PI * clampFreq(f, sr) / sr, c = cos(w), s = sin(w), al = s / (2.0 * q);
        setNormalized((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + al, -2 * c, 1 - al);
    }
    void highpass(float sr, float f, float q) {
        double w = 2.0 * M_PI * clampFreq(f, sr) / sr, c = cos(w), s = sin(w), al = s / (2.0 * q);
        setNormalized((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + al, -2 * c, 1 - al);
    }
    void peak(float sr, float f, float q, float gainDb) {
        double A = pow(10.0, gainDb / 40.0);
        double w = 2.0 * M_PI * clampFreq(f, sr) / sr, c = cos(w), s = sin(w), al = s / (2.0 * q);
        setNormalized(1 + al * A, -2 * c, 1 - al * A, 1 + al / A, -2 * c, 1 - al / A);
    }
    void lowshelf(float sr, float f, float gainDb) {
        double A = pow(10.0, gainDb / 40.0);
        double w = 2.0 * M_PI * clampFreq(f, sr) / sr, c = cos(w), s = sin(w);
        double al = s / 2.0 * sqrt((A + 1 / A) * (1 / 0.707 - 1) + 2);
        double sq = 2 * sqrt(A) * al;
        setNormalized(A * ((A + 1) - (A - 1) * c + sq), 2 * A * ((A - 1) - (A + 1) * c),
                      A * ((A + 1) - (A - 1) * c - sq), (A + 1) + (A - 1) * c + sq,
                      -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - sq);
    }

    float process(float x) {
        double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1; x1 = x; y2 = y1; y1 = y;
        // Flush denormals; they cost far more than the branch.
        if (!(fabs(y1) > 1e-18)) y1 = 0;
        if (!(fabs(y2) > 1e-18)) y2 = 0;
        return (float)y;
    }

private:
    static double clampFreq(float f, float sr) {
        double nyq = sr * 0.49;
        return f < 10.f ? 10.0 : (f > nyq ? nyq : (double)f);
    }
};

// tanh waveshaper, normalised so the transfer curve still maps 1 -> 1.
// Identity at drive == 0.
inline float shape(float x, float drive) {
    if (drive <= 0.f) return x;
    const float k = 1.f + 8.f * drive;
    return tanhf(x * k) / tanhf(k);
}

// Ring modulator. Identity when hz <= 0.
struct Ring {
    float inc = 0.f, phase = 0.f;
    bool on = false;
    void set(float sr, float hz) {
        on = hz > 0.f;
        inc = on ? 2.f * (float)M_PI * hz / sr : 0.f;
        if (!on) phase = 0.f;
    }
    void reset() { phase = 0.f; }
    float process(float x) {
        if (!on) return x;
        float m = cosf(phase);
        phase += inc;
        if (phase > 2.f * (float)M_PI) phase -= 2.f * (float)M_PI;
        return x * m;
    }
};

// Envelope-gated white noise: static only while there is signal.
// Deterministic — fixed-seed xorshift, so tests can compare runs bit for bit.
struct NoiseGate {
    uint32_t s = 0x9271u;
    float env = 0.f;
    void reset() { s = 0x9271u; env = 0.f; }
    float process(float x, float amount) {
        if (amount <= 0.f) return x;
        float a = fabsf(x);
        env += (a > env ? 0.01f : 0.0005f) * (a - env);
        s ^= s << 13; s ^= s >> 17; s ^= s << 5;
        float n = (float)(int32_t)s * (1.f / 2147483648.f);
        return x + n * amount * env * 2.f;
    }
};

// Fixed-capacity delay ring. Allocates only in init().
struct Delay {
    std::vector<float> buf;
    int mask = 0, w = 0, d = 0;
    void init(int maxSamples) {
        int n = 1;
        while (n < maxSamples + 1) n <<= 1;
        buf.assign(n, 0.f);
        mask = n - 1; w = 0; d = 0;
    }
    void reset() { std::fill(buf.begin(), buf.end(), 0.f); w = 0; }
    void setDelay(int samples) {
        if (samples < 0) samples = 0;
        if (samples > mask) samples = mask;
        d = samples;
    }
    float process(float x) {
        buf[w] = x;
        int r = (w - d) & mask;
        w = (w + 1) & mask;
        return buf[r];
    }
};

} // namespace tv
#endif
