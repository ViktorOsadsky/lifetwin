#pragma once
// Per-minute summaries, thigh-pocket posture, non-wear flags and the 24 h ring buffer.
// Pure C++ so it can be host-tested.
#include <stdint.h>
#include <string.h>
#include <math.h>
#include "config.h"

#pragma pack(push, 1)
struct MinuteRecord {          // 12 bytes, little-endian on the wire (format version 2)
  uint32_t ts;                 // unix seconds at minute close (seconds since boot if FLAG_TIME_UNSYNCED)
  uint8_t  steps;              // steps in the minute (clamped to 255)
  uint16_t enmo_mg10;          // mean ENMO in 0.1 milli-g units
  uint8_t  cls;                // 0 sedentary, 1 light, 2 moderate, 3 vigorous
  uint8_t  flags;              // see below
  uint16_t std_mg10;           // largest per-axis std-dev in the minute, 0.1 milli-g (for tuning non-wear)
  uint8_t  posture;            // 0 unknown, 1 sitting (thigh horizontal; lying looks the same), 2 upright, 3 other
};
#pragma pack(pop)
static_assert(sizeof(MinuteRecord) == 12, "minute record must be 12 bytes");

enum : uint8_t { CLS_SEDENTARY = 0, CLS_LIGHT = 1, CLS_MODERATE = 2, CLS_VIGOROUS = 3 };
enum : uint8_t { POSTURE_UNKNOWN = 0, POSTURE_SITTING = 1, POSTURE_UPRIGHT = 2, POSTURE_OTHER = 3 };
enum : uint8_t {
  FLAG_NONWEAR = 1,         // >= 30 consecutive still minutes (set from the 30th minute on)
  FLAG_STILL = 2,           // this minute had near-zero variance on all axes
  FLAG_MOTION = 4,          // an epoch exceeded MOTION_EPOCH_MG
  FLAG_NO_POSTURE_CAL = 8,  // posture references not captured yet: posture is unknown
  FLAG_TIME_UNSYNCED = 16   // ts is seconds since boot, not unix time
};

// Reference gravity directions in the sensor's own frame, captured while the
// person stands and while they sit with the band in the pocket. Learning them
// means it does not matter which way up the board sits in the pocket.
struct PostureRef {
  float stand[3] = {0, 0, 0};
  float sit[3] = {0, 0, 0};
  bool haveStand = false, haveSit = false;

  bool valid() const { return haveStand && haveSit; }
  static bool unitize(const float* in, float* out) {
    float n = sqrtf(in[0] * in[0] + in[1] * in[1] + in[2] * in[2]);
    if (n < 0.5f) return false;
    for (int i = 0; i < 3; i++) out[i] = in[i] / n;
    return true;
  }
  bool setStand(const float* v) { haveStand = unitize(v, stand); return haveStand; }
  bool setSit(const float* v) { haveSit = unitize(v, sit); return haveSit; }
  // The two directions must differ by at least 45 degrees or the capture is bad.
  bool separated() const {
    float d = stand[0] * sit[0] + stand[1] * sit[1] + stand[2] * sit[2];
    return d <= POSTURE_SEP_COS;
  }
  // Angle in degrees between the gravity direction (x,y,z) and a unit reference.
  static float angleDeg(const float* ref, float x, float y, float z) {
    float n = sqrtf(x * x + y * y + z * z);
    if (n < 0.5f) return 180.0f;
    float c = (x * ref[0] + y * ref[1] + z * ref[2]) / n;
    if (c > 1.0f) c = 1.0f;
    if (c < -1.0f) c = -1.0f;
    return acosf(c) * 57.29578f;
  }
  // Nearest-reference decision with hysteresis. x,y,z = mean calibrated acceleration (g).
  // prev = the previous answer; it makes the result stick near the 50/50 boundary.
  uint8_t classify(float x, float y, float z, uint8_t prev) const {
    if (!valid()) return POSTURE_UNKNOWN;
    if (sqrtf(x * x + y * y + z * z) < 0.5f) return POSTURE_UNKNOWN;
    float as = angleDeg(stand, x, y, z), ai = angleDeg(sit, x, y, z);
    if (as > POSTURE_OTHER_DEG && ai > POSTURE_OTHER_DEG) return POSTURE_OTHER;
    float d = as - ai;                       // negative = closer to standing
    if (prev == POSTURE_UPRIGHT) return d < POSTURE_MARGIN_DEG ? POSTURE_UPRIGHT : POSTURE_SITTING;
    if (prev == POSTURE_SITTING) return d > -POSTURE_MARGIN_DEG ? POSTURE_SITTING : POSTURE_UPRIGHT;
    return d < 0 ? POSTURE_UPRIGHT : POSTURE_SITTING;
  }
};

class MinuteAggregator {
 public:
  void setPostureRef(const PostureRef* r) { ref_ = r; }

  // Feed one CALIBRATED accelerometer sample (g).
  void addSample(float x, float y, float z) {
    float enmo = sqrtf(x * x + y * y + z * z) - 1.0f;
    if (enmo < 0) enmo = 0;
    epochSum_ += enmo * 1000.0f;
    ex_ += x; ey_ += y; ez_ += z;
    if (++epochN_ >= SAMPLES_PER_EPOCH) {
      float e = epochSum_ / epochN_;
      minSum_ += e; minEpochs_++;
      if (e > maxEpoch_) maxEpoch_ = e;
      uint8_t p = ref_ ? ref_->classify(ex_ / epochN_, ey_ / epochN_, ez_ / epochN_, lastEp_) : POSTURE_UNKNOWN;
      lastEp_ = p;
      pc_[p & 3]++;
      epochSum_ = 0; ex_ = ey_ = ez_ = 0; epochN_ = 0;
    }
    sx_ += x; sy_ += y; sz_ += z;
    qx_ += x * x; qy_ += y * y; qz_ += z * z;
    n_++;
  }
  void addSteps(uint16_t n) { steps_ += n; }
  uint16_t stepsSoFar() const { return steps_; }

