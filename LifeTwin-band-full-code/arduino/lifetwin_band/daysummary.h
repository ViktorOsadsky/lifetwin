#pragma once
// Day summary built ON THE BAND from its minute records, so no web page or app is needed to make it.
// Pure C++ so it can be host-tested. It mirrors the logic in lifetwin-band.html (categorize, not-worn
// back-fill, sit-to-stand transitions, hourly breakdown) and writes the same "lifetwin.band_day.v0" JSON.
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include "minute.h"

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
