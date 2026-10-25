#pragma once
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
