struct MinuteRecord;   // forward declarations: the Arduino IDE inserts function prototypes
struct PostureRef;     // above the type definitions, so the names must already exist
struct DayAgg;
class RingBuffer;

// LifeTwin band firmware v0.8 - SINGLE-FILE VERSION (thigh pocket, ESP32 + MPU-6050)
// Paste this whole file into the Arduino sketch. Only library needed: NimBLE-Arduino (>= 2.0).
// Board: ESP32S3 Dev Module (or ESP32C3 Dev Module) with USB CDC On Boot: Enabled.

// ======== config.h ========
#include <stdint.h>

// ---- Firmware identity -------------------------------------------------
#define FW_MAJOR 0
#define FW_MINOR 8
#define FORMAT_VERSION 2          // v2: thigh-pocket posture codes (v3 was the chest build)

// ---- Pins (ESP32-S3/C3 default I2C pair; matches the G8/G9 wiring) -----
#define PIN_SDA 8
#define PIN_SCL 9

// ---- Motion sensor -----------------------------------------------------
#define MPU_ADDR 0x68             // 0x69 if the AD0 pin is pulled high
#define IMU_HZ 50
#define IMU_PERIOD_US (1000000UL / IMU_HZ)
#define ACCEL_LSB_PER_G 8192.0f   // +/-4 g range

// ---- Aggregation -------------------------------------------------------
#define EPOCH_S 5
#define SAMPLES_PER_EPOCH (IMU_HZ * EPOCH_S)
#define RING_MINUTES 1440         // 24 h * 12 bytes = 17,280 bytes

// ---- Activity class from walking cadence (steps in the minute) ----------
// PROVISIONAL, from memory of walking-cadence literature (about 100 steps/min
// ~ moderate, about 130 steps/min ~ vigorous). Verify against a primary source
// (e.g. Tudor-Locke et al., CADENCE-Adults) before showing intensity to anyone.
constexpr uint8_t CADENCE_MODERATE = 100;
constexpr uint8_t CADENCE_VIGOROUS = 130;

// ---- Posture (thigh pocket) -------------------------------------------
constexpr float POSTURE_OTHER_DEG  = 55.0f; // farther than this from BOTH references => "other"
constexpr float POSTURE_MARGIN_DEG = 8.0f;  // hysteresis: must be clearly closer to the other reference to switch
constexpr float POSTURE_SEP_COS    = 0.707f; // stand and sit references must be >= 45 degrees apart
constexpr uint32_t POSTURE_DEBOUNCE_MS = 600; // a new live posture must hold this long before it is reported

// ---- Motion / non-wear ---------------------------------------------------
constexpr float MOTION_EPOCH_MG   = 40.0f; // any epoch above this => FLAG_MOTION
constexpr float NONWEAR_STD_MG    = 8.0f;  // per-axis std below this => "still" minute (TUNE)
constexpr int   NONWEAR_MIN_MINUTES = 30;  // still this long => non-wear

// ======== mpu6050.h ========
// Minimal MPU-6050 accelerometer driver (no external library). HW-01.
#include <Wire.h>

class Mpu6050 {
 public:
  bool begin(uint8_t addr = MPU_ADDR) {
    addr_ = addr;
    Wire.beginTransmission(addr_);
    if (Wire.endTransmission() != 0) return false;
    if (whoAmI() != 0x68) { /* clones may report other IDs; keep going */ }
    write(0x6B, 0x01);   // PWR_MGMT_1: wake, clock = gyro X PLL
    delay(100);
    write(0x1C, 0x08);   // ACCEL_CONFIG: +/-4 g
    write(0x1A, 0x04);   // CONFIG: digital low-pass ~21 Hz
    write(0x19, 19);     // SMPLRT_DIV: 1 kHz / (1+19) = 50 Hz
    return true;
  }
  uint8_t whoAmI() { return read8(0x75); }

  // Raw counts. Returns false on an I2C error.
  bool readRaw(int16_t& x, int16_t& y, int16_t& z) {
    Wire.beginTransmission(addr_);
    Wire.write(0x3B);
    if (Wire.endTransmission(false) != 0) return false;
    if (Wire.requestFrom((int)addr_, 6) != 6) return false;
    uint8_t b[6];
    for (int i = 0; i < 6; i++) b[i] = Wire.read();
    x = (int16_t)((b[0] << 8) | b[1]);
    y = (int16_t)((b[2] << 8) | b[3]);
    z = (int16_t)((b[4] << 8) | b[5]);
    return true;
  }
 private:
  void write(uint8_t reg, uint8_t v) {
    Wire.beginTransmission(addr_); Wire.write(reg); Wire.write(v); Wire.endTransmission();
  }
  uint8_t read8(uint8_t reg) {
    Wire.beginTransmission(addr_); Wire.write(reg); Wire.endTransmission(false);
    Wire.requestFrom((int)addr_, 1);
    return Wire.available() ? Wire.read() : 0;
  }
  uint8_t addr_ = MPU_ADDR;
};

// ======== calib.h ========
// 6-position accelerometer calibration (HW-02). Offsets/scales are stored in flash.
#include <Preferences.h>

struct Calib {
  float off[3] = {0, 0, 0};   // g
  float scl[3] = {1, 1, 1};
  bool valid = false;
  void apply(float rx, float ry, float rz, float& x, float& y, float& z) const {
    x = (rx - off[0]) * scl[0];
    y = (ry - off[1]) * scl[1];
    z = (rz - off[2]) * scl[2];
  }
};

inline void loadCalib(Calib& c) {
  Preferences p; p.begin("lt", true);
  if (p.isKey("cal")) {
    float v[6]; p.getBytes("cal", v, sizeof v);
    for (int i = 0; i < 3; i++) { c.off[i] = v[i]; c.scl[i] = v[3 + i]; }
    c.valid = true;
  }
  p.end();
}
inline void saveCalib(const Calib& c) {
  float v[6] = {c.off[0], c.off[1], c.off[2], c.scl[0], c.scl[1], c.scl[2]};
  Preferences p; p.begin("lt", false); p.putBytes("cal", v, sizeof v); p.end();
}

// ======== steps.h ========
// Step detection for a thigh-pocket sensor. Pure C++ so it can be host-tested.
// Input: calibrated acceleration magnitude in g at IMU_HZ, plus a gate.
//
// Method: band-limit the magnitude, find peaks, and judge each peak by its PROMINENCE (rise above the
// lowest point since the previous step) rather than its height, so small steps riding on the thigh's
// slow swing still count. Peaks are accepted only if they are plausible in size and timing; a walk
// is confirmed after 3 regular steps (those 3 are then released), and after that every step counts at
// once, short gaps and single odd intervals do not restart the confirmation, and a missed alternate
// step is filled in. While the gate is closed (e.g. seated) nothing counts and any partial walk is dropped.
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

// ======== minute.h ========
// Per-minute summaries, thigh-pocket posture, non-wear flags and the 24 h ring buffer.
// Pure C++ so it can be host-tested.
#include <string.h>

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

// ======== daysummary.h ========
// Day summary built ON THE BAND from its minute records, so no web page or app is needed to make it.
// Pure C++ so it can be host-tested. It mirrors the logic in lifetwin-band.html (categorize, not-worn
// back-fill, sit-to-stand transitions, hourly breakdown) and writes the same "lifetwin.band_day.v0" JSON.
#include <stdio.h>
#include <stdarg.h>

constexpr uint8_t WALK_MIN_STEPS = 15;     // fewer steps than this in a minute is not "walking"

enum : uint8_t {
  CAT_SITTING = 0, CAT_STANDING = 1, CAT_WALK_LIGHT = 2, CAT_WALK_MOD = 3,
  CAT_VIGOROUS = 4, CAT_OTHER = 5, CAT_NONWEAR = 6, CAT_UNKNOWN = 7, CAT_COUNT = 8
};

struct HourAgg { uint16_t sit, stand, walk, run, other, notworn, steps; };

// One local calendar day. Plain data, so it can be written to a file as it is.
struct DayAgg {
  uint8_t used[180];                 // which minutes of the local day already counted (1440 bits): a minute is never counted twice
  int32_t dayKey;                    // local days since 1970-01-01
  uint16_t minutes[CAT_COUNT];
  uint32_t steps;
  uint16_t transitions, longestSit, recorded, wear;
  uint32_t firstStart, lastStart;    // unix seconds at the start of the first / last minute (0 = none)
  HourAgg hourly[24];
};