  MinuteRecord close(uint32_t ts, bool synced) {
    MinuteRecord r;
    memset(&r, 0, sizeof r);
    r.ts = ts;
    r.steps = steps_ > 255 ? 255 : (uint8_t)steps_;
    float mean = minEpochs_ ? minSum_ / minEpochs_ : 0;
    r.enmo_mg10 = (uint16_t)fminf(mean * 10.0f, 65535.0f);

    // majority posture over the minute's 5 s epochs (ties go to the lower code)
    uint8_t best = POSTURE_UNKNOWN; int bestN = 0;
    for (uint8_t p = 1; p < 4; p++) if (pc_[p] > bestN) { bestN = pc_[p]; best = p; }
    r.posture = best;

    // Activity class: sitting with no stepping is sedentary; standing is light;
    // walking/running is graded by cadence (steps in the minute).
    if (r.steps >= CADENCE_VIGOROUS) r.cls = CLS_VIGOROUS;
    else if (r.steps >= CADENCE_MODERATE) r.cls = CLS_MODERATE;
    else if (r.steps > 0 || best == POSTURE_UPRIGHT) r.cls = CLS_LIGHT;
    else r.cls = CLS_SEDENTARY;

    float sd = 0;
    if (n_ > 1) sd = fmaxf(fmaxf(std_(sx_, qx_), std_(sy_, qy_)), std_(sz_, qz_)) * 1000.0f;
    r.std_mg10 = (uint16_t)fminf(sd * 10.0f, 65535.0f);
    bool still = (n_ > 0) && sd < NONWEAR_STD_MG;
    stillRun_ = still ? stillRun_ + 1 : 0;

    uint8_t f = 0;
    if (still) f |= FLAG_STILL;
    if (stillRun_ >= NONWEAR_MIN_MINUTES) f |= FLAG_NONWEAR;
    if (maxEpoch_ > MOTION_EPOCH_MG) f |= FLAG_MOTION;
    if (!ref_ || !ref_->valid()) f |= FLAG_NO_POSTURE_CAL;
    if (!synced) f |= FLAG_TIME_UNSYNCED;
    r.flags = f;

    // reset minute accumulators (epoch accumulators carry over)
    steps_ = 0; minSum_ = 0; minEpochs_ = 0; maxEpoch_ = 0; n_ = 0;
    sx_ = sy_ = sz_ = qx_ = qy_ = qz_ = 0;
    for (int i = 0; i < 4; i++) pc_[i] = 0;
    return r;
  }
  int stillRun() const { return stillRun_; }

 private:
  float std_(double s, double q) const {
    double m = s / n_;
    double v = q / n_ - m * m;
    return v > 0 ? (float)sqrt(v) : 0.0f;
  }
  const PostureRef* ref_ = nullptr;
  double sx_ = 0, sy_ = 0, sz_ = 0, qx_ = 0, qy_ = 0, qz_ = 0;
  float epochSum_ = 0, minSum_ = 0, maxEpoch_ = 0, ex_ = 0, ey_ = 0, ez_ = 0;
  int epochN_ = 0, minEpochs_ = 0, n_ = 0, stillRun_ = 0;
  int pc_[4] = {0, 0, 0, 0};
  uint8_t lastEp_ = POSTURE_UNKNOWN;
  uint16_t steps_ = 0;
};

// Running timers for live testing: seconds spent sitting / standing / other, and steps,
// since the last reset. "Standing" includes walking (the thigh is vertical either way).
struct SessionTotals {
  uint32_t sit = 0, stand = 0, other = 0, steps = 0, runSec = 0;
  uint8_t runPosture = POSTURE_UNKNOWN;     // posture of the current stretch, and how long it has lasted
  void tickSecond(uint8_t posture) {
    if (posture == POSTURE_SITTING) sit++;
    else if (posture == POSTURE_UPRIGHT) stand++;
    else if (posture == POSTURE_OTHER) other++;
    if (posture == runPosture) runSec++; else { runPosture = posture; runSec = 1; }
  }
  void addSteps(uint32_t n) { steps += n; }
  void reset() { *this = SessionTotals(); }
};

class RingBuffer {
 public:
  void push(const MinuteRecord& r) {
    buf_[head_] = r;
    head_ = (head_ + 1) % RING_MINUTES;
    if (count_ < RING_MINUTES) count_++;
  }
  uint16_t size() const { return count_; }
  // i = 0 is the OLDEST record
  const MinuteRecord& at(uint16_t i) const {
    uint16_t start = (head_ + RING_MINUTES - count_) % RING_MINUTES;
    return buf_[(start + i) % RING_MINUTES];
  }
  // When the app sends unix time, convert boot-relative records to unix time.
  void rebaseUnsynced(uint32_t offsetSeconds) {
    for (uint16_t i = 0; i < count_; i++) {
      uint16_t start = (head_ + RING_MINUTES - count_) % RING_MINUTES;
      MinuteRecord& r = buf_[(start + i) % RING_MINUTES];
      if (r.flags & FLAG_TIME_UNSYNCED) {
        r.ts += offsetSeconds;
        r.flags &= (uint8_t)~FLAG_TIME_UNSYNCED;
      }
    }
  }
 private:
  MinuteRecord buf_[RING_MINUTES];
  uint16_t head_ = 0, count_ = 0;
};
