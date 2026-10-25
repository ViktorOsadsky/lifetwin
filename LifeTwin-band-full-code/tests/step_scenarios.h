#pragma once
#ifndef STEP_HZ
#define STEP_HZ 3.5f
#endif
#ifndef TRANSIENT
#define TRANSIENT 1
#endif
inline int gFamily = 0;   // 0 smooth body bounce, 1 sharp heel strikes, 2 swing-dominated
#ifndef AMP_SCALE
#define AMP_SCALE 1.0f
#endif
// Realistic-ish thigh-pocket step scenarios for comparing step detectors.
// Each scenario returns the magnitude signal (g) at 50 Hz and the true number of steps.
#include <vector>
#include <random>
#include <cmath>
#include <string>
#include <functional>

struct Scenario { std::string name; std::vector<float> mag; int truth; bool seated; };

struct Gen {
  std::mt19937 rng; std::vector<float> sig; int truth = 0;
  explicit Gen(unsigned seed) : rng(seed) {}
  float g(float s) { return std::normal_distribution<float>(0, s)(rng); }
  float u(float a, float b) { return std::uniform_real_distribution<float>(a, b)(rng); }
  void ensure(size_t n) { if (sig.size() < n) sig.resize(n, 0.0f); }
  // one heel-strike transient (damped ~6 Hz burst) starting at time t seconds
  void impulse(float t, float amp) { amp *= AMP_SCALE;
    size_t i0 = (size_t)(t * 50); ensure(i0 + 30);
    for (int k = 0; k < 30; k++) { float tau = k / 50.0f;
#if TRANSIENT == 1
      float d = (tau - 0.05f) / 0.03f; sig[i0 + k] += amp * (expf(-d * d) - 0.25f * expf(-(tau - 0.14f) * (tau - 0.14f) / 0.0018f));   // one-sided pulse with a small undershoot
#else
      sig[i0 + k] += amp * expf(-tau / 0.08f) * sinf(2 * M_PI * STEP_HZ * tau);
#endif
    }
  }
  // a swing component at stride frequency over [t0, t1]
  void swing(float t0, float t1, float hz, float amp) {
    size_t a = (size_t)(t0 * 50), b = (size_t)(t1 * 50); ensure(b + 1); float ph = u(0, 6.28f);
    for (size_t i = a; i < b; i++) { float t = i / 50.0f, env = fminf(1.0f, fminf((t - t0) / 0.6f, (t1 - t) / 0.6f)); sig[i] += env * amp * sinf(2 * M_PI * hz * t + ph); }
  }
  // a walking bout: `steps` steps at step-frequency `hz`, transient amplitude `amp`, leg-ratio `alt`, timing jitter (fraction)
  // family 0: bounce-dominant   (smooth step-rate wave, small transient, small swing)
  // family 1: transient-dominant (sharp heel strikes, little bounce, medium swing)
  // family 2: swing-heavy       (big stride-rate swing under moderate bounce + transient)
  void hump(float tc, float T, float amp) { size_t a = (size_t)((tc - T / 2) * 50), b = (size_t)((tc + T / 2) * 50) + 1; ensure(b + 1);
    for (size_t i = a; i < b; i++) { float tau = i / 50.0f - tc; if (fabsf(tau) < T / 2) sig[i] += amp * 0.5f * (1 + cosf(2 * M_PI * tau / T)); } }
  float bout(float t0, int steps, float hz, float amp, float alt = 0.7f, float jitter = 0.07f, float swingFrac = -1) {
    const float B[3] = {1.0f, 0.3f, 0.5f}, A[3] = {0.35f, 1.0f, 0.5f}, S[3] = {0.3f, 0.5f, 1.0f};
    float t = t0; for (int k = 0; k < steps; k++) {
      float a = amp * ((k % 2) ? alt : 1.0f) * (1 + 0.15f * g(1.0f)); if (a < 0.002f) a = 0.002f;
      float T = (1.0f / hz) * (1 + jitter * g(1.0f));
      hump(t, T, B[gFamily] * a); impulse(t, A[gFamily] * a); t += T; }
    truth += steps; swing(t0, t, hz / 2, amp * S[gFamily]); return t;
  }
  float boutOld_unused(float t0, int steps, float hz, float amp, float alt = 0.7f, float jitter = 0.07f, float swingFrac = 0.3f) {
    float t = t0; for (int k = 0; k < steps; k++) {
      float a = amp * ((k % 2) ? alt : 1.0f) * (1 + 0.15f * g(1.0f)); if (a < 0.002f) a = 0.002f;
      impulse(t, a); t += (1.0f / hz) * (1 + jitter * g(1.0f)); }
    truth += steps; swing(t0, t, hz / 2, amp * swingFrac); return t;
  }
  Scenario finish(const std::string& name, float seconds, bool seated = false, float noise = 0.0025f) {
    ensure((size_t)(seconds * 50)); sig.resize((size_t)(seconds * 50));
    for (float& v : sig) v = 1.0f + v + g(noise);                  // magnitude near 1 g
    return {name, sig, truth, seated};
  }
};

