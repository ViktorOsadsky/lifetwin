#pragma once
// Step detection (HW-03). Pure C++ (no Arduino calls) so it can be host-tested.
// Input: calibrated acceleration magnitude in g, at IMU_HZ.
// Method: remove gravity/drift, low-pass, adaptive-threshold peak detection,
// >= 250 ms between peaks, and a 4-peak "walking confirmation" so isolated
// hand movements at a desk are not counted.
#include <stdint.h>
#include <math.h>

class OldStepDetector {
 public:
  void reset() { *this = OldStepDetector(); }

  // Returns the number of steps to ADD now: 0, 1, or 4 (when a walking
  // sequence is first confirmed, the 4 held candidates are released).
  uint8_t update(float mag_g, uint32_t t_ms) {
    float x = mag_g - 1.0f;
    if (!init_) { lp_ = x; base_ = x; init_ = true; }
    lp_ += kLpAlpha * (x - lp_);          // ~4 Hz low-pass
    base_ += kBaseAlpha * (lp_ - base_);  // ~0.3 Hz baseline
    float s = lp_ - base_;

    uint8_t add = 0;
    // local maximum at the previous sample
    if (p1_ > p2_ && p1_ >= s) add = onPeak(p1_, t_ms);
    p2_ = p1_;
    p1_ = s;

    if (lastPeakMs_ && (t_ms - lastPeakMs_) > 3000) env_ = 0;  // forget amplitude
    return add;
  }

 private:
  static constexpr float kLpAlpha = 0.334f;   // fs = 50 Hz, fc ~ 4 Hz
  static constexpr float kBaseAlpha = 0.0375f; // fs = 50 Hz, fc ~ 0.3 Hz
  static constexpr float kMinThr = 0.05f;     // g, absolute floor
  static constexpr uint32_t kMinGapMs = 250;
  static constexpr uint32_t kMaxGapMs = 2000;

  uint8_t onPeak(float h, uint32_t t) {
    float thr = fmaxf(kMinThr, 0.4f * env_);
    if (h < thr) return 0;
    if (lastPeakMs_ && (t - lastPeakMs_) < kMinGapMs) return 0;

    uint32_t gap = lastPeakMs_ ? (t - lastPeakMs_) : 0;
    lastPeakMs_ = t;
    env_ = (env_ == 0) ? h : (0.8f * env_ + 0.2f * h);

    if (gap == 0 || gap > kMaxGapMs) { cand_ = 1; avgGap_ = 0; return 0; }
    if (avgGap_ > 0 && (gap > 1.6f * avgGap_ || gap < 0.5f * avgGap_)) {
      cand_ = 1; avgGap_ = 0; return 0;
    }
    avgGap_ = (avgGap_ == 0) ? gap : (0.7f * avgGap_ + 0.3f * gap);
    cand_++;
    if (cand_ == 4) return 4;
    if (cand_ > 4) return 1;
    return 0;
  }

  bool init_ = false;
  float lp_ = 0, base_ = 0, p1_ = 0, p2_ = 0, env_ = 0, avgGap_ = 0;
  uint32_t lastPeakMs_ = 0;
  int cand_ = 0;
};