// ---- calendar helpers (proleptic Gregorian, no library calls) ----
inline int32_t floorDiv(int64_t a, int64_t b) { int64_t q = a / b; if ((a % b != 0) && ((a < 0) != (b < 0))) q--; return (int32_t)q; }
inline int32_t floorMod(int64_t a, int64_t b) { return (int32_t)(a - (int64_t)floorDiv(a, b) * b); }
inline int64_t daysFromCivil(int y, int m, int d) {
  y -= m <= 2;
  const int era = (y >= 0 ? y : y - 399) / 400;
  const unsigned yoe = (unsigned)(y - era * 400);
  const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return (int64_t)era * 146097 + (int)doe - 719468;
}
inline void civilFromDays(int64_t z, int& y, int& m, int& d) {
  z += 719468;
  const int64_t era = (z >= 0 ? z : z - 146096) / 146097;
  const unsigned doe = (unsigned)(z - era * 146097);
  const unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  y = (int)yoe + (int)era * 400;
  const unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  const unsigned mp = (5 * doy + 2) / 153;
  d = (int)(doy - (153 * mp + 2) / 5 + 1);
  m = (int)(mp < 10 ? mp + 3 : mp - 9);
  y += (m <= 2);
}

// Parse a typed local time such as "2026-10-25 08:30:00 -07:00", "2026-10-25T08:30:00-07:00" or "...Z".
// If no zone is typed the current zone (curTzMin, minutes east of UTC) is kept.
inline bool parseLocalTime(const char* s, int curTzMin, uint32_t& unixOut, int16_t& tzOut) {
  int Y, M, D, h, mi, sec, n = 0;
  if (sscanf(s, "%d-%d-%d%*c%d:%d:%d%n", &Y, &M, &D, &h, &mi, &sec, &n) < 6 || n == 0) return false;
  if (Y < 2020 || Y > 2100 || M < 1 || M > 12 || D < 1 || D > 31 || h < 0 || h > 23 || mi < 0 || mi > 59 || sec < 0 || sec > 60) return false;
  int tz = curTzMin;
  const char* p = s + n;
  while (*p == ' ') p++;
  if (*p == 'Z' || *p == 'z') tz = 0;
  else if (*p == '+' || *p == '-') {
    int sign = (*p == '-') ? -1 : 1, th = 0, tm = 0;
    int got = sscanf(p + 1, "%d:%d", &th, &tm);
    if (got < 1) return false;
    if (got == 1 && th >= 100) { tm = th % 100; th /= 100; }      // "-0700"
    if (th > 14 || tm > 59) return false;
    tz = sign * (th * 60 + tm);
  }
  int64_t t = daysFromCivil(Y, M, D) * 86400 + h * 3600 + mi * 60 + sec - (int64_t)tz * 60;
  if (t < 1600000000LL || t > 4102444800LL) return false;
  unixOut = (uint32_t)t; tzOut = (int16_t)tz;
  return true;
}

struct JsonOut {
  char* b; size_t cap; size_t n;
  void put(const char* fmt, ...) {
    if (n >= cap) return;
    va_list ap; va_start(ap, fmt);
    int w = vsnprintf(b + n, cap - n, fmt, ap);
    va_end(ap);
    if (w < 0) return;
    n += (size_t)w; if (n >= cap) n = cap - 1;
  }
};