// Builds all scenarios for one random seed.
inline std::vector<Scenario> makeScenarios(unsigned seed) {
  std::vector<Scenario> out;
  { Gen G(seed); G.bout(2, 100, 1.8f, 0.25f);               out.push_back(G.finish("normal walk, 100 steps", 70)); }
  { Gen G(seed); G.bout(2, 80, 1.3f, 0.15f);                out.push_back(G.finish("slow walk, 80 steps", 75)); }
  { Gen G(seed); G.bout(2, 150, 2.4f, 0.35f);               out.push_back(G.finish("fast walk, 150 steps", 75)); }
  { Gen G(seed); G.bout(2, 100, 1.6f, 0.06f, 0.8f);         out.push_back(G.finish("SMALL steps (0.06 g), 100", 75)); }
  { Gen G(seed); G.bout(2, 100, 1.6f, 0.035f, 0.8f);        out.push_back(G.finish("VERY small steps (0.035 g), 100", 75)); }
  { Gen G(seed); G.bout(2, 120, 1.8f, 0.2f, 0.45f);         out.push_back(G.finish("one leg much weaker (ratio 0.45), 120", 80)); }
  { Gen G(seed); float t = 2; int n[] = {5, 8, 3, 12, 6, 9, 4}; for (int s : n) { t = G.bout(t, s, G.u(1.4f, 2.0f), 0.2f, 0.7f, 0.2f) + G.u(1.5f, 3.0f); }
    out.push_back(G.finish("start/stop/turns: 7 bouts of 3-12 steps", t + 3)); }
  { Gen G(seed); float t = 2; for (int i = 0; i < 20; i++) t = G.bout(t, 4, 1.8f, 0.2f) + 4.0f;
    out.push_back(G.finish("walking around a room: 20 bouts of 4 steps", t)); }
  { Gen G(seed); float t = G.bout(2, 12, 1.8f, 0.2f); t = G.bout(t + 1.2f, 10, 1.4f, 0.12f, 0.6f, 0.25f); t = G.bout(t + 2.5f, 15, 2.1f, 0.3f);
    out.push_back(G.finish("mixed pace walk, 37 steps", t + 3)); }
  { Gen G(seed); for (float t = 1; t < 60; t += 1 / 2.6f) G.impulse(t, 0.05f * (1 + 0.2f * G.g(1.0f)));   // seated leg bounce, truth 0
    G.truth = 0; out.push_back(G.finish("SEATED leg bounce 2.6 Hz (truth 0)", 60, true)); }
  { Gen G(seed); float t = 5; while (t < 300) { for (int k = 0; k < 6; k++) G.impulse(t + k * 0.12f, 0.18f * expf(-k * 0.5f)); t += G.u(15, 40); }
    G.truth = 0; out.push_back(G.finish("SEATED desk fidgets, 5 min (truth 0)", 300, true)); }
  { Gen G(seed); for (int i = 0; i < 10; i++) { float t = 8 + i * 10; G.impulse(t, 0.35f); G.impulse(t + 0.5f, 0.3f); G.impulse(t + 1.1f, 0.2f); }   // sit/stand transitions (not steps)
    G.truth = 0; out.push_back(G.finish("10 stand-up / sit-down moves (truth 0)", 120, true)); }
  return out;
}
