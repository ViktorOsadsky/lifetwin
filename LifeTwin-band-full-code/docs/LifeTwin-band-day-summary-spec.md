# LifeTwin band: day summary file and end-of-day iPhone transfer

> **Update (firmware 0.8 and the app files in `app-integration/`):** the Bluetooth transfer described in section 3 is now specified in `band-ble-contract.md` and implemented on both sides. The band lists its saved days (`0D`), sends any day's file by date (`0C`), and deletes a stored finished day on request (`0E`). The phone connects to the band; the app files feed the existing `BandFileIntake`. Section 3 below is the earlier design and is kept for reference. Not yet run on a real band and iPhone together.


For the app owner. Status: **draft proposal**. Nothing here is in the repo's contracts yet (the existing Health contract is `apple_health_samples.v0`; this would be a new Track B contract). The band firmware (0.6) and `lifetwin-band.html` implement everything marked **built**. Everything marked **not built** is the later iteration.

## 1. What happens today (built)

1. Open `lifetwin-band.html` in Chrome or Edge on a laptop. Click **Connect band**. The clock is set and stored minutes are downloaded.
2. **Live timers** show elapsed sitting, standing, steps and "current position for…". The band counts them itself, so they keep running with the page closed. *Reset timers* restarts them.
3. **Download day summary (JSON)** produces the file below for the selected day.
4. Minute-by-minute data can be exported as CSV for testing.

The band keeps the last **24 hours** of minute records in RAM. **They are lost when the band loses power**, so download before switching off.

## 2. Day summary file (`lifetwin.band_day.v0`)

Aggregates only: no per-minute timestamps, matching decision D1 (raw minute records stay on the band and phone; only aggregated summaries may reach the server, processed within the request and never stored). It carries what plan item APP-02 lists: steps, activity minutes, wear time and valid-day status.

