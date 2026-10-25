// Unit tests for the band-side day summary. g++ -std=c++17 -I../lifetwin_band day_unit_test.cpp -o day_unit_test
#include <cstdio>
#include <cstdlib>
#include <string>
#include "daysummary.h"
static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); fails++; } else { printf("ok:   "); printf(__VA_ARGS__); printf("\n"); } } while (0)
int main() {
  // ---- calendar ----
  { int y, m, d; civilFromDays(daysFromCivil(2026, 10, 24), y, m, d); CHECK(y == 2026 && m == 10 && d == 24, "civil date round trip 2026-10-24");
    CHECK(daysFromCivil(1970, 1, 1) == 0 && daysFromCivil(2000, 3, 1) == 11017, "epoch day 0 and 2000-03-01 = 11017");
    civilFromDays(daysFromCivil(2028, 2, 29), y, m, d); CHECK(y == 2028 && m == 2 && d == 29, "leap day 2028-02-29"); }
  // ---- typed time ----
  { uint32_t u; int16_t tz;
    CHECK(parseLocalTime("2026-10-25 08:30:00 -07:00", 0, u, tz) && u == 1792942200u && tz == -420, "typed time '2026-10-25 08:30:00 -07:00' -> unix %lu, zone -420", (unsigned long)u);
    CHECK(parseLocalTime("2026-10-25T08:30:00-07:00", 0, u, tz) && u == 1792942200u && tz == -420, "ISO form with T and no space");
    CHECK(parseLocalTime("2026-10-25 15:30:00 Z", 0, u, tz) && u == 1792942200u && tz == 0, "UTC 'Z' form");
    CHECK(parseLocalTime("2026-10-25 08:30:00", -420, u, tz) && u == 1792942200u && tz == -420, "no zone typed keeps the zone already set (-420)");
    CHECK(parseLocalTime("2026-10-25 21:00:00 +05:30", 0, u, tz) && tz == 330 && u == 1792942200u, "India +05:30: 21:00 local = the same moment (%lu)", (unsigned long)u);
    CHECK(parseLocalTime("2026-10-25 08:30:00 -0700", 0, u, tz) && tz == -420, "compact zone -0700");
    CHECK(!parseLocalTime("hello", 0, u, tz) && !parseLocalTime("2026-13-40 25:61:00", 0, u, tz), "garbage and impossible times are rejected"); }
  // ---- compact JSON must fit one Bluetooth read (512 bytes) even at the extremes ----
  { DayAgg d; memset(&d, 0, sizeof d); d.dayKey = daysFromCivil(2026, 12, 31);
    for (int c = 0; c < CAT_COUNT; c++) { d.minutes[c] = 1440; }
    d.steps = 4000000000u; d.transitions = 65535; d.longestSit = 1440; d.recorded = 1440; d.wear = 1440; d.firstStart = 1792800000u; d.lastStart = 1792886340u;
    static char buf[8192]; size_t n = dayToJson(d, -840, "0.8", 2, 1792900000u, 0, buf, sizeof buf);
    CHECK(n <= 512, "HEADLINE JSON worst case (every number maxed, 4 billion steps) is %zu bytes (limit 512 for one Bluetooth read)", n);
    size_t nf = dayToJson(d, -840, "0.8", 2, 1792900000u, 1, buf, sizeof buf);
    CHECK(nf < 4500, "full JSON with hourly list worst case is %zu bytes (buffer 4608)", nf);
    char small[100]; size_t ns = dayToJson(d, 0, "0.8", 2, 1792900000u, 1, small, sizeof small); CHECK(ns < sizeof small && small[ns] == 0, "a too-small buffer is cut off safely, not overrun"); }
  // ---- merge after a restart ----
  { DayAgg a, b; memset(&a, 0, sizeof a); memset(&b, 0, sizeof b);
    a.dayKey = b.dayKey = 100; a.recorded = 100; a.wear = 90; a.minutes[CAT_SITTING] = 70; a.minutes[CAT_NONWEAR] = 10; a.steps = 500; a.transitions = 3; a.longestSit = 40; a.firstStart = 1000; a.lastStart = 9000; a.hourly[9].sit = 60;
    b.recorded = 50; b.wear = 50; b.minutes[CAT_SITTING] = 20; b.minutes[CAT_STANDING] = 30; b.steps = 300; b.transitions = 2; b.longestSit = 55; b.firstStart = 10000; b.lastStart = 13000; b.hourly[9].sit = 20;
    mergeDay(a, b);
    CHECK(a.recorded == 150 && a.wear == 140 && a.minutes[CAT_SITTING] == 90 && a.steps == 800 && a.transitions == 5 && a.longestSit == 55 && a.firstStart == 1000 && a.lastStart == 13000 && a.hourly[9].sit == 80, "merge: totals add up, longest sit = larger, first/last = earliest/latest");
    DayAgg e; memset(&e, 0, sizeof e); mergeDay(e, b); CHECK(e.recorded == 50, "merging into an empty day just copies it"); }
  // ---- unsynced minutes are ignored, and a day boundary splits days correctly ----
  { static RingBuffer ring; static uint8_t cats[RING_MINUTES + 8];
    int32_t day0 = (int32_t)daysFromCivil(2026, 10, 24); uint32_t mid = (uint32_t)(day0 * 86400LL);
    for (int i = 0; i < 10; i++) { MinuteRecord r{}; r.ts = i * 60 + 60; r.flags = FLAG_TIME_UNSYNCED; r.posture = POSTURE_SITTING; ring.push(r); }   // boot-relative: ignored
    for (int i = 0; i < 20; i++) { MinuteRecord r{}; r.ts = mid - 10 * 60 + 60 + i * 60; r.posture = POSTURE_SITTING; r.steps = 1; ring.push(r); }          // 10 min before midnight, 10 after (UTC)
    annotateRing(ring, cats); int32_t keys[4]; int n = collectDayKeys(ring, 0, keys, 4);
    CHECK(n == 2 && keys[0] == day0 - 1 && keys[1] == day0, "20 minutes across midnight form two days (unsynced minutes ignored)");
    DayAgg a, b; buildDay(ring, cats, 0, keys[0], a, nullptr); buildDay(ring, cats, 0, keys[1], b, nullptr);
    CHECK(a.recorded == 10 && b.recorded == 10 && a.steps == 10 && b.steps == 10, "10 minutes and 10 steps land on each side of midnight");
    n = collectDayKeys(ring, -7 * 3600, keys, 4); CHECK(n == 1, "in a UTC-7 zone the same 20 minutes are all one local day"); }
  // ---- restart in the middle of a day: (saved before) + (recorded after) must equal recording straight through ----
  { static RingBuffer A, B, C; static uint8_t ca[RING_MINUTES + 8], cb[RING_MINUTES + 8], cc[RING_MINUTES + 8];
    int32_t day = (int32_t)daysFromCivil(2026, 10, 24); uint32_t t0 = (uint32_t)(day * 86400LL) + 9 * 3600;
    auto mk = [&](RingBuffer& r1, RingBuffer& r2, uint32_t ts, uint8_t posture, uint8_t steps, uint8_t cls) { MinuteRecord m{}; m.ts = ts; m.posture = posture; m.steps = steps; m.cls = cls; r1.push(m); r2.push(m); };
    uint32_t t = t0;
    for (int i = 0; i < 40; i++) { t += 60; mk(A, C, t, POSTURE_SITTING, 0, CLS_SEDENTARY); }
    for (int i = 0; i < 12; i++) { t += 60; mk(A, C, t, POSTURE_UPRIGHT, 60, CLS_LIGHT); }
    t += 20 * 60;                                                                                       // the band is off for 20 minutes
    for (int i = 0; i < 25; i++) { t += 60; mk(B, C, t, POSTURE_SITTING, 0, CLS_SEDENTARY); }
    for (int i = 0; i < 8; i++) { t += 60; mk(B, C, t, POSTURE_UPRIGHT, 110, CLS_MODERATE); }
    annotateRing(A, ca); annotateRing(B, cb); annotateRing(C, cc);
    DayAgg a, b, c, total; buildDay(A, ca, 0, day, a, nullptr); buildDay(B, cb, 0, day, b, nullptr); buildDay(C, cc, 0, day, c, nullptr);
    total = a; mergeDay(total, b);                                                                      // what the band keeps: earlier saved totals + new minutes
    bool same = total.recorded == c.recorded && total.wear == c.wear && total.steps == c.steps && total.transitions == c.transitions && total.longestSit == c.longestSit && total.firstStart == c.firstStart && total.lastStart == c.lastStart;
    for (int k = 0; k < CAT_COUNT; k++) same = same && total.minutes[k] == c.minutes[k];
    for (int h = 0; h < 24; h++) same = same && total.hourly[h].sit == c.hourly[h].sit && total.hourly[h].walk == c.hourly[h].walk && total.hourly[h].steps == c.hourly[h].steps;
    CHECK(same, "a restart mid-day: saved totals + new minutes equal one straight recording (%u + %u = %u minutes, %lu steps, %u transitions)", (unsigned)a.recorded, (unsigned)b.recorded, (unsigned)c.recorded, (unsigned long)c.steps, (unsigned)c.transitions); }
  // ---- one record per minute, whatever the clock does ----
  { static RingBuffer R; static uint8_t cr[RING_MINUTES + 8]; int32_t day = (int32_t)daysFromCivil(2026, 10, 24); uint32_t t0 = (uint32_t)(day * 86400LL) + 9 * 3600;
    // 10 records 60 s apart, then the clock is corrected 40 s back so three more land in minutes that were already counted
    uint32_t t = t0; for (int i = 0; i < 10; i++) { t += 60; MinuteRecord m{}; m.ts = t; m.posture = POSTURE_SITTING; m.steps = 1; R.push(m); }
    t -= 40; for (int i = 0; i < 3; i++) { t += 60; MinuteRecord m{}; m.ts = t; m.posture = POSTURE_SITTING; m.steps = 1; R.push(m); }
    annotateRing(R, cr); DayAgg d; buildDay(R, cr, 0, day, d, nullptr);
    int firstM = floorMod((int64_t)d.firstStart, 86400) / 60, lastM = floorMod((int64_t)d.lastStart, 86400) / 60;
    CHECK(d.recorded <= (unsigned)(lastM - firstM + 1), "after a clock correction the file never claims more minutes (%u) than its first-to-last window (%d)", (unsigned)d.recorded, lastM - firstM + 1);
    // a restart that overlaps minutes already saved must not count them again
    static RingBuffer R2; static uint8_t cr2[RING_MINUTES + 8]; t = t0 + 5 * 60; for (int i = 0; i < 6; i++) { t += 60; MinuteRecord m{}; m.ts = t; m.posture = POSTURE_SITTING; m.steps = 1; R2.push(m); }
    annotateRing(R2, cr2); DayAgg d2; buildDay(R2, cr2, 0, day, d2, d.used); DayAgg tot = d; mergeDay(tot, d2);
    int a = floorMod((int64_t)tot.firstStart, 86400) / 60, b = floorMod((int64_t)tot.lastStart, 86400) / 60;
    CHECK(tot.recorded <= (unsigned)(b - a + 1), "after a restart over minutes already saved: %u minutes counted in a %d-minute window", (unsigned)tot.recorded, b - a + 1); }
  // ---- asking for a saved day by date, and the list of saved days ----
  { int32_t k; CHECK(parseDateKey("2026-10-24", k) && k == (int32_t)daysFromCivil(2026, 10, 24), "date text '2026-10-24' parses to the day number");
    CHECK(!parseDateKey("2026-02-30", k) && !parseDateKey("2026-13-01", k) && !parseDateKey("hello", k), "impossible dates are rejected (Feb 30, month 13, text)");
    int32_t keys[3] = {(int32_t)daysFromCivil(2026, 10, 24), (int32_t)daysFromCivil(2026, 10, 25), (int32_t)daysFromCivil(2026, 10, 27)}; char buf[400];
    size_t n = indexToJson(keys, 3, -420, "0.8", buf, sizeof buf);
    CHECK(std::string(buf) == "{\"schema\":\"lifetwin.band_index.v0\",\"firmware\":\"0.8\",\"timezone_offset_minutes\":-420,\"days\":[\"2026-10-24\",\"2026-10-25\",\"2026-10-27\"]}" && n == strlen(buf), "index JSON lists the saved days: %s", buf);
    int32_t many[40]; for (int i = 0; i < 40; i++) many[i] = (int32_t)daysFromCivil(2026, 10, 1) + i; static char big[1200]; size_t nb = indexToJson(many, 40, 0, "0.8", big, sizeof big);
    CHECK(nb < 1200, "a full index of 40 days is %zu bytes", nb); }
  printf("\n%s\n", fails ? "SOME TESTS FAILED" : "ALL TESTS PASSED");
  return fails ? 1 : 0;
}
