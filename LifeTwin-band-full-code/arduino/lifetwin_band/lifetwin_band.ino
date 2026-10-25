// LifeTwin band firmware v0.8 - ESP32 + MPU-6050 worn in a THIGH POCKET
// Measures: steps, walking cadence, posture (sitting / standing / other), wear time.
// Thigh horizontal reads as "sitting" (lying down looks the same). Raw samples never leave the band.
//
// Library (Arduino Library Manager): NimBLE-Arduino (>= 2.0)
// Board: ESP32-S3 -> "ESP32S3 Dev Module", ESP32-C3 -> "ESP32C3 Dev Module",
//        both with "USB CDC On Boot: Enabled"

#include <Wire.h>
#include "config.h"
#include "mpu6050.h"
#include "calib.h"
#include "steps.h"
#include "minute.h"
#include "daysummary.h"
#include <LittleFS.h>
#include "ble_service.h"

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