// "YYYY-MM-DD" -> local day number (the same numbering the day files use). Rejects impossible dates.
inline bool parseDateKey(const char* s, int32_t& dayKey) {
  int y, m, d;
  if (sscanf(s, "%4d-%2d-%2d", &y, &m, &d) != 3) return false;
  if (y < 2020 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return false;
  int32_t k = (int32_t)daysFromCivil(y, m, d); int yy, mm, dd; civilFromDays(k, yy, mm, dd);
  if (yy != y || mm != m || dd != d) return false;
  dayKey = k; return true;
}
// The list of saved days, so the app can ask for each one: {"schema":"lifetwin.band_index.v0",...,"days":["2026-10-24",...]}
inline size_t indexToJson(const int32_t* keys, int n, int tzMin, const char* fw, char* buf, size_t cap) {
  JsonOut o{buf, cap, 0};
  o.put("{\"schema\":\"lifetwin.band_index.v0\",\"firmware\":\"%s\",\"timezone_offset_minutes\":%d,\"days\":[", fw, tzMin);
  for (int i = 0; i < n; i++) { int y, m, d; civilFromDays(keys[i], y, m, d); o.put("%s\"%04d-%02d-%02d\"", i ? "," : "", y, m, d); }
  o.put("]}");
  if (o.n < cap) o.b[o.n] = 0; else o.b[cap - 1] = 0;
  return o.n;
}

// ---- classification (same rules as the page) ----
inline uint8_t categorizeMinute(const MinuteRecord& r, bool notWorn) {
  if (notWorn) return CAT_NONWEAR;
  if (r.cls >= CLS_VIGOROUS) return CAT_VIGOROUS;
  if (r.cls == CLS_MODERATE) return CAT_WALK_MOD;
  if (r.steps >= WALK_MIN_STEPS) return CAT_WALK_LIGHT;
  switch (r.posture) {
    case POSTURE_SITTING: return CAT_SITTING;
    case POSTURE_UPRIGHT: return CAT_STANDING;
    case POSTURE_OTHER:   return CAT_OTHER;
    default:              return CAT_UNKNOWN;
  }
}

// cats[i] = category of ring minute i (0 = oldest). A run of 30+ consecutive "still" minutes is not-worn;
// the band only flags it from the 30th minute, so the earlier minutes of the run are filled in here.
inline void annotateRing(const RingBuffer& ring, uint8_t* cats) {
  const uint16_t n = ring.size();
  uint16_t runStart = 0, runLen = 0; uint32_t lastTs = 0;
  for (uint16_t i = 0; i < n; i++) {
    const MinuteRecord& r = ring.at(i);
    cats[i] = (r.flags & FLAG_NONWEAR) ? 1 : 0;
    bool still = (r.flags & FLAG_STILL) != 0;
    if (still && (runLen == 0 || (int32_t)(r.ts - lastTs) <= 90)) { if (runLen == 0) runStart = i; runLen++; lastTs = r.ts; }
    else {
      if (runLen >= NONWEAR_MIN_MINUTES) for (uint16_t k = 0; k < runLen; k++) cats[runStart + k] = 1;
      runLen = 0;
      if (still) { runStart = i; runLen = 1; lastTs = r.ts; }
    }
  }
  if (runLen >= NONWEAR_MIN_MINUTES) for (uint16_t k = 0; k < runLen; k++) cats[runStart + k] = 1;
  for (uint16_t i = 0; i < n; i++) cats[i] = categorizeMinute(ring.at(i), cats[i] == 1);
}

// Local day number of a minute record (by the minute's START time).
inline int32_t dayKeyOf(const MinuteRecord& r, int32_t tzSec) { return floorDiv((int64_t)r.ts - 60 + tzSec, 86400); }

// Distinct local days present in the ring (oldest first). Returns how many were stored in keys[].
inline int collectDayKeys(const RingBuffer& ring, int32_t tzSec, int32_t* keys, int maxKeys) {
  int n = 0;
  for (uint16_t i = 0; i < ring.size(); i++) {
    const MinuteRecord& r = ring.at(i);
    if (r.flags & FLAG_TIME_UNSYNCED) continue;
    int32_t k = dayKeyOf(r, tzSec); bool have = false;
    for (int j = 0; j < n; j++) if (keys[j] == k) have = true;
    if (!have && n < maxKeys) keys[n++] = k;
  }
  for (int a = 0; a < n; a++) for (int b = a + 1; b < n; b++) if (keys[b] < keys[a]) { int32_t t = keys[a]; keys[a] = keys[b]; keys[b] = t; }
  return n;
}

// Aggregate every minute of local day `dayKey`. Each minute of the day is counted at most once (a clock correction or
// a one-second timing wobble can put two records in the same minute, and the app rejects a file that claims more
// minutes than its first-to-last window). `skip` = minutes an earlier run of the band already counted (or null).
inline void buildDay(const RingBuffer& ring, const uint8_t* cats, int32_t tzSec, int32_t dayKey, DayAgg& out, const uint8_t* skip) {
  memset(&out, 0, sizeof out);
  out.dayKey = dayKey;
  bool havePrev = false; uint32_t prevTs = 0; uint8_t prevCat = 0; uint16_t curSit = 0;
  for (uint16_t i = 0; i < ring.size(); i++) {
    const MinuteRecord& r = ring.at(i);
    if (r.flags & FLAG_TIME_UNSYNCED) continue;
    int64_t localStart = (int64_t)r.ts - 60 + tzSec;
    if (floorDiv(localStart, 86400) != dayKey) continue;
    int32_t slot = floorMod(localStart, 86400) / 60;                       // minute of the local day, 0..1439
    if (out.used[slot >> 3] & (1 << (slot & 7))) continue;               // already counted in this run
    if (skip && (skip[slot >> 3] & (1 << (slot & 7)))) continue;          // already counted before a restart
    out.used[slot >> 3] |= (uint8_t)(1 << (slot & 7));
    uint8_t c = cats[i];
    out.minutes[c]++; out.recorded++; out.steps += r.steps;
    uint32_t startUtc = r.ts - 60;
    if (out.firstStart == 0 || startUtc < out.firstStart) out.firstStart = startUtc;
    if (startUtc > out.lastStart) out.lastStart = startUtc;
    HourAgg& h = out.hourly[floorMod(localStart, 86400) / 3600];
    h.steps += r.steps;
    switch (c) {
      case CAT_SITTING: h.sit++; break;
      case CAT_STANDING: h.stand++; break;
      case CAT_WALK_LIGHT: case CAT_WALK_MOD: h.walk++; break;
      case CAT_VIGOROUS: h.run++; break;
      case CAT_OTHER: h.other++; break;
      case CAT_NONWEAR: h.notworn++; break;
      default: break;
    }
    bool contiguous = havePrev && (int32_t)(r.ts - prevTs) <= 90;
    bool up = c == CAT_STANDING || c == CAT_WALK_LIGHT || c == CAT_WALK_MOD || c == CAT_VIGOROUS;
    if (c == CAT_SITTING) { curSit = (contiguous && prevCat == CAT_SITTING) ? curSit + 1 : 1; if (curSit > out.longestSit) out.longestSit = curSit; }
    else curSit = 0;
    if (contiguous && prevCat == CAT_SITTING && up) out.transitions++;
    havePrev = true; prevTs = r.ts; prevCat = c;
  }
  out.wear = out.recorded - out.minutes[CAT_NONWEAR];
}

// Add what was recorded after a restart (`add`) to what an earlier run of the band saved (`base`).
// Totals add up exactly; the longest sitting stretch is the larger of the two and a sit-to-stand that
// straddles the restart is not counted.
inline void mergeDay(DayAgg& base, const DayAgg& add) {
  if (base.recorded == 0) { base = add; return; }
  for (int k = 0; k < 180; k++) base.used[k] |= add.used[k];
  for (int c = 0; c < CAT_COUNT; c++) base.minutes[c] += add.minutes[c];
  base.steps += add.steps; base.transitions += add.transitions; base.recorded += add.recorded; base.wear += add.wear;
  if (add.longestSit > base.longestSit) base.longestSit = add.longestSit;
  if (add.firstStart && (base.firstStart == 0 || add.firstStart < base.firstStart)) base.firstStart = add.firstStart;
  if (add.lastStart > base.lastStart) base.lastStart = add.lastStart;
  for (int h = 0; h < 24; h++) {
    base.hourly[h].sit += add.hourly[h].sit; base.hourly[h].stand += add.hourly[h].stand; base.hourly[h].walk += add.hourly[h].walk;
    base.hourly[h].run += add.hourly[h].run; base.hourly[h].other += add.hourly[h].other; base.hourly[h].notworn += add.hourly[h].notworn;
    base.hourly[h].steps += add.hourly[h].steps;
  }
}

// ---- JSON ----
inline void localHM(uint32_t unixT, int tzMin, int& hh, int& mm) {
  int64_t local = (int64_t)unixT + (int64_t)tzMin * 60;
  hh = floorMod(local, 86400) / 3600; mm = floorMod(local, 3600) / 60;
}

// mode 0 = HEADLINE: just the headline numbers, small enough for one Bluetooth read (512 bytes or less).
// mode 1 = FULL: the complete file (adds device, generated_at, first/last minute, hourly list and notes).
inline size_t dayToJson(const DayAgg& d, int tzMin, const char* fw, int fmt, uint32_t nowUnix, int mode, char* buf, size_t cap) {
  JsonOut o{buf, cap, 0};
  const bool full = mode == 1;
  int y, m, dd; civilFromDays(d.dayKey, y, m, dd);
  o.put("{\"schema\":\"lifetwin.band_day.v0\",\"date\":\"%04d-%02d-%02d\",", y, m, dd);
  if (full) {
    int gy, gm, gd; civilFromDays(floorDiv(nowUnix, 86400), gy, gm, gd);
    int gs = floorMod(nowUnix, 86400);
    o.put("\"timezone_offset_minutes\":%d,\"generated_at\":\"%04d-%02d-%02dT%02d:%02d:%02dZ\",", tzMin, gy, gm, gd, gs / 3600, (gs / 60) % 60, gs % 60);
    o.put("\"device\":{\"mount\":\"thigh_pocket\",\"firmware\":\"%s\",\"record_format\":%d},", fw, fmt);
  } else o.put("\"headline_only\":true,");
  o.put("\"coverage\":{\"minutes_recorded\":%u,\"wear_minutes\":%u,\"valid_day\":%s", (unsigned)d.recorded, (unsigned)d.wear, d.wear >= 600 ? "true" : "false");
  if (full) {
    if (d.firstStart) { int a, b2, c, e; localHM(d.firstStart, tzMin, a, b2); localHM(d.lastStart, tzMin, c, e);
      o.put(",\"first_minute\":\"%02d:%02d\",\"last_minute\":\"%02d:%02d\"", a, b2, c, e); }
    else o.put(",\"first_minute\":null,\"last_minute\":null");
  }
  o.put("},\"minutes\":{\"sitting_or_lying\":%u,\"standing\":%u,\"walking_light\":%u,\"walking_moderate\":%u,\"running_vigorous\":%u,\"other_posture\":%u,\"not_worn\":%u,\"positions_not_saved\":%u},",
        (unsigned)d.minutes[CAT_SITTING], (unsigned)d.minutes[CAT_STANDING], (unsigned)d.minutes[CAT_WALK_LIGHT], (unsigned)d.minutes[CAT_WALK_MOD],
        (unsigned)d.minutes[CAT_VIGOROUS], (unsigned)d.minutes[CAT_OTHER], (unsigned)d.minutes[CAT_NONWEAR], (unsigned)d.minutes[CAT_UNKNOWN]);
  o.put("\"moderate_vigorous_minutes\":%u,\"steps\":%lu,\"sit_to_stand_transitions\":%u,\"longest_sitting_minutes\":%u",
        (unsigned)(d.minutes[CAT_WALK_MOD] + d.minutes[CAT_VIGOROUS]), (unsigned long)d.steps, (unsigned)d.transitions, (unsigned)d.longestSit);
  if (full) {
    o.put(",\n\"hourly\":[");
    for (int h = 0; h < 24; h++) {
      const HourAgg& a = d.hourly[h];
      o.put("%s\n {\"hour\":%d,\"sitting_lying_min\":%u,\"standing_min\":%u,\"walking_min\":%u,\"running_min\":%u,\"other_min\":%u,\"not_worn_min\":%u,\"steps\":%u}",
            h ? "," : "", h, (unsigned)a.sit, (unsigned)a.stand, (unsigned)a.walk, (unsigned)a.run, (unsigned)a.other, (unsigned)a.notworn, (unsigned)a.steps);
    }
    o.put("\n],\n\"notes\":[\"Device estimates, not medical measurements.\",\"A thigh sensor counts lying down as sitting.\",\"Walking intensity uses provisional steps-per-minute cut-offs.\",\"A valid day has at least 600 wear minutes.\"]");
  }
  o.put("}");
  if (o.n < cap) o.b[o.n] = 0; else o.b[cap - 1] = 0;
  return o.n;
}

// ======== ble_service.h ========
// BLE GATT service (HW-07). Requires NimBLE-Arduino >= 2.0.
// UUIDs below are PLACEHOLDERS: the repo has no band-protocol contract yet.
// Agree on them with the Flutter owner (APP-01) before the app depends on them.
#include <NimBLEDevice.h>
#include <string>

#define LT_SVC_UUID     "4c540001-7b2a-4f0e-9a51-0d1e2c3b4a50"
#define LT_INFO_UUID    "4c540002-7b2a-4f0e-9a51-0d1e2c3b4a50"  // READ
#define LT_TIME_UUID    "4c540003-7b2a-4f0e-9a51-0d1e2c3b4a50"  // WRITE  uint32 LE unix seconds
#define LT_CTRL_UUID    "4c540004-7b2a-4f0e-9a51-0d1e2c3b4a50"  // WRITE  see README
#define LT_HISTORY_UUID "4c540005-7b2a-4f0e-9a51-0d1e2c3b4a50"  // NOTIFY 12-byte MinuteRecord
#define LT_TOTALS_UUID  "4c540007-7b2a-4f0e-9a51-0d1e2c3b4a50"  // READ+NOTIFY 20 bytes: sit s u32, stand s u32, other s u32, steps u32, run s u16, posture u8, 0
#define LT_SUMMARY_UUID "4c540008-7b2a-4f0e-9a51-0d1e2c3b4a50"  // READ: headline day summary (JSON text, <= 512 bytes). NOTIFY: the full JSON file, sent in chunks after CTRL 0x0B
#define LT_LIVE_UUID    "4c540006-7b2a-4f0e-9a51-0d1e2c3b4a50"  // NOTIFY 5 bytes: enmo_mg u16, steps_this_min u16, posture u8 

class BandBle;
static BandBle* gBle = nullptr;

class BandBle {
 public:
  volatile bool connected = false;
  volatile bool timePending = false;
  uint8_t timeBuf[32]; volatile uint8_t timeLen = 0;   // raw bytes written to the time characteristic (4 = unix, 6 = unix + zone, or typed text)
  volatile bool saveRequested = false, sendFileRequested = false;   // CTRL 0x0A / 0x0B
  volatile bool indexRequested = false, dayFileRequested = false, ackDayRequested = false;   // CTRL 0x0D / 0x0C / 0x0E
  char ctrlArg[17]; volatile uint8_t ctrlArgLen = 0;                 // text argument that follows 0x0C / 0x0E (a date YYYY-MM-DD)
  volatile uint16_t mtu = 23;                                        // negotiated size, used to pick the chunk size
  volatile bool streamPending = false; volatile uint32_t streamSince = 0;
  volatile bool stopPending = false;
  volatile bool liveOn = false;
  volatile bool resetTotals = false;
  volatile bool stepSettingsPending = false; volatile uint8_t stepSettingsValue = 0;   // CTRL 0x09 + byte
  uint8_t stepSettings = 0;                         // current settings byte, reported in INFO byte 9                // set by CTRL 0x07
  uint32_t totSit = 0, totStand = 0, totOther = 0, totSteps = 0;   // set by the main loop, sent at 1 Hz
  uint16_t totRun = 0; uint8_t totPosture = 0;
  volatile bool liveDirty = false;                  // set when posture changes: notify immediately
  volatile bool capStand = false, capSit = false;   // set by CTRL 0x05 / 0x06
  uint16_t liveEnmoMg = 0, liveSteps = 0;     // set by the main loop
  uint8_t livePosture = 0, postureState = 0;  // postureState bits: 1 stand captured, 2 sit captured, 4 both valid

  void begin(RingBuffer* ring) {
    ring_ = ring; gBle = this;
    NimBLEDevice::init("LifeTwin Band");
    server_ = NimBLEDevice::createServer();
    server_->setCallbacks(new ServerCb());
    NimBLEService* svc = server_->createService(LT_SVC_UUID);
    info_ = svc->createCharacteristic(LT_INFO_UUID, NIMBLE_PROPERTY::READ);
    NimBLECharacteristic* t = svc->createCharacteristic(LT_TIME_UUID, NIMBLE_PROPERTY::WRITE);
    NimBLECharacteristic* c = svc->createCharacteristic(LT_CTRL_UUID, NIMBLE_PROPERTY::WRITE);
    t->setCallbacks(new TimeCb());
    c->setCallbacks(new CtrlCb());
    hist_ = svc->createCharacteristic(LT_HISTORY_UUID, NIMBLE_PROPERTY::NOTIFY);
    live_ = svc->createCharacteristic(LT_LIVE_UUID, NIMBLE_PROPERTY::NOTIFY);
    tot_ = svc->createCharacteristic(LT_TOTALS_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
    sum_ = svc->createCharacteristic(LT_SUMMARY_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
    { const char* none = "{\"headline_only\":true,\"note\":\"no summary yet: set the time, then write 0A to the control characteristic\"}"; sum_->setValue((const uint8_t*)none, strlen(none)); }
    { uint8_t z[20] = {0}; tot_->setValue(z, sizeof z); }
    svc->start();
    updateInfo();
    // The 128-bit service UUID + flags + the name do not fit in one 31-byte advertising
    // packet, so the name was being dropped (scanners showed "N/A"). Put the UUID in the
    // advertisement and the name in the scan response.
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    NimBLEAdvertisementData advData;
    advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
    advData.addServiceUUID(LT_SVC_UUID);
    NimBLEAdvertisementData scanData;
    scanData.setName("LifeTwin Band");
    adv->setAdvertisementData(advData);
    adv->setScanResponseData(scanData);
    adv->enableScanResponse(true);
    adv->start();
  }

  // INFO: [fw_major, fw_minor, format_version, record_size, capacity u16, stored u16, posture_state, step_settings]
  void updateInfo() {
    uint8_t b[10] = {FW_MAJOR, FW_MINOR, FORMAT_VERSION, sizeof(MinuteRecord),
                     (uint8_t)(RING_MINUTES & 0xFF), (uint8_t)(RING_MINUTES >> 8),
                     (uint8_t)(ring_->size() & 0xFF), (uint8_t)(ring_->size() >> 8), postureState, stepSettings};
    info_->setValue(b, sizeof b);
  }

  // The headline summary: what a plain READ of the summary characteristic returns.
  void setHeadline(const char* json, size_t len) { if (len > 512) len = 512; sum_->setValue((const uint8_t*)json, len); }
  // Send a whole text file as notifications on the summary characteristic (the phone must have notifications switched on).
  void startFileStream(const char* data, size_t len) { fileData_.assign(data, len); filePos_ = 0; fileFails_ = 0; fileEofSent_ = false; fileStreaming_ = true; }
  bool fileStreamBusy() const { return fileStreaming_; }

  // Call every loop iteration with millis().
  void service(uint32_t now) {
    if (!connected) { streaming_ = false; fileStreaming_ = false; return; }
    if (fileStreaming_ && now - lastFileChunk_ >= 25) {
      lastFileChunk_ = now;
      size_t chunk = mtu > 23 ? (size_t)mtu - 3 : 20; if (chunk > 180) chunk = 180;
      if (filePos_ < fileData_.size()) {
        size_t n = fileData_.size() - filePos_; if (n > chunk) n = chunk;
        if (sum_->notify((const uint8_t*)fileData_.data() + filePos_, n)) { filePos_ += n; fileFails_ = 0; }
        else if (++fileFails_ > 80) fileStreaming_ = false;          // nobody listening: give up after about 2 s
      } else if (!fileEofSent_) {
        const char* eof = "<EOF>"; if (sum_->notify((const uint8_t*)eof, 5)) { fileEofSent_ = true; fileStreaming_ = false; }
        else if (++fileFails_ > 80) fileStreaming_ = false;
      }
    }
    if (stopPending) { stopPending = false; streaming_ = false; }
    if (streamPending) { streamPending = false; cursor_ = streamSince; streaming_ = true; }

    if (streaming_ && now - lastSend_ >= 15) {       // ~66 records/s
      lastSend_ = now;
      const MinuteRecord* next = nullptr;
      for (uint16_t i = 0; i < ring_->size(); i++) {
        if (ring_->at(i).ts > cursor_) { next = &ring_->at(i); break; }
      }
      if (!next) {                                    // end marker: ts = 0xFFFFFFFF
        uint8_t end[sizeof(MinuteRecord)]; memset(end, 0xFF, sizeof end);
        if (hist_->notify(end, sizeof end)) streaming_ = false;
      } else if (hist_->notify((const uint8_t*)next, sizeof(MinuteRecord))) {
        cursor_ = next->ts;                           // only advance when the send was accepted
      }
    }
    if (liveOn && (liveDirty || now - lastLive_ >= 1000)) {
      lastLive_ = now;
      liveDirty = false;
      uint8_t b[5] = {(uint8_t)(liveEnmoMg & 0xFF), (uint8_t)(liveEnmoMg >> 8),
                      (uint8_t)(liveSteps & 0xFF), (uint8_t)(liveSteps >> 8), livePosture};
      live_->notify(b, sizeof b);
    }
    if (liveOn && now - lastTot_ >= 1000) {
      lastTot_ = now;
      uint8_t b[20];
      put32(b, 0, totSit); put32(b, 4, totStand); put32(b, 8, totOther); put32(b, 12, totSteps);
      b[16] = (uint8_t)(totRun & 0xFF); b[17] = (uint8_t)(totRun >> 8); b[18] = totPosture; b[19] = 0;
      tot_->setValue(b, sizeof b);
      tot_->notify(b, sizeof b);
    }
  }

 private:
  struct ServerCb : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer*, NimBLEConnInfo&) override { gBle->connected = true; }
    void onMTUChange(uint16_t MTU, NimBLEConnInfo&) override { gBle->mtu = MTU; }
    void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
      gBle->connected = false; gBle->mtu = 23;
      NimBLEDevice::getAdvertising()->start();        // keep advertising so it can reconnect
    }
  };
  struct TimeCb : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* c, NimBLEConnInfo&) override {
      NimBLEAttValue v = c->getValue();
      size_t n = v.length(); if (n > 31) n = 31;
      if (n >= 4) { memcpy(gBle->timeBuf, v.data(), n); gBle->timeLen = (uint8_t)n; gBle->timePending = true; }
    }
  };
  // CTRL: 0x01 + u32 LE since_ts -> stream records with ts > since_ts
  //       0x02 -> stop;  0x03 -> live on;  0x04 -> live off
  //       0x05 -> capture STANDING reference (5 s delay, then 3 s hold still)
  //       0x06 -> capture SITTING reference  (same)
  //       0x07 -> reset the live sit / stand / steps timers
  //       0x0A -> build the day summary now, save it as a JSON file in the band's flash, update the headline read
  //       0x0B -> same, then send the full JSON file as notifications on the summary characteristic (switch them on first)
  //       0x0C + "YYYY-MM-DD" -> send that saved day's JSON file as notifications (switch them on first)
  //       0x0D -> send the list of saved days as notifications
  //       0x0E + "YYYY-MM-DD" -> delete that day's file (only days before today), once the app has stored it
  //       0x09 + byte -> step settings: bits 0-2 sensitivity 1..5, bit 3 ignore-steps-while-sitting, bit 4 count-each-step-twice
  struct CtrlCb : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* c, NimBLEConnInfo&) override {
      NimBLEAttValue v = c->getValue();
      if (v.length() < 1) return;
      const uint8_t* d = v.data();
      switch (d[0]) {
        case 0x01:
          if (v.length() >= 5) {
            gBle->streamSince = (uint32_t)d[1] | ((uint32_t)d[2] << 8) | ((uint32_t)d[3] << 16) | ((uint32_t)d[4] << 24);
            gBle->streamPending = true;
          }
          break;
        case 0x02: gBle->stopPending = true; break;
        case 0x03: gBle->liveOn = true; break;
        case 0x04: gBle->liveOn = false; break;
        case 0x05: gBle->capStand = true; break;
        case 0x06: gBle->capSit = true; break;
        case 0x07: gBle->resetTotals = true; break;
        case 0x0A: gBle->saveRequested = true; break;       // build today's summary and save it as a JSON file on the band
        case 0x0B: gBle->sendFileRequested = true; break;   // ...and send the full file as notifications
        case 0x0C: case 0x0E: {                              // + date "YYYY-MM-DD": send that day's saved file / delete it after the app has stored it
          size_t n = v.length() > 1 ? v.length() - 1 : 0; if (n > 16) n = 16;
          memcpy(gBle->ctrlArg, d + 1, n); gBle->ctrlArg[n] = 0; gBle->ctrlArgLen = (uint8_t)n;
          if (d[0] == 0x0C) gBle->dayFileRequested = true; else gBle->ackDayRequested = true;
          break; }
        case 0x0D: gBle->indexRequested = true; break;       // send the list of saved days
        case 0x09:
          if (v.length() >= 2) { gBle->stepSettingsValue = d[1]; gBle->stepSettingsPending = true; }
          break;
      }
    }
  };

  static void put32(uint8_t* b, int o, uint32_t v) { b[o] = v & 0xFF; b[o + 1] = (v >> 8) & 0xFF; b[o + 2] = (v >> 16) & 0xFF; b[o + 3] = (v >> 24) & 0xFF; }
  RingBuffer* ring_ = nullptr;
  NimBLEServer* server_ = nullptr;
  NimBLECharacteristic *info_ = nullptr, *hist_ = nullptr, *live_ = nullptr, *tot_ = nullptr, *sum_ = nullptr;
  bool streaming_ = false;
  std::string fileData_; size_t filePos_ = 0; int fileFails_ = 0; bool fileStreaming_ = false, fileEofSent_ = false; uint32_t lastFileChunk_ = 0;
  uint32_t cursor_ = 0, lastSend_ = 0, lastLive_ = 0, lastTot_ = 0;
};

