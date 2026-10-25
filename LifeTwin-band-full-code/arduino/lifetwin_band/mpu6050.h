#pragma once
// Minimal MPU-6050 accelerometer driver (no external library). HW-01.
#include <Wire.h>
#include "config.h"

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
