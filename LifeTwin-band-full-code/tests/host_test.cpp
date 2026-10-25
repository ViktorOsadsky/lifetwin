// Host test for the pure-C++ parts. Build:  g++ -std=c++17 -O1 -I../lifetwin_band host_test.cpp -o host_test
#include <cstdio>
#include <cstdlib>
#include <random>
#include <array>
#include "steps.h"
#include "minute.h"

static std::mt19937 rng(42);
static float gauss(float s) { return std::normal_distribution<float>(0, s)(rng); }
static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); fails++; } else { printf("ok:   "); printf(__VA_ARGS__); printf("\n"); } } while (0)

#include "step_scenarios.h"
// total steps counted by the detector over a scenario (gate = posture allows counting)
static int countSteps(const Scenario& s, bool gate, uint8_t sens = 3, int* firstAtStep = nullptr) {
  StepDetector d; d.setSensitivity(sens); int total = 0;
  for (size_t i = 0; i < s.mag.size(); i++) { int a = d.update(s.mag[i], (uint32_t)(i * 20), gate); if (a && total == 0 && firstAtStep) *firstAtStep = a; total += a; }
  return total;
}
static float meanCount(const std::string& name, int family, bool gate, uint8_t sens = 3, int seeds = 12) {
  gFamily = family; float sum = 0; int truth = 0;
  for (unsigned seed = 1; seed <= (unsigned)seeds; seed++) for (auto& s : makeScenarios(seed)) if (s.name == name) { sum += countSteps(s, gate, sens); truth = s.truth; }
  (void)truth; return sum / seeds;
}
static int truthOf(const std::string& name) { gFamily = 0; for (auto& s : makeScenarios(1)) if (s.name == name) return s.truth; return -1; }

static void feed(MinuteAggregator& a, float x, float y, float z, int seconds, float noise = 0.004f) {
  for (int i = 0; i < seconds * IMU_HZ; i++) a.addSample(x + gauss(noise), y + gauss(noise), z + gauss(noise));
}
typedef std::array<float, 3> V3;
// A thigh sensor at an arbitrary rotation M in the pocket: gravity in the thigh's own frame is
// "along the leg" (standing) or "out of the front of the thigh" (sitting, thigh horizontal).
struct Pocket {
  float M[3][3];
  explicit Pocket(unsigned seed) {
    std::mt19937 g(seed); std::uniform_real_distribution<float> U(-1, 1);
    float ax[3] = {U(g), U(g), U(g)}; float n = sqrtf(ax[0]*ax[0]+ax[1]*ax[1]+ax[2]*ax[2]); for (float& a : ax) a /= n;
    float ang = (U(g) + 1) * M_PI, c = cosf(ang), s = sinf(ang), t = 1 - c;
    float R[3][3] = {{t*ax[0]*ax[0]+c, t*ax[0]*ax[1]-s*ax[2], t*ax[0]*ax[2]+s*ax[1]},
                     {t*ax[0]*ax[1]+s*ax[2], t*ax[1]*ax[1]+c, t*ax[1]*ax[2]-s*ax[0]},
                     {t*ax[0]*ax[2]-s*ax[1], t*ax[1]*ax[2]+s*ax[0], t*ax[2]*ax[2]+c}};
    memcpy(M, R, sizeof M);
  }
  // leg angle from vertical in degrees: 0 = standing, 90 = thigh horizontal (sitting)
  V3 at(float legDeg, float noise = 0.004f) const {
    float t = legDeg * M_PI / 180; float b[3] = {sinf(t), 0, cosf(t)}; V3 o{};
    for (int i = 0; i < 3; i++) o[i] = M[i][0]*b[0] + M[i][1]*b[1] + M[i][2]*b[2] + gauss(noise);
    return o;
  }
};
static PostureRef makeRef(const Pocket& p) { PostureRef r; V3 a = p.at(0, 0), b = p.at(90, 0); r.setStand(a.data()); r.setSit(b.data()); return r; }

