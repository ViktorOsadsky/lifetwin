# Wearable activity tracker prototype plan

Prototype plan for a wrist wearable that records activity and offers the results to LifeTwin. This implements the spec's future [Wearable Integrations](../projectspec.md) idea at hackathon scale. Read [MASTER_PLAN.md](../MASTER_PLAN.md) and [team-plan.md](team-plan.md) first. Nothing here is implemented yet. The **Owner** column is `TBD` until the team assigns one; this document does not create a track.

Status: **draft.** D1, D2, D3 and D5 were ruled on 2026-10-23. D4 is open (see [decisions](#decisions)). Hardware availability was checked on Hive (Cal Hacks 13.0) on 2026-10-23.

## Goal and scope

Build a wrist band that measures movement, turns it into daily activity summaries on the device and phone, and offers a **suggested** weekly activity value that the user confirms before it enters their profile.

| In scope (prototype) | Out of scope |
| --- | --- |
| Steps, cadence, activity intensity minutes, wear time, rest windows, skin-temperature trend | Diagnosis, alerts, fall detection, arrhythmia detection or any medical claim |
| BLE link to the Flutter app, on-device storage only | Accounts, cloud sync, storing wearable data on the server |
| Suggested `exercise_minutes_weekly` (and, as a stretch goal, `sleep_hours`) for user confirmation | Silently changing the confirmed baseline or a prediction |
| Educational, cited activity context | Any invented survival benefit for steps or wearable metrics |

## Hardware (bill of materials)

The 5-unit Hive limit applies. The heartbeat module and OLED were unavailable at checkout time.

| Part | Source | Status | Role |
| --- | --- | --- | --- |
| ESP32 dev board | Hive | **In cart** | MCU with BLE; samples, processes, buffers |
| MPU 6050 (accelerometer + gyroscope, I²C) | Hive (13 in stock) | To add | Movement for every activity metric |
| Temperature sensor module KY-001 (DS18B20) | Hive (2 in stock) | To add (optional) | Skin-temperature trend |
| Cal Hacks Arduino Kit (UNO R3) | Hive (1 in stock) | To add | Breadboard + 5 M-F and 5 M-M wires; the UNO is a spare MCU |
| Female-to-male Dupont wire **or** GY-6500 | Hive | Fallback if the UNO kit is gone | Wiring / backup motion sensor |
| USB power bank, ESP32 data cable, strap/velcro | Bring your own | Needed | Power and wearing. Hive has no LiPo/charger parts |
| Heart-rate sensor (MAX30102 or similar, I²C) | Team sourcing outside Hive (D5) | Coming | Pulse; joins the MPU-6050's I²C bus, so no extra wires to the ESP32 |

### Wiring

```
ESP32 3V3    → breadboard + rail → MPU6050 VCC, KY-001 VCC
ESP32 GND    → breadboard − rail → MPU6050 GND, KY-001 GND
ESP32 GPIO21 → MPU6050 SDA   (default ESP32 I²C)
ESP32 GPIO22 → MPU6050 SCL
ESP32 GPIO4  → KY-001 signal (1-Wire; the module has its pull-up)
Later: heart-rate sensor VIN/GND → rails, SDA/SCL → the same SDA/SCL rows as the MPU6050
```

Confirm the pin labels on the specific ESP32 board before powering it. Never feed 5 V into the sensors' data pins.

## Architecture

```
MPU6050 ─I²C 50 Hz─┐
DS18B20 ─1-Wire 1/min┤→ ESP32 firmware ──BLE GATT──→ Flutter app (on-device only) ──user confirms──→ profile draft
                     │   • filter + step detection        • daily aggregation          • existing validation/API
                     │   • per-minute summaries           • activity panel, evidence    • predictions unchanged
                     │   • 24 h ring buffer               • suggested values             until confirmed
```

- **Raw samples never leave the band.** Firmware sends per-minute summaries (about 12 bytes each). A 24 h ring buffer is roughly 17 KB, which fits in ESP32 RAM.
- **The app owns aggregation and suggestions.** Under D2 (a) no contract change is needed. Under D1, aggregated summaries may go to the server, which uses them within the request and never stores or logs them.
- **Three separate states**, following the master plan's separation rules: wearable summaries (sensor estimates) ≠ confirmed health inputs ≠ quiz/game health. Activity may drive a cosmetic twin reaction, but never game health or a prediction.

## Metric definitions

Prototype thresholds are engineering targets for this build, not validated research cut-points, unless a source is cited.

| Metric | How it is computed | Evidence / caveat |
| --- | --- | --- |
| Acceleration magnitude (ENMO) | √(x²+y²+z²) − 1 g, negatives set to 0, in milli-g, averaged per 5 s epoch | ENMO is a standard raw-accelerometer metric ([van Hees et al. 2013](https://pubmed.ncbi.nlm.nih.gov/23626718/)) |
| Steps | Low-pass filtered magnitude, adaptive-threshold peak detection, ≥250 ms between peaks | Engineering heuristic; validate by manual count (HW-03) |
| Cadence | Steps per minute | Step intensity did not add to step count in NHANES ([Saint-Maurice et al. 2020](https://www.nih.gov/news-events/nih-research-matters/number-steps-day-more-important-step-intensity)), so cadence is displayed only |
| Intensity minutes | Each minute is classified sedentary / light / moderate-to-vigorous (MVPA) from epoch ENMO using published wrist cut-points | Cut-points come from research-grade devices (e.g., Hildebrand et al. 2014, *Med Sci Sports Exerc* 46(9):1816–24). **The owner must take the exact values from the primary paper** and treat MPU-6050 output as approximate. Agreement is only moderate even on research devices ([review](https://sportsmedicine-open.springeropen.com/articles/10.1186/s40798-025-00820-1/tables/4)) |
| Weekly MVPA minutes | Sum of MVPA minutes over valid days, scaled to 7 days | Compared against the WHO target of 150–300 min/week moderate ([Bull et al. 2020](https://doi.org/10.1136/bjsports-2020-102955)) |
| Wear time / valid day | Non-wear = near-zero variance on all axes for ≥30 min. A valid day has ≥10 h wear | ≥10 h on ≥4 days is the NHANES accelerometry convention (Troiano et al. 2008, *Med Sci Sports Exerc* 40(1):181–8). A hackathon demo will not reach 4 days, so the app must say so |
| Rest window (stretch) | Longest low-movement window from wrist-angle variability | Simplified from [van Hees et al. 2018](https://doi.org/10.1038/s41598-018-31266-z). A rough estimate, labeled as such |
| Skin temperature | DS18B20, 1 sample/min | Wrist skin ≠ core temperature. Show a trend against the user's own baseline, never a fever reading |
| Heart rate | Optical PPG sensor once sourced (D5): beat detection → per-minute mean HR, resting-HR candidate | Hobby PPG is noisy during movement. Informational only. Not a profile field and not a model input unless Track A adds one |

## Feature list (GitHub issue candidates)

Each row is sized to become one issue. IDs are stable so issues and PRs can reference them.

### Firmware and hardware

| ID | Feature | Acceptance criteria | Depends on |
| --- | --- | --- | --- |
| HW-01 | Bench bring-up | ESP32 reads the MPU-6050 at 50 Hz ±2% for 10 min and logs to serial; ±4 g range | Parts |
| HW-02 | Accelerometer calibration | At rest in 6 orientations, magnitude is 1 g ±3% after offset correction | HW-01 |
| HW-03 | Step detection | Within ±10% of a manual count on 3 × 100-step walks; ≤5% spurious steps over 10 min of desk work | HW-02 |
| HW-04 | Per-minute summaries | Minute record: timestamp, steps, mean ENMO, intensity class, wear flag, temperature. Stored in a 24 h ring buffer | HW-03 |
| HW-05 | Non-wear detection | Band left on a table for 30 min is marked non-wear; normal sitting is not | HW-04 |
| HW-06 | Skin-temperature sampling (optional) | 1/min reading; a missing sensor yields `null`, not a crash | HW-01 |
| HW-07 | BLE GATT service | Device-info, time-sync (write), minute-history (read/notify) and optional live-magnitude characteristics; reconnect resumes from the last unsent minute | HW-04 |
| HW-08 | Wearable build | Strap, power bank, cable routing; ≥4 h runtime; the sensor sits flat on the wrist | HW-07 |
| HW-09 | Heart-rate sensor | Sensor shares the I²C bus with the MPU-6050. Per-minute mean HR within ±5 bpm of a reference reading at rest; minutes with motion are flagged low-confidence | Sensor sourced, HW-04 |

### App (Flutter)

| ID | Feature | Acceptance criteria | Depends on |
| --- | --- | --- | --- |
| APP-01 | Mascot-led band pairing | Pairing happens inside the game room. Bluetooth-denied, off and not-found states are handled | HW-07 |
| APP-02 | Sync and on-device aggregation | Minute records stay in memory. Daily steps, MVPA/light/sedentary minutes, wear time and valid-day status are computed. Nothing is sent to the server or logged | APP-01 |
| APP-03 | Activity panel | Today's and the week's summaries, wear-time sufficiency and a "sensor estimate" label. Accessible text alternatives for charts | APP-02 |
| APP-04 | Suggested `exercise_minutes_weekly` | Shows the suggested value, its source and valid-day count. The user confirms, edits or dismisses. Confirmation goes through the same draft/confirm path as the conversation. The baseline is untouched until confirmed | APP-02, D2, D3 |
| APP-05 | Cosmetic twin reaction | The twin animates more energetically after activity. No effect on game health or predictions (test it) | APP-02 |
| APP-06 | Cited activity evidence card | Steps/activity facts quote only the cited sources, as observational associations, with no personal survival number | D-track sources |
| APP-07 | Replay/demo mode | Plays a recorded minute-summary file without hardware, clearly labeled as recorded data | APP-02 |
| APP-08 | Suggested `sleep_hours` (stretch) | From the rest window; labeled rough; same confirmation flow as APP-04 | HW-04, D2 |
| APP-09 | Heart-rate display | Shows band HR (HW-09) as informational only, with a low-confidence state; not stored in the profile | HW-09 |

### Validation and demo

| ID | Feature | Acceptance criteria |
| --- | --- | --- |
| VAL-01 | Step accuracy log | Band vs. manual count vs. phone pedometer on scripted walks; results committed as a short table |
| VAL-02 | Separation tests | Wearable data cannot change quiz health or predictions without confirmation; dismissing a suggestion leaves the profile unchanged |
| VAL-03 | Privacy check | No raw samples or minute records leave the phone. Summaries sent under D1 never appear in server logs, traces, error reports, caches or storage |
| DEMO-01 | Demo script | Pair band → walk → panel updates → suggestion → confirm → existing fortune/experiment flow, plus a replay-mode fallback |

## Phases and exit criteria

| Phase | Work | Exit criteria |
| --- | --- | --- |
| P0 — Parts | Check out MPU 6050, KY-001 and the UNO kit; bring a power bank and cable | All parts in hand; wiring powered and verified |
| P1 — Bench | HW-01, HW-02, HW-06 | Clean 50 Hz stream on serial; calibration passes |
| P2 — Algorithms | HW-03, HW-04, HW-05; VAL-01 started | Step accuracy target met at the bench; minute summaries look right |
| P3 — Link | HW-07, APP-01, APP-02, APP-07 | Phone receives and aggregates minutes; replay mode works without hardware |
| P4 — Product | APP-03, APP-04, APP-05, APP-06 | Suggestion → confirm flow works; separation tests (VAL-02) pass |
| P5 — Wear and demo | HW-08, VAL-01 finished, VAL-03, DEMO-01; HW-09/APP-09 once the sensor arrives; stretch APP-08 | Rehearsed demo on the wrist, with replay as the fallback |

P3's replay mode removes the hardware from the app's critical path: app work can start from a recorded file as soon as HW-04 defines the minute-record format.

## Decisions

These are Tier-1 (data model, privacy boundary, model inputs, spending).

| ID | Decision | Ruling | Consequence for this plan |
| --- | --- | --- | --- |
| D1 | Where wearable data may go | **(b) aggregated summaries may go to the server, processed within the request only, never stored** | Raw samples and minute records stay on the band/phone. The server must not persist, log, trace or cache wearable payloads (extends VAL-03). **Open:** whether summaries may be forwarded to the AI agents. [apple-health.md](apple-health.md) already sends Apple Health samples to the agents through the server, so the wearable could follow the same path. The exact summary fields need a contract decision with Track B, alongside `apple_health_samples.v0` |
| D2 | How wearable values enter the profile | **(a) for now:** a suggestion the user confirms; no contract change | APP-04/APP-08 use the existing draft → confirm path. A provenance field can be revisited with Tracks A/B |
| D3 | Device-measured vs. self-reported activity | **Device-measured activity will be included in the model** | Track A owns the method and the change is part of deferred prediction work. Until it lands, suggestions carry the device-vs-self-report caveat. The model must be trained on device data comparable to this band (see the note below) |
| D4 | Ownership | **Open** | Team decides; not assigned here |
| D5 | Heart rate | **(c) the team will source a sensor** (MAX30102 or similar) outside Hive | HW-09 and APP-09 added. Heart rate stays informational until a model input is decided |

**Note on D3:** NHANES device data comes from research ActiGraph monitors (hip-worn in 2003–2006, wrist-worn in 2011–2014), summarized in that device's own units. MPU-6050 output is not on the same scale, so a model trained on NHANES device data needs a documented mapping or calibration before this band's values can be fed to it.

## Risks

| Risk | Mitigation |
| --- | --- |
| The last UNO kit or ESP32 is taken | ESP32 is in the cart. Fall back to F-M Dupont wires; the ESP32's pins can connect straight to a sensor breadboard |
| MPU-6050 cut-points don't transfer from research devices | Label minutes as estimates; validate steps (VAL-01); don't overclaim intensity |
| Too little wear data for a valid week | Show valid-day status; replay mode for the demo; the user can always type the value themselves |
| BLE flakiness at a crowded venue | Buffered history + resume (HW-07); replay fallback |
| Wearable data mistaken for medical measurement | "Sensor estimate" labels everywhere; no alerts; cosmetic-only twin reaction |

## Sources

- van Hees VT et al. *Separating movement and gravity components in an acceleration signal…* PLoS ONE 2013;8(4):e61691. <https://pubmed.ncbi.nlm.nih.gov/23626718/>
- van Hees VT et al. *Estimating sleep parameters using an accelerometer without sleep diary.* Sci Rep 2018;8:12975. <https://doi.org/10.1038/s41598-018-31266-z>
- Hildebrand M et al. *Age group comparability of raw accelerometer output from wrist- and hip-worn monitors.* Med Sci Sports Exerc 2014;46(9):1816–24. Cut-point values to be verified from the primary paper.
- Troiano RP et al. *Physical activity in the United States measured by accelerometer.* Med Sci Sports Exerc 2008;40(1):181–8.
- Saint-Maurice PF et al. *Association of daily step count and step intensity with mortality among US adults.* JAMA 2020;323(12):1151–60. Summary: <https://www.nih.gov/news-events/nih-research-matters/number-steps-day-more-important-step-intensity>
- Paluch AE et al. *Daily steps and all-cause mortality: a meta-analysis of 15 international cohorts.* Lancet Public Health 2022;7(3):e219–28. <https://doi.org/10.1016/S2468-2667(21)00302-9>
- Bull FC et al. *World Health Organization 2020 guidelines on physical activity and sedentary behaviour.* Br J Sports Med 2020;54:1451–62. <https://doi.org/10.1136/bjsports-2020-102955>

All step and activity studies above are observational. They support educational context, not a modeled or causal survival benefit for an individual.