| Field | Meaning |
|---|---|
| `date`, `timezone_offset_minutes` | Local calendar day the summary covers |
| `device` | Mount, firmware version, minute-record format |
| `coverage.wear_minutes` | Recorded minutes minus "not worn" minutes |
| `coverage.valid_day` | `true` when wear minutes ≥ 600 (10 h, the plan's valid-day rule) |
| `minutes.*` | Minutes in each category (sitting or lying, standing, walking light / moderate, running, other, not worn, positions not saved) |
| `moderate_vigorous_minutes` | Walking moderate + running. This feeds the suggested `exercise_minutes_weekly` |
| `steps`, `sit_to_stand_transitions`, `longest_sitting_minutes` | Day totals |
| `hourly[]` | Per-hour minutes and steps (24 entries) |

**Caveats that travel with the file:** device estimates, not medical measurements; a thigh sensor counts lying down as sitting; walking intensity uses provisional steps-per-minute cut-offs (100 and 130, from memory, unverified); sitting time is a candidate model input only if Track A adds it (decision D6).

Example (synthetic data; `hourly` shortened here):

```json
{
  "schema": "lifetwin.band_day.v0",
  "date": "2026-10-24",
  "timezone_offset_minutes": 0,
  "generated_at": "2026-10-24T23:10:00.000Z",
  "device": {
    "mount": "thigh_pocket",
    "firmware": "0.6",
    "record_format": 2
  },
  "coverage": {
    "minutes_recorded": 630,
    "wear_minutes": 630,
    "valid_day": true,
    "first_minute": "08:00",
    "last_minute": "18:29"
  },
  "minutes": {
    "sitting_or_lying": 535,
    "standing": 55,
    "walking_light": 12,
    "walking_moderate": 28,
    "running_vigorous": 0,
    "other_posture": 0,
    "not_worn": 0,
    "positions_not_saved": 0
  },
  "moderate_vigorous_minutes": 28,
  "steps": 3836,
  "sit_to_stand_transitions": 3,
  "longest_sitting_minutes": 260,
  "hourly": [
    {
      "hour": 8,
      "sitting_lying_min": 60,
      "standing_min": 0,
      "walking_min": 0,
      "running_min": 0,
      "other_min": 0,
      "not_worn_min": 0,
      "steps": 0
    },
    {
      "hour": 9,
      "sitting_lying_min": 30,
      "standing_min": 25,
      "walking_min": 5,
      "running_min": 0,
      "other_min": 0,
      "not_worn_min": 0,
      "steps": 350
    },
    {
      "hour": 10,
      "sitting_lying_min": 53,
      "standing_min": 0,
      "walking_min": 7,
      "running_min": 0,
      "other_min": 0,
      "not_worn_min": 0,
      "steps": 490
    },
    {
      "hour": 11,
      "sitting_lying_min": 57,
      "standing_min": 0,
      "walking_min": 3,
      "running_min": 0,
      "other_min": 0,
      "not_worn_min": 0,
      "steps": 336
    },
    {
      "hour": 12,
      "sitting_lying_min": 55,
      "standing_min": 0,
      "walking_min": 5,
      "running_min": 0,
      "other_min": 0,
      "not_worn_min": 0,
      "steps": 560
    },
    {
      "hour": 13,
      "sitting_lying_min": 20,
      "standing_min": 30,
      "walking_min": 10,
      "running_min": 0,
      "other_min": 0,
      "not_worn_min": 0,
      "steps": 1050
    },
    {
      "hour": 14,
      "sitting_lying_min": 50,
      "standing_min": 0,
      "walking_min": 10,
      "running_min": 0,
      "other_min": 0,
      "not_worn_min": 0,
      "steps": 1050
    }
  ],
  "notes": [
    "Device estimates, not medical measurements.",
    "A thigh sensor counts lying down as sitting.",
    "Walking intensity uses provisional steps-per-minute cut-offs.",
    "A valid day has at least 600 wear minutes."
  ]
}
```

## 3. End-of-day flow to the iPhone (not built)

**Your intent as I understand it:** at night the user ends the day on the band, the band sends the day to the phone, and the user then switches it off. Note a hard power switch cannot transfer anything (the band is off), so the transfer has to happen *before* power is cut.

Proposed sequence, using GATT calls the page already makes:

1. User presses an **End day** button on the band (long press). The band lights its status LED and advertises "ready to sync".
2. The iPhone app (scanning for service `4c540001-…` in the background, or opened by the user) connects.
3. App writes the current time to `…0003` (4 bytes, unix seconds, little-endian). Boot-relative minutes are converted on the band.
4. App reads `…0002`. **Check the format byte is `2`** and firmware ≥ 0.6.
5. App enables notifications on `…0005` and writes `01` + the last timestamp it already holds (4 bytes) to `…0004`. The band streams one 12-byte record per notification, then a record of twelve `0xFF` bytes as the end marker. Resume after a dropped link by repeating step 5 with the last timestamp received.
6. App builds the day summary from the minutes (`categorize` / `summarizeDay` / `buildDaySummary` in the page's JavaScript are the reference implementation), stores the file on the phone, and may use it for APP-04 (suggested weekly exercise minutes, user-confirmed).
7. *(new)* App writes an **acknowledge** (`08`) so the band shows a green LED and goes to sleep. The user then switches it off.

**Minute record (12 bytes, little-endian):** `ts u32, steps u8, enmo_mg10 u16, cls u8, flags u8, std_mg10 u16, posture u8` (posture 0 unknown, 1 sitting or lying, 2 standing, 3 other; flags 1 not worn, 2 still, 4 motion, 8 positions not saved, 16 time unsynced). A run of 30+ consecutive "still" minutes is not-worn: the band only flags from the 30th minute, so the app must back-fill the earlier 29.

### What still has to be built

| Item | Notes |
|---|---|
| **Flash log of minute records** | **Partly built (firmware 0.8):** the band now saves the *day summary* JSON to flash (LittleFS) every 10 minutes, so a power-off no longer loses the totals. The individual minute records are still lost at power-off, and the clock must be set again after every power-off |
| End-day button, status LED, acknowledge command `08`, deep sleep | Waiting on the parts decision (the cart has a push button; RGB LED and battery parts are not chosen) |
| iOS app BLE client | Web Bluetooth does **not** exist on iPhone. The app needs CoreBluetooth (for Flutter, a BLE plugin such as `flutter_blue_plus`); I have not tested iOS background behaviour, and iOS limits background scanning and connection timing |
| Pairing / encryption | The prototype service is open. Use bonding before this carries a real person's data |
| Final UUIDs and contract | Mine are placeholders. Agree them, plus this file's schema, with Track B |
| Timezone | The app knows the phone's timezone; the band doesn't. The summary's `date` should be the phone's local day |