int main() {
  // ---- steps: tougher scenarios, measured limits (12 random runs each, mean count vs truth) ----
  // These tolerances record what the detector does on MY simulated signals; real legs may differ.
  struct { const char* name; float tol; } smooth[] = {
    {"normal walk, 100 steps", 0.03f}, {"slow walk, 80 steps", 0.03f}, {"fast walk, 150 steps", 0.03f},
    {"SMALL steps (0.06 g), 100", 0.08f}, {"VERY small steps (0.035 g), 100", 0.25f},
    {"one leg much weaker (ratio 0.45), 120", 0.10f}, {"start/stop/turns: 7 bouts of 3-12 steps", 0.15f},
    {"walking around a room: 20 bouts of 4 steps", 0.25f}, {"mixed pace walk, 37 steps", 0.10f}};
  for (auto& k : smooth) { int tr = truthOf(k.name); float m = meanCount(k.name, 0, true); float e = fabsf(m - tr) / tr;
    CHECK(e <= k.tol, "smooth-bounce signal, %s: mean %.1f (error %.0f%%, limit %.0f%%)", k.name, m, 100 * e, 100 * k.tol); }
  { float m = meanCount("normal walk, 100 steps", 1, true); CHECK(m >= 60 && m <= 110, "sharp-heel-strike signal, normal walk: mean %.1f of 100 (known weaker: can fall back to counting strides)", m); }
  { int tr = truthOf("SMALL steps (0.06 g), 100"); CHECK(meanCount("SMALL steps (0.06 g), 100", 1, true) >= 0.6f * tr, "sharp-heel-strike signal, small steps: mean %.1f of 100", meanCount("SMALL steps (0.06 g), 100", 1, true)); }
  { float lo = meanCount("VERY small steps (0.035 g), 100", 0, true, 1), mid = meanCount("VERY small steps (0.035 g), 100", 0, true, 3), hi = meanCount("VERY small steps (0.035 g), 100", 0, true, 5);
    CHECK(lo <= mid && mid <= hi && hi > lo, "sensitivity works: very small steps counted %.0f / %.0f / %.0f at sensitivity 1 / 3 / 5", lo, mid, hi); }
  { gFamily = 0; int first = 0; for (auto& s : makeScenarios(2)) if (s.name == "normal walk, 100 steps") countSteps(s, true, 3, &first);
    CHECK(first == 3, "confirmation lag: the first steps are counted at the 3rd step (was the 4th)"); }
  { float closed = meanCount("SEATED leg bounce 2.6 Hz (truth 0)", 0, false), open = meanCount("SEATED leg bounce 2.6 Hz (truth 0)", 0, true);
    CHECK(closed == 0, "while sitting (gate closed): seated leg bounce counts %.0f steps", closed);
    CHECK(open > 20, "without the sitting rule, seated leg bounce would count %.0f false steps a minute (why the rule exists)", open); }
  CHECK(meanCount("SEATED desk fidgets, 5 min (truth 0)", 0, true) <= 1, "5 min of desk fidgets, even with the gate open: %.1f false steps", meanCount("SEATED desk fidgets, 5 min (truth 0)", 0, true));
  { float m = meanCount("10 stand-up / sit-down moves (truth 0)", 0, true); printf("      (note: 10 simulated stand-up/sit-down moves with the gate open count %.0f false steps: about 3 per move)\n", m); }
  CHECK(sizeof(MinuteRecord) == 12, "minute record is 12 bytes");

  // ---- posture: any board orientation in the pocket ----
  { int bad = 0, total = 0;
    for (unsigned seed = 1; seed <= 20; seed++) {
      Pocket p(seed); PostureRef ref = makeRef(p);
      if (!ref.valid() || !ref.separated()) { bad++; continue; }
      struct { float leg; uint8_t want; } cs[] = {{0, POSTURE_UPRIGHT}, {15, POSTURE_UPRIGHT}, {30, POSTURE_UPRIGHT}, {60, POSTURE_SITTING}, {75, POSTURE_SITTING}, {90, POSTURE_SITTING}};
      for (auto& k : cs) { total++; V3 v = p.at(k.leg); if (ref.classify(v[0], v[1], v[2], POSTURE_UNKNOWN) != k.want) bad++; }
    }
    CHECK(bad == 0, "standing/sitting at 6 leg angles x 20 random board rotations: %d wrong of %d", bad, total); }
  { PostureRef bad; float a[3] = {0, 1, 0}, b[3] = {0, 0.94f, 0.34f}; bad.setStand(a); bad.setSit(b);
    CHECK(!bad.separated(), "references only ~20 deg apart are rejected"); }
  { Pocket p(3); PostureRef r = makeRef(p); V3 v = p.at(0, 0);
    // sideways: gravity perpendicular to both the leg axis and the thigh-front axis
    float side[3] = {p.M[0][1], p.M[1][1], p.M[2][1]};
    CHECK(r.classify(side[0], side[1], side[2], POSTURE_UNKNOWN) == POSTURE_OTHER, "sideways (90 deg from both) -> other"); (void)v; }

  // ---- hysteresis and flicker ----
  {
    Pocket p(11); PostureRef r = makeRef(p);
    auto at = [&](float deg, uint8_t prev) { V3 v = p.at(deg, 0); return r.classify(v[0], v[1], v[2], prev); };
    CHECK(at(42, POSTURE_UPRIGHT) == POSTURE_UPRIGHT && at(48, POSTURE_SITTING) == POSTURE_SITTING, "near the 50/50 boundary the previous answer sticks");
    CHECK(at(60, POSTURE_UPRIGHT) == POSTURE_SITTING && at(30, POSTURE_SITTING) == POSTURE_UPRIGHT, "clearly past the boundary it switches");
    int fh = 0, fp = 0; uint8_t pv = POSTURE_SITTING, pp = POSTURE_SITTING;
    for (int i = 0; i < 2000; i++) { float d = 45 + gauss(4.0f);
      uint8_t a = at(d, pv); if (a != pv) fh++; pv = a; uint8_t b = at(d, POSTURE_UNKNOWN); if (b != pp) fp++; pp = b; }
    printf("      (flips in 2000 samples jittering on the boundary: with hysteresis %d, without %d)\n", fh, fp);
    CHECK(fh * 2 < fp, "hysteresis cuts boundary flicker by more than half");
  }

  // ---- per-minute record ----
  Pocket pk(5); PostureRef ref = makeRef(pk);
  { MinuteAggregator a; a.setPostureRef(&ref); V3 v = pk.at(0, 0); feed(a, v[0], v[1], v[2], 60);
    MinuteRecord r = a.close(1000, true); CHECK(r.posture == POSTURE_UPRIGHT && r.cls == CLS_LIGHT, "standing still -> upright, light"); }
  { MinuteAggregator a; a.setPostureRef(&ref); V3 v = pk.at(90, 0); feed(a, v[0], v[1], v[2], 60);
    MinuteRecord r = a.close(1060, true); CHECK(r.posture == POSTURE_SITTING && r.cls == CLS_SEDENTARY && !(r.flags & FLAG_NO_POSTURE_CAL), "sitting still -> sitting, sedentary"); }
  { MinuteAggregator a; a.setPostureRef(&ref); V3 s = pk.at(0, 0), q = pk.at(90, 0);
    feed(a, s[0], s[1], s[2], 40); feed(a, q[0], q[1], q[2], 20);
    CHECK(a.close(1120, true).posture == POSTURE_UPRIGHT, "40 s standing + 20 s sitting -> majority upright"); }
  { MinuteAggregator a; V3 q = pk.at(90, 0); feed(a, q[0], q[1], q[2], 60); MinuteRecord r = a.close(1180, true);
    CHECK(r.posture == POSTURE_UNKNOWN && (r.flags & FLAG_NO_POSTURE_CAL), "no references -> unknown + NO_POSTURE_CAL flag"); }
  struct { int steps; uint8_t want; const char* name; } cases[] = {{0, CLS_SEDENTARY, "0 steps seated"}, {40, CLS_LIGHT, "40 steps/min"}, {99, CLS_LIGHT, "99 steps/min"},
    {100, CLS_MODERATE, "100 steps/min"}, {129, CLS_MODERATE, "129 steps/min"}, {135, CLS_VIGOROUS, "135 steps/min"}};
  for (auto& k : cases) { MinuteAggregator a; a.setPostureRef(&ref); V3 q = pk.at(90, 0); feed(a, q[0], q[1], q[2], 60); a.addSteps(k.steps);
    MinuteRecord r = a.close(2000, true); CHECK(r.cls == k.want, "%s -> class %u (want %u)", k.name, r.cls, k.want); }

  // ---- live timers ----
  {
    SessionTotals t;
    for (int i = 0; i < 90; i++) t.tickSecond(POSTURE_SITTING);
    for (int i = 0; i < 40; i++) t.tickSecond(POSTURE_UPRIGHT);
    for (int i = 0; i < 5; i++) t.tickSecond(POSTURE_OTHER);
    t.addSteps(4); t.addSteps(1);
    CHECK(t.sit == 90 && t.stand == 40 && t.other == 5 && t.steps == 5, "timers add up: 90 s sitting, 40 s standing, 5 s other, 5 steps");
    CHECK(t.runPosture == POSTURE_OTHER && t.runSec == 5, "current stretch: other for 5 s");
    t.tickSecond(POSTURE_UNKNOWN); t.tickSecond(POSTURE_UNKNOWN);
    CHECK(t.sit + t.stand + t.other == 135 && t.runPosture == POSTURE_UNKNOWN && t.runSec == 2, "unknown posture is not counted as sitting or standing");
    t.reset();
    CHECK(t.sit == 0 && t.stand == 0 && t.steps == 0 && t.runSec == 0, "reset clears every timer");
  }

  // ---- non-wear ----
  {
    MinuteAggregator a; RingBuffer r;
    for (int m = 0; m < 35; m++) { feed(a, 0.0f, 0.0f, 1.0f, 60, 0.002f); r.push(a.close(1000 + m * 60, true)); }
    CHECK((r.at(0).flags & FLAG_STILL) != 0, "still minute flagged STILL (std=%.1f mg)", r.at(0).std_mg10 / 10.0);
    CHECK(!(r.at(28).flags & FLAG_NONWEAR) && (r.at(29).flags & FLAG_NONWEAR), "NONWEAR from the 30th still minute");
  }
  {
    MinuteAggregator a;
    for (int i = 0; i < 60 * IMU_HZ; i++) { float tt = i / (float)IMU_HZ; a.addSample(0.3f * sinf(2 * M_PI * 2 * tt), 0.2f * sinf(2 * M_PI * 2 * tt + 1), 1.0f + 0.3f * sinf(2 * M_PI * 2 * tt)); }
    MinuteRecord rec = a.close(5000, true);
    CHECK(!(rec.flags & FLAG_STILL) && (rec.flags & FLAG_MOTION), "moving minute -> not still, motion flagged");
  }
  {
    static RingBuffer r;
    for (int i = 0; i < RING_MINUTES + 10; i++) { MinuteRecord x{}; x.ts = i; x.flags = FLAG_TIME_UNSYNCED; r.push(x); }
    CHECK(r.size() == RING_MINUTES && r.at(0).ts == 10, "ring keeps newest %d minutes", RING_MINUTES);
    r.rebaseUnsynced(1700000000);
    CHECK(r.at(0).ts == 1700000010 && !(r.at(0).flags & FLAG_TIME_UNSYNCED), "rebase unsynced timestamps to unix time");
  }
  printf("\n%s\n", fails ? "SOME TESTS FAILED" : "ALL TESTS PASSED");
  return fails ? 1 : 0;
}
