#pragma once
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