// ======== main sketch ========
#include <LittleFS.h>

Mpu6050 imu;
Calib cal;
StepDetector stepper;
MinuteAggregator agg;
RingBuffer ring;
BandBle ble;
PostureRef postureRef;
SessionTotals totals;          // live sit / stand / steps timers (reset with 'z' or from the web page)
uint32_t lastTotMs = 0;
// Step settings (kept in flash): sensitivity 1..5, ignore steps while sitting, count every detected step twice
uint8_t stepSens = 3; bool stepGate = true; bool stepDouble = false;
bool recordCsv = false;       // 'r': raw CSV recording for tuning

// ---- day summary kept on the band (JSON files in flash) ----
int16_t tzMin = 0;             // local time zone, minutes east of UTC (e.g. -420 for PDT). Set with the time.
bool fsOk = false;             // flash file system mounted?
char fwStr[12];
static uint8_t catBuf[RING_MINUTES + 8];
static char fullJson[4608];    // the full day file for the most recent day
static char headJson[560];     // the headline numbers (fits one Bluetooth read)
struct BaseSlot { int32_t dayKey; bool used; DayAgg agg; };
static BaseSlot baseSlots[3];  // what earlier runs of the band (before a restart) had already saved for each day
uint8_t nextBaseSlot = 0;
uint8_t minutesSinceSave = 0;
size_t dayIndexLen = 0;

