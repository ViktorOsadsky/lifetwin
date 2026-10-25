#pragma once
// Step detection for a thigh-pocket sensor. Pure C++ so it can be host-tested.
// Input: calibrated acceleration magnitude in g at IMU_HZ, plus a gate.
//
// Method: band-limit the magnitude, find peaks, and judge each peak by its PROMINENCE (rise above the
// lowest point since the previous step) rather than its height, so small steps riding on the thigh's
// slow swing still count. Peaks are accepted only if they are plausible in size and timing; a walk
// is confirmed after 3 regular steps (those 3 are then released), and after that every step counts at
// once, short gaps and single odd intervals do not restart the confirmation, and a missed alternate
// step is filled in. While the gate is closed (e.g. seated) nothing counts and any partial walk is dropped.
#include <stdint.h>
#include <math.h>

class StepDetector {
 public:
  void reset() { *this = StepDetector(); }

  // Sensitivity 1 (least) .. 5 (most): the smallest step size in g, measured as peak prominence.
  void setSensitivity(uint8_t level) {
    static const float thr[5] = {0.060f, 0.040f, 0.025f, 0.016f, 0.010f};
    if (level < 1) level = 1;
    if (level > 5) level = 5;
    minThr_ = thr[level - 1];
  }

  // Returns the number of steps to ADD now (0, 1, 2, or 3 when a walk is first confirmed).
  uint8_t update(float mag_g, uint32_t t_ms, bool gate = true) {
    float x = mag_g - 1.0f;
    if (!init_) { l1_ = l2_ = base_ = x; init_ = true; }
    l1_ += kLp * (x - l1_);                 // two cascaded low-pass stages, about 4 Hz overall
    l2_ += kLp * (l1_ - l2_);
    base_ += kBase * (l2_ - base_);         // slow baseline (about 0.3 Hz) removed
    float s = l2_ - base_;

    uint8_t add = 0;
    bool isPeak = (p1_ > p2_ && p1_ >= s);   // local maximum at the previous sample
    if (isPeak) {
      acc_ = false;
      if (gate) add = onPeak(p1_ - minSince_, t_ms);
      if (acc_) minSince_ = s;               // restart the trough search only after an accepted step
    }
    if (s < minSince_) minSince_ = s;
    p2_ = p1_; p1_ = s;

    if (!gate) { cand_ = 0; walking_ = false; lastPeak_ = 0; avgGap_ = 0; env_ = 0; }
    else if (lastPeak_ && (t_ms - lastPeak_) > 3000) env_ = 0;
    return add;
  }

  bool walking() const { return walking_; }

 private:
  static constexpr float kLp = 0.43f;        // 50 Hz, about 6 Hz per stage
  static constexpr float kBase = 0.0375f;       // about 0.3 Hz baseline removal
  static constexpr uint8_t kConfirm = 3;

  uint8_t onPeak(float prom, uint32_t t) {
    float thr = fmaxf(minThr_, 0.35f * env_);   // also at least 35% of the recent typical step size
    if (prom < thr) return 0;
    uint32_t gap = lastPeak_ ? t - lastPeak_ : 0;
    float minGap = 220.0f;
    if (avgGap_ > 0) minGap = fmaxf(220.0f, 0.55f * avgGap_);   // a second bump inside one step is ignored
    if (lastPeak_ && gap < minGap) return 0;

    acc_ = true;
    env_ = (env_ == 0) ? prom : 0.75f * env_ + 0.25f * prom;
    lastPeak_ = t;

    uint32_t maxGap = walking_ ? 3000 : 2000;
    if (gap == 0 || gap > maxGap) { cand_ = 1; walking_ = false; avgGap_ = 0; return 0; }   // new bout

    if (avgGap_ > 0) {
      float ratio = gap / avgGap_;
      if (!walking_) {
        if (ratio > 1.6f || ratio < 0.55f) { cand_ = 1; avgGap_ = 0; return 0; }              // not regular yet
      } else if (ratio > 1.7f) {
        return (ratio < 2.4f) ? 2 : 1;       // about 2 intervals: a step in between was too small to see
      }
    }
    avgGap_ = (avgGap_ == 0) ? (float)gap : 0.75f * avgGap_ + 0.25f * gap;
    cand_++;
    if (!walking_) {
      if (cand_ >= kConfirm) { walking_ = true; return kConfirm; }
      return 0;
    }
    return 1;
  }

  bool init_ = false, acc_ = false, walking_ = false;
  float minThr_ = 0.025f;
  float l1_ = 0, l2_ = 0, base_ = 0, p1_ = 0, p2_ = 0, minSince_ = 0, env_ = 0, avgGap_ = 0;
  uint32_t lastPeak_ = 0;
  uint8_t cand_ = 0;
};
