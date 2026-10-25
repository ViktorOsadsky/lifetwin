# LifeTwin band: full code (firmware 0.8, thigh pocket)

The complete code for the band: an ESP32 with an MPU-6050, worn in a front trouser pocket on the **thigh**. Record format 2. The single-file sketch in this zip is byte-identical to the one you uploaded (SHA-256 `44cc58bd7614d72645f58a6f73055255c9bf22844f03c5a2ab903d759df7c058`), so it is the code on your band now.

## What's in the zip
| Folder | What it is |
|---|---|
| `arduino/lifetwin_band/` | **The firmware as a normal multi-file Arduino sketch.** Open `lifetwin_band.ino`; the other files appear as tabs. Edit this one. |
| `arduino/lifetwin_band_single_file/` | The same code joined into one file (what is on your band). Paste-and-upload friendly. |
| `tests/` | Logic tests that run on a computer, no board needed: `./run_tests.sh` |
| `tools/hex_to_json.py` | Turns hex copied from nRF Connect into a `.json` file |
| `test-page/lifetwin-band.html` | The test web page (Chrome or Edge on a laptop). Testing only |
| `docs/` | nRF Connect guide, build guide, Bluetooth contract, day-summary spec |

Not in here: the 3D-printed case, and the Flutter app files (separate zips).

### The firmware files (`arduino/lifetwin_band/`)
| File | Does |
|---|---|
| `lifetwin_band.ino` | Setup and main loop, serial commands, calibration, posture capture, live timers, saving day files, time setting |
| `config.h` | Pins, sample rate, version, and every tunable threshold |
| `mpu6050.h`, `calib.h` | Sensor driver; six-pose calibration stored in flash |
| `steps.h` | Step detector |
| `minute.h` | Posture decision, per-minute summaries, 24-hour memory, live timers |
| `daysummary.h` | Builds the day summary and its JSON (same `lifetwin.band_day.v0` the app reads), date parsing, saved-day list |
| `ble_service.h` | Bluetooth service and file streaming |

## Hardware
ESP32-S3 (or C3) + MPU-6050. `3V3 → VCC`, `GND → GND`, `G8 → SDA`, `G9 → SCL`; leave AD0 and INT unconnected (address `0x68`). Pins and address are in `config.h`.

## Software setup
1. Arduino IDE with the Espressif ESP32 board package.
2. Library: **NimBLE-Arduino 2.x** (Library Manager). Nothing else.
3. *Tools*: board **ESP32S3 Dev Module** (C3 board for a C3), **USB CDC On Boot: Enabled**, and a **Partition Scheme with SPIFFS** (for example "Default 4MB with spiffs"). The SPIFFS area is where the band saves its day files.
4. Open `arduino/lifetwin_band/lifetwin_band.ino` (or the single-file one) and upload. Serial Monitor at **115200**, line ending **Newline**.
5. Expect: `LifeTwin band fw 0.8 (thigh pocket)`, `MPU6050 OK`, `Flash file system OK`.

## First-time set-up, in order
1. `c`: six-pose accelerometer calibration (kept in flash).
2. `u` then `v`: save your **standing** and **sitting** positions with the band in the pocket (5 s to get into position, then 3 s still). Without these, posture is "unknown".
3. `T 2026-10-25 08:30:00 -07:00`: set the clock (local time and zone). **Needed after every power-off.** The app or page also sets it when it connects.

## Serial commands
`h` help · `s` raw stream · `r` CSV recording for step tuning · `i` I²C scan · `c` calibrate · `u` save standing · `v` save sitting · `p` posture and angles now · `z` reset timers · `k 1-5` step sensitivity · `g` ignore steps while sitting on/off · `d` count each step twice on/off · `m` last 10 minutes · `T <time>` set clock · `w` save day files now · `j` print today's JSON file · `f` list saved files · `E yes` erase saved files · `x` status.

## What it does and where things live
| Kept in | What |
|---|---|
| Flash (survives power-off) | the program; sensor calibration; saved standing/sitting positions; step settings; time zone; the day summary files `/day_YYYY-MM-DD.json` (rewritten every 10 minutes once the clock is set) |
| RAM (lost at power-off) | the last 24 hours of per-minute records; live timers; the clock; the current partial minute |

## Bluetooth (details in `docs/band-ble-contract.md`)
Service `4c540001-7b2a-4f0e-9a51-0d1e2c3b4a50`; characteristics `…0002` to `…0008` (info, clock, control, minute history, live posture, live timers, summary). The phone connects to the band. Control codes written to `…0004`: `0A` save now · `0B` send latest day · `0D` list saved days · `0C`+date send a day · `0E`+date delete a finished day · `07` reset timers · `05`/`06` save standing/sitting · `09`+byte step settings · `03`/`04` live on/off · `01`+time stream minute records.

## Tests
`cd tests && ./run_tests.sh` builds and runs the logic tests (steps on simulated walking, posture for any board rotation, minute records, timers, non-wear, day summary, restart-merge, one-record-per-minute). They need `g++` with C++17.

## Know before relying on it
- The step detector, posture rules and thresholds were developed and tested on **simulated** signals and on your own tests, not on a validated reference. Intensity cut-offs (`CADENCE_*` in `config.h`) are provisional. Everything is a sensor estimate.
- A thigh sensor counts **lying down as sitting**. It only tells sitting from standing on the thigh, not the lower leg.
- No pairing or encryption on Bluetooth yet. Anyone in range can read the band.
- The clock is lost at power-off; minutes recorded before it is set are lost if the band is switched off first.
- The firmware's flash writing and Bluetooth sending were checked by compiling and by tests on a computer; hardware behaviour beyond what you have run yourself is untested.