bool imuOk = false;
bool rawStream = false;
uint32_t nextImuUs = 0, minuteStartMs = 0;
uint32_t epochOffset = 0;      // unix seconds minus uptime seconds, once synced
bool synced = false;
uint32_t rateCount = 0, rateStartMs = 0;
float liveX = 0, liveY = 0, liveZ = 1;   // ~0.4 s moving average of gravity direction
uint8_t postureStable = POSTURE_UNKNOWN, posturePending = POSTURE_UNKNOWN;   // live posture state
uint32_t posturePendingSince = 0;

static const char* POSTURE_NAMES[4] = {"unknown", "sitting", "standing", "other"};
static const char* CLS_NAMES[4] = {"sedentary", "light", "moderate", "vigorous"};

// ---------- helpers ----------
void i2cScan() {
  Serial.println("I2C scan (expect 0x68 = MPU6050):");
  int found = 0;
  for (uint8_t a = 1; a < 127; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) { Serial.printf("  found 0x%02X\n", a); found++; }
  }
  if (!found) Serial.println("  nothing found: check 3V3/GND/SDA/SCL wiring");
}

bool readCalibrated(float& x, float& y, float& z) {
  int16_t rx, ry, rz;
  if (!imu.readRaw(rx, ry, rz)) return false;
  cal.apply(rx / ACCEL_LSB_PER_G, ry / ACCEL_LSB_PER_G, rz / ACCEL_LSB_PER_G, x, y, z);
  return true;
}

void waitKey() {
  while (Serial.available()) Serial.read();
  while (!Serial.available()) delay(10);
  while (Serial.available()) Serial.read();
}

