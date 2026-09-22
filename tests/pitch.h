// Shared test helper: estimate the fundamental of a near-tonal buffer.
// Uses a windowed DFT magnitude scan rather than autocorrelation, which
// suffers octave errors on pure tones (every multiple of the period
// correlates equally well).
#ifndef TV_TEST_PITCH_H
#define TV_TEST_PITCH_H
#include <cmath>
#include <vector>

inline float estimate_hz(const std::vector<float> &v, float sr = 48000.f,
                         float lo = 60.f, float hi = 900.f) {
    // Analyse the steady-state second half so priming transients are excluded.
    size_t start = v.size() / 2, N = v.size() - start;
    if (N < 2048) { start = 0; N = v.size(); }
    std::vector<double> w(N);
    for (size_t i = 0; i < N; i++)
        w[i] = v[start + i] * (0.5 - 0.5 * cos(2.0 * M_PI * i / (N - 1)));  // Hann
    double bestMag = -1.0, bestHz = lo;
    for (double f = lo; f <= hi; f += 0.5) {
        double re = 0, im = 0, k = 2.0 * M_PI * f / sr;
        for (size_t i = 0; i < N; i++) { re += w[i] * cos(k * i); im += w[i] * sin(k * i); }
        double mag = re * re + im * im;
        if (mag > bestMag) { bestMag = mag; bestHz = f; }
    }
    return (float)bestHz;
}
#endif