// HW-02: six-position calibration. Axis labels are printed on the MPU6050 board.
void runCalibration() {
  const char* names[6] = {"+X up", "-X up", "+Y up", "-Y up", "+Z up (flat, chip face up)", "-Z up (flat, chip face down)"};
  float avg[6][3];
  Serial.println("\n== Calibration: hold still in each pose, press Enter to sample ==");
  Serial.println("In each pose the named axis must point straight UP (+) or straight DOWN (-).");
  Serial.println("The X/Y/Z arrows are printed on the sensor board. Z points out of the chip face.");
  for (int p = 0; p < 6; p++) {
    int axis = p / 2;
    float sign = (p % 2 == 0) ? 1.0f : -1.0f;
    bool accepted = false;
    while (!accepted) {
      Serial.printf("Pose %d/6: %s. Hold it still, then press Enter.\n", p + 1, names[p]);
      waitKey();
      double s[3] = {0, 0, 0}; int n = 0;
      uint32_t t0 = millis();
      while (n < 150 && millis() - t0 < 5000) {
        int16_t rx, ry, rz;
        if (imu.readRaw(rx, ry, rz)) { s[0] += rx; s[1] += ry; s[2] += rz; n++; }
        delay(20);
      }
      if (n < 100) { Serial.println("Too few samples (I2C problem?). Aborting."); return; }
      for (int i = 0; i < 3; i++) avg[p][i] = (float)(s[i] / n) / ACCEL_LSB_PER_G;
      Serial.printf("  raw g: %.4f %.4f %.4f\n", avg[p][0], avg[p][1], avg[p][2]);
      if (avg[p][axis] * sign < 0.7f) {
        Serial.printf("  WRONG POSE: the %c axis should read about %+.0f g but reads %.2f. Rotate the board and try this pose again.\n",
                      "XYZ"[axis], sign, avg[p][axis]);
      } else {
        accepted = true;
      }
    }
  }
  Calib c;
  for (int i = 0; i < 3; i++) {
    float pos = avg[2 * i][i], neg = avg[2 * i + 1][i];
    c.off[i] = (pos + neg) / 2.0f;
    c.scl[i] = 2.0f / (pos - neg);
  }
  c.valid = true;
  bool pass = true;
  Serial.println("After correction (target |g| = 1.000 +/- 0.030):");
  for (int p = 0; p < 6; p++) {
    float x, y, z; c.apply(avg[p][0], avg[p][1], avg[p][2], x, y, z);
    float m = sqrtf(x * x + y * y + z * z);
    bool ok = fabsf(m - 1.0f) <= 0.03f; pass &= ok;
    Serial.printf("  %-30s |g| = %.4f  %s\n", names[p], m, ok ? "PASS" : "FAIL");
  }
  if (pass) { cal = c; saveCalib(cal); Serial.println("HW-02 PASS: calibration saved."); }
  else Serial.println("HW-02 FAIL: not saved. Re-seat the sensor flat and retry.");
}


// ---------- step settings ----------
uint8_t stepSettingsByte() { return (stepSens & 7) | (stepGate ? 8 : 0) | (stepDouble ? 16 : 0); }
void applyStepSettings() { stepper.setSensitivity(stepSens); ble.stepSettings = stepSettingsByte(); }
void loadStepSettings() {
  Preferences p; p.begin("lt", true);
  if (p.isKey("stp")) { uint8_t v = p.getUChar("stp", stepSettingsByte()); stepSens = (v & 7) < 1 || (v & 7) > 5 ? 3 : (v & 7); stepGate = (v & 8) != 0; stepDouble = (v & 16) != 0; }
  p.end();
  applyStepSettings();
}
void setStepSettings(uint8_t v) {
  stepSens = (v & 7) < 1 || (v & 7) > 5 ? stepSens : (v & 7); stepGate = (v & 8) != 0; stepDouble = (v & 16) != 0;
  applyStepSettings(); ble.updateInfo();
  Preferences p; p.begin("lt", false); p.putUChar("stp", stepSettingsByte()); p.end();
  Serial.printf("step settings: sensitivity %u, ignore steps while sitting %s, count twice %s\n", stepSens, stepGate ? "ON" : "off", stepDouble ? "ON" : "off");
}

// ---------- day summary files ----------
uint32_t nowUnix() { return epochOffset + millis() / 1000; }
void dayFileName(int32_t dayKey, char* out, size_t n) { int y, m, d; civilFromDays(dayKey, y, m, d); snprintf(out, n, "/day_%04d-%02d-%02d.json", y, m, d); }
void accFileName(int32_t dayKey, char* out, size_t n) { snprintf(out, n, "/acc_%ld.bin", (long)dayKey); }
bool readAcc(int32_t dayKey, DayAgg& out) {
  if (!fsOk) return false;
  char p[32]; accFileName(dayKey, p, sizeof p);
  if (!LittleFS.exists(p)) return false;
  File f = LittleFS.open(p, "r"); if (!f) return false;
  bool ok = f.size() == sizeof(DayAgg) && f.read((uint8_t*)&out, sizeof(DayAgg)) == sizeof(DayAgg) && out.dayKey == dayKey;
  f.close(); return ok;
}
void writeFileBytes(const char* path, const void* data, size_t n) {
  if (!fsOk) return;
  File f = LittleFS.open(path, "w"); if (!f) { Serial.printf("could not write %s\n", path); return; }
  f.write((const uint8_t*)data, n); f.close();
}
DayAgg* baseFor(int32_t dayKey) {
  for (int i = 0; i < 3; i++) if (baseSlots[i].used && baseSlots[i].dayKey == dayKey) return &baseSlots[i].agg;
  BaseSlot& s = baseSlots[nextBaseSlot]; nextBaseSlot = (nextBaseSlot + 1) % 3;
  s.used = true; s.dayKey = dayKey; memset(&s.agg, 0, sizeof s.agg);
  DayAgg loaded; if (readAcc(dayKey, loaded)) s.agg = loaded;
  return &s.agg;
}
// Build the day summary for every day in the ring, save each as /day_YYYY-MM-DD.json in flash, and refresh the
// headline (BLE read) and full (BLE stream) text for the most recent day. Returns false if the clock is not set.
bool saveSummaries() {
  if (!synced) { Serial.println("Set the time first (serial: T 2026-10-25 08:30:00 -07:00, or write it over Bluetooth)."); return false; }
  annotateRing(ring, catBuf);
  int32_t keys[4]; int n = collectDayKeys(ring, (int32_t)tzMin * 60, keys, 4);
  if (n == 0) { Serial.println("No minutes recorded yet: wait for the first minute to finish."); return false; }
  for (int i = 0; i < n; i++) {
    DayAgg* base = baseFor(keys[i]);
    DayAgg cur; buildDay(ring, catBuf, (int32_t)tzMin * 60, keys[i], cur, base->recorded ? base->used : nullptr);
    DayAgg total = *base; mergeDay(total, cur);
    DayAgg saved; if (readAcc(keys[i], saved) && saved.recorded > total.recorded) total = saved;   // never replace a day with less data
    size_t len = dayToJson(total, tzMin, fwStr, FORMAT_VERSION, nowUnix(), 1, fullJson, sizeof fullJson);
    if (fsOk) { char p[40]; accFileName(keys[i], p, sizeof p); writeFileBytes(p, &total, sizeof total); dayFileName(keys[i], p, sizeof p); writeFileBytes(p, fullJson, len); }
    if (i == n - 1) { size_t hl = dayToJson(total, tzMin, fwStr, FORMAT_VERSION, nowUnix(), 0, headJson, sizeof headJson); ble.setHeadline(headJson, hl); }
  }
  return true;
}
// The saved days, oldest first (from the /day_YYYY-MM-DD.json files in flash).
int listDayKeys(int32_t* keys, int maxKeys) {
  int n = 0; if (!fsOk) return 0;
  File root = LittleFS.open("/"); File f = root.openNextFile();
  while (f) {
    const char* nm = f.name(); const char* b = strrchr(nm, '/'); b = b ? b + 1 : nm; int32_t k;
    if (strlen(b) == 19 && strncmp(b, "day_", 4) == 0 && strcmp(b + 14, ".json") == 0) {
      char d[11]; memcpy(d, b + 4, 10); d[10] = 0;
      if (parseDateKey(d, k) && n < maxKeys) keys[n++] = k;
    }
    f = root.openNextFile();
  }
  for (int a = 0; a < n; a++) for (int c = a + 1; c < n; c++) if (keys[c] < keys[a]) { int32_t t = keys[a]; keys[a] = keys[c]; keys[c] = t; }
  return n;
}
void serveIndex() {
  if (synced) saveSummaries();                       // make sure today's file is current
  int32_t keys[40]; int n = listDayKeys(keys, 40);
  size_t len = dayIndexLen = indexToJson(keys, n, tzMin, fwStr, fullJson, sizeof fullJson);
  ble.startFileStream(fullJson, len);
}
void serveDayFile() {
  char date[17]; memcpy(date, ble.ctrlArg, 17); date[16] = 0; int32_t key;
  if (!parseDateKey(date, key)) { const char* e = "{\"error\":\"bad_date\"}"; ble.startFileStream(e, strlen(e)); return; }
  if (synced) saveSummaries();                       // refreshes today's file; older days are served as saved
  char p[40]; dayFileName(key, p, sizeof p);
  if (!fsOk || !LittleFS.exists(p)) { const char* e = "{\"error\":\"no_file_for_that_date\"}"; ble.startFileStream(e, strlen(e)); return; }
  File f = LittleFS.open(p, "r"); size_t n = f.read((uint8_t*)fullJson, sizeof fullJson - 1); f.close(); fullJson[n] = 0;
  ble.startFileStream(fullJson, n);
}
// The app has stored a finished day: free the space. Today's (and any later) day is never deleted.
void ackDay() {
  char date[17]; memcpy(date, ble.ctrlArg, 17); date[16] = 0; int32_t key;
  if (!fsOk || !synced || !parseDateKey(date, key)) { Serial.println("ack ignored (no file system, clock not set, or bad date)"); return; }
  int32_t todayKey = floorDiv((int64_t)nowUnix() + (int64_t)tzMin * 60, 86400);
  if (key >= todayKey) { Serial.println("ack ignored: only finished days before today can be deleted"); return; }
  char p[40]; dayFileName(key, p, sizeof p); LittleFS.remove(p); accFileName(key, p, sizeof p); LittleFS.remove(p);
  for (int i = 0; i < 3; i++) if (baseSlots[i].used && baseSlots[i].dayKey == key) baseSlots[i].used = false;
  Serial.printf("day %s deleted after the app stored it\n", date);
}
void listFiles() {
  if (!fsOk) { Serial.println("No flash file system."); return; }
  File root = LittleFS.open("/"); File f = root.openNextFile(); int n = 0;
  while (f) { Serial.printf("  %s  %u bytes\n", f.name(), (unsigned)f.size()); n++; f = root.openNextFile(); }
  Serial.printf("%d file(s)\n", n);
}
// Set the clock from 4 bytes (unix), 6 bytes (unix + zone in minutes, little-endian) or typed text such as
// "2026-10-25 08:30:00 -07:00". Boot-relative minutes already recorded become real times.
void applyTime(const uint8_t* b, size_t n) {
  uint32_t u = 0; int16_t tz = tzMin; bool ok = false;
  if (n == 4 || n == 6) { u = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24); if (n == 6) tz = (int16_t)(b[4] | (b[5] << 8)); ok = u > 1600000000UL; }
  else if (n >= 10 && n < 32) { char t[33]; memcpy(t, b, n); t[n] = 0; ok = parseLocalTime(t, tzMin, u, tz); }
  if (!ok) { Serial.println("Time not understood. Use e.g.  2026-10-25 08:30:00 -07:00"); return; }
  tzMin = tz; epochOffset = u - millis() / 1000; synced = true; ring.rebaseUnsynced(epochOffset);
  Preferences p; p.begin("lt", false); p.putShort("tz", tzMin); p.end();
  int hh, mm; localHM(u, tzMin, hh, mm);
  Serial.printf("Clock set. Local time now %02d:%02d, zone %+d min from UTC.\n", hh, mm, (int)tzMin);
}

// ---------- posture references (thigh pocket) ----------
void loadPosture() {
  Preferences p; p.begin("lt", true);
  if (p.getBytesLength("pst2") == sizeof(PostureRef)) p.getBytes("pst2", &postureRef, sizeof(PostureRef));
  p.end();
}
void savePosture() {
  Preferences p; p.begin("lt", false); p.putBytes("pst2", &postureRef, sizeof(PostureRef)); p.end();
}
uint8_t postureState() {
  return (postureRef.haveStand ? 1 : 0) | (postureRef.haveSit ? 2 : 0) | (postureRef.valid() ? 4 : 0);
}

// Capture the gravity direction while the band is in the pocket. Waits 5 s so you can
// get into position (and put the phone away), then averages 3 s. Hold still and keep
// the thigh in position: standing = leg vertical, sitting = thigh horizontal.
void doPostureCapture(bool stand) {
  if (!imuOk) { Serial.println("No IMU, cannot capture posture."); return; }
  if (!cal.valid) { Serial.println("Run accelerometer calibration ('c') first."); return; }
  Serial.printf("Capturing %s in 5 s. Get into position and hold still...\n", stand ? "STANDING" : "SITTING");
  uint32_t t0 = millis();
  while (millis() - t0 < 5000) delay(10);
  double s[3] = {0, 0, 0}; int n = 0;
  t0 = millis();
  while (n < 150 && millis() - t0 < 6000) {
    float x, y, z;
    if (readCalibrated(x, y, z)) { s[0] += x; s[1] += y; s[2] += z; n++; }
    delay(20);
  }
  nextImuUs = micros();
  if (n < 100) { Serial.println("Too few samples. Try again."); return; }
  float v[3] = {(float)(s[0] / n), (float)(s[1] / n), (float)(s[2] / n)};
  float mag = sqrtf(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  Serial.printf("  mean g: %.3f %.3f %.3f  (|g|=%.3f)\n", v[0], v[1], v[2], mag);
  if (mag < 0.85f || mag > 1.15f) { Serial.println("  Not still enough. Hold still and try again."); return; }
  PostureRef t = postureRef;
  if (stand) t.setStand(v); else t.setSit(v);
  if (t.valid() && !t.separated()) {
    Serial.println("  Standing and sitting directions are less than 45 degrees apart. Not saved.");
    Serial.println("  Make sure the thigh is vertical when standing and horizontal when sitting, then retry.");
    return;
  }
  postureRef = t;
  savePosture();
  ble.postureState = postureState();
  ble.updateInfo();
  Serial.printf("  %s reference saved. %s\n", stand ? "Standing" : "Sitting",
                postureRef.valid() ? "Both references set: posture detection is ON." : "Now capture the other one.");
}

void printRecord(const MinuteRecord& r) {
  Serial.printf("min ts=%lu steps=%u enmo=%.1fmg std=%.1fmg posture=%s class=%s flags=0x%02X\n",
    (unsigned long)r.ts, r.steps, r.enmo_mg10 / 10.0, r.std_mg10 / 10.0,
    POSTURE_NAMES[r.posture & 3], CLS_NAMES[r.cls & 3], r.flags);
}

void handleSerial() {
  if (!Serial.available()) return;
  String line = Serial.readStringUntil('\n'); line.trim();
  if (!line.length()) return;
  char c = line[0];
  if (c == 'h' || c == '?') {
    Serial.println("s=raw stream+rate  c=accel calibration  u=capture STANDING  v=capture SITTING\n"
                   "p=posture now  z=reset timers  k <1-5>=step sensitivity  g=toggle ignore-steps-while-sitting  d=toggle count-twice  r=CSV recording  i=I2C scan  m=last 10 minutes  T <2026-10-25 08:30:00 -07:00>=set time  w=save day summary file  j=print it  f=list files  E yes=erase files  x=status");
  } else if (c == 's') { rawStream = !rawStream; recordCsv = false; rateCount = 0; rateStartMs = millis(); Serial.println(rawStream ? "stream ON" : "stream OFF"); }
  else if (c == 'c') runCalibration();
  else if (c == 'u') doPostureCapture(true);
  else if (c == 'v') doPostureCapture(false);
  else if (c == 'p') Serial.printf("angle to stand %.0f deg, to sit %.0f deg\nstand ref %s (%.2f %.2f %.2f)  sit ref %s (%.2f %.2f %.2f)  now: %s\n",
      PostureRef::angleDeg(postureRef.stand, liveX, liveY, liveZ), PostureRef::angleDeg(postureRef.sit, liveX, liveY, liveZ),
      postureRef.haveStand ? "SET" : "none", postureRef.stand[0], postureRef.stand[1], postureRef.stand[2],
      postureRef.haveSit ? "SET" : "none", postureRef.sit[0], postureRef.sit[1], postureRef.sit[2],
      POSTURE_NAMES[postureStable & 3]);
  else if (c == 'i') i2cScan();
  else if (c == 'm') { int n = ring.size(); for (int i = max(0, n - 10); i < n; i++) printRecord(ring.at(i)); }
  else if (c == 't') { uint32_t e = strtoul(line.substring(1).c_str(), nullptr, 10); uint8_t b[4] = {(uint8_t)e, (uint8_t)(e >> 8), (uint8_t)(e >> 16), (uint8_t)(e >> 24)}; applyTime(b, 4); }
  else if (c == 'T') { String t = line.substring(1); t.trim(); applyTime((const uint8_t*)t.c_str(), t.length()); }
  else if (c == 'w') { if (saveSummaries()) { Serial.println("Saved. Files on the band:"); listFiles(); } }
  else if (c == 'j') { if (saveSummaries()) { Serial.println("---- day summary (copy everything between the lines into a .json file) ----"); Serial.println(fullJson); Serial.println("---- end ----"); } }
  else if (c == 'f') listFiles();
  else if (c == 'E') { if (line.indexOf("yes") > 0 && fsOk) { LittleFS.format(); memset(baseSlots, 0, sizeof baseSlots); Serial.println("All saved summary files erased."); } else Serial.println("To erase every saved summary file type:  E yes"); }
  else if (c == 'k') { int n = line.substring(1).toInt(); if (n >= 1 && n <= 5) setStepSettings((stepSettingsByte() & ~7) | n); else Serial.println("usage: k 1..5 (1 = fewest steps counted, 5 = most sensitive)"); }
  else if (c == 'g') setStepSettings(stepSettingsByte() ^ 8);
  else if (c == 'd') setStepSettings(stepSettingsByte() ^ 16);
  else if (c == 'r') { recordCsv = !recordCsv; rawStream = false; if (recordCsv) Serial.println("t_ms,ax,ay,az,steps,posture"); else Serial.println("# recording stopped"); }
  else if (c == 'z') { totals.reset(); publishTotals(); Serial.println("timers reset"); }
  else if (c == 'x') { Serial.printf("imu=%d cal=%d posture_cal=%d synced=%d stored=%u ble=%d\n", imuOk, cal.valid, postureRef.valid(), synced, ring.size(), (int)ble.connected); printTotals(); Serial.printf("step settings: sensitivity %u, ignore steps while sitting %s, count twice %s\n", stepSens, stepGate ? "ON" : "off", stepDouble ? "ON" : "off"); }
}

// ---------- live timers ----------
void printTotals() {
  auto hms = [](uint32_t s, char* o) { snprintf(o, 12, "%02lu:%02lu:%02lu", (unsigned long)(s / 3600), (unsigned long)((s / 60) % 60), (unsigned long)(s % 60)); };
  char a[12], b[12], c[12];
  hms(totals.sit, a); hms(totals.stand, b); hms(totals.other, c);
  Serial.printf("timers  sitting %s  standing %s  other %s  steps %lu\n", a, b, c, (unsigned long)totals.steps);
}
void publishTotals() {
  ble.totSit = totals.sit; ble.totStand = totals.stand; ble.totOther = totals.other; ble.totSteps = totals.steps;
  ble.totRun = (uint16_t)(totals.runSec > 65535 ? 65535 : totals.runSec); ble.totPosture = totals.runPosture;
}

// ---------- live posture: smoothed, hysteresis, 0.6 s debounce ----------
void updateLivePosture() {
  uint8_t cand = postureRef.classify(liveX, liveY, liveZ, postureStable);
  if (cand == postureStable) { posturePending = cand; return; }
  if (cand != posturePending) { posturePending = cand; posturePendingSince = millis(); return; }
  if (millis() - posturePendingSince >= POSTURE_DEBOUNCE_MS) {
    postureStable = cand;
    ble.livePosture = cand;
    ble.liveDirty = true;                       // push to the phone/laptop right away
    Serial.printf("posture -> %s\n", POSTURE_NAMES[cand & 3]);
  }
}

// ---------- once per minute ----------
void closeMinute() {
  minuteStartMs += 60000;
  uint32_t upS = millis() / 1000;
  uint32_t ts = synced ? epochOffset + upS : upS;
  MinuteRecord r = agg.close(ts, synced);
  ring.push(r);
  ble.postureState = postureState();
  ble.updateInfo();
  printRecord(r);
  printTotals();
  if (synced && ++minutesSinceSave >= 10) { minutesSinceSave = 0; saveSummaries(); }   // keep the file on the band up to date
}

void setup() {
  Serial.begin(115200);
  delay(1500);   // native USB needs a moment before the monitor attaches
  Serial.println("\nLifeTwin band fw " + String(FW_MAJOR) + "." + String(FW_MINOR) + " (thigh pocket)");
  Wire.begin(PIN_SDA, PIN_SCL);
  Wire.setClock(400000);
  i2cScan();

  imuOk = imu.begin(MPU_ADDR);
  Serial.println(imuOk ? "MPU6050 OK" : "MPU6050 NOT FOUND (check wiring / AD0 address)");
  loadCalib(cal);
  Serial.println(cal.valid ? "Accel calibration loaded" : "No accel calibration yet: send 'c'");
  loadPosture();
  loadStepSettings();
  snprintf(fwStr, sizeof fwStr, "%d.%d", FW_MAJOR, FW_MINOR);
  { Preferences p; p.begin("lt", true); tzMin = p.getShort("tz", 0); p.end(); }
  fsOk = LittleFS.begin(true);
  Serial.println(fsOk ? "Flash file system OK (day summaries are saved here)" : "Flash file system FAILED: check Tools > Partition Scheme (use one with SPIFFS). Summaries still work over Bluetooth.");
  Serial.println(postureRef.valid() ? "Posture references loaded" : "No posture references yet: send 'u' (standing) and 'v' (sitting), or use the web page");
  agg.setPostureRef(&postureRef);
  ble.postureState = postureState();
  ble.begin(&ring);

  nextImuUs = micros();
  minuteStartMs = rateStartMs = lastTotMs = millis();
  Serial.println("Send 'h' for commands.");
}

void loop() {
  uint32_t nowUs = micros();
  if ((int32_t)(nowUs - nextImuUs) >= 0) {
    nextImuUs += IMU_PERIOD_US;
    if ((int32_t)(nowUs - nextImuUs) > (int32_t)(5 * IMU_PERIOD_US)) nextImuUs = nowUs + IMU_PERIOD_US;  // resync if we fell far behind

    float x, y, z;
    if (imuOk && readCalibrated(x, y, z)) {
      float mag = sqrtf(x * x + y * y + z * z);
      agg.addSample(x, y, z);
      bool gateOpen = !stepGate || postureStable != POSTURE_SITTING;   // a seated leg bounce is not walking
      uint8_t add = stepper.update(mag, millis(), gateOpen);
      if (add) { uint16_t n = (uint16_t)add * (stepDouble ? 2 : 1); agg.addSteps(n); totals.addSteps(n); }
      liveX += 0.05f * (x - liveX); liveY += 0.05f * (y - liveY); liveZ += 0.05f * (z - liveZ);   // ~0.4 s smoothing
      updateLivePosture();
      ble.liveEnmoMg = (uint16_t)fmaxf(0, (mag - 1.0f) * 1000.0f);
      ble.liveSteps = agg.stepsSoFar();
      rateCount++;
      if (recordCsv) Serial.printf("%lu,%.4f,%.4f,%.4f,%lu,%u\n", (unsigned long)millis(), x, y, z, (unsigned long)totals.steps, postureStable);
      if (rawStream) {
        Serial.printf("%.3f,%.3f,%.3f,|g|=%.3f,stand=%.0fdeg,sit=%.0fdeg,posture=%s\n", x, y, z, mag,
                      PostureRef::angleDeg(postureRef.stand, liveX, liveY, liveZ),
                      PostureRef::angleDeg(postureRef.sit, liveX, liveY, liveZ), POSTURE_NAMES[postureStable & 3]);
        if (millis() - rateStartMs >= 10000) {
          Serial.printf("[rate] %.2f Hz\n", rateCount * 1000.0 / (millis() - rateStartMs));
          rateCount = 0; rateStartMs = millis();
        }
      }
    }
  }
  if (millis() - lastTotMs >= 1000) { lastTotMs += 1000; totals.tickSecond(postureStable); publishTotals(); }
  if (ble.stepSettingsPending) { ble.stepSettingsPending = false; setStepSettings(ble.stepSettingsValue); }
  if (ble.resetTotals) { ble.resetTotals = false; totals.reset(); publishTotals(); Serial.println("timers reset"); }
  if (millis() - minuteStartMs >= 60000) closeMinute();
  if (ble.timePending) { ble.timePending = false; applyTime(ble.timeBuf, ble.timeLen); }
  if (ble.saveRequested) { ble.saveRequested = false; saveSummaries(); }
  if (ble.indexRequested) { ble.indexRequested = false; serveIndex(); }
  if (ble.dayFileRequested) { ble.dayFileRequested = false; serveDayFile(); }
  if (ble.ackDayRequested) { ble.ackDayRequested = false; ackDay(); }
  if (ble.sendFileRequested) { ble.sendFileRequested = false; if (saveSummaries()) ble.startFileStream(fullJson, strlen(fullJson)); }
  if (ble.capStand) { ble.capStand = false; doPostureCapture(true); }   // 05 = standing
  if (ble.capSit) { ble.capSit = false; doPostureCapture(false); }     // 06 = sitting
  ble.service(millis());
  handleSerial();
}
