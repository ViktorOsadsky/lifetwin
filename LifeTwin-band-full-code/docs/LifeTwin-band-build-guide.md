# LifeTwin band v0.8: thigh-pocket guide

**Hardware:** ESP32 (G8 = SDA, G9 = SCL) + MPU-6050, in a **front trouser pocket on the thigh**. **Status:** the posture and activity logic passes host tests on simulated signals and random board rotations, and the web page passes tests against a simulated band. None of it has run on a real leg yet.

The earlier **chest** build (firmware 0.4) is kept in `archive/chest-v0.4/` in case you switch again. It is not compatible with this page: the record codes differ.

## 1. What a thigh sensor can and cannot tell

| Situation | Thigh | Detected as | Reliable? |
|---|---|---|---|
| Standing, walking | vertical | **Standing** | Yes |
| Sitting | horizontal | **Sitting** | Yes |
| Lying down | horizontal | **Sitting** (the page calls it "Sitting / lying") | **No: lying looks the same as sitting** |
| Leg tilted, one foot up, sideways | in between | **Other** | n/a |
| Walking / running | | steps + cadence → light / moderate / vigorous | cadence cut-offs unverified |

If you need lying down detected too, a chest sensor does that but can't tell sitting from standing. Using both would give all three states.

## 2. Mounting
Put the board in a snug pouch (or tape it to a card) so it can't rotate or flip in the pocket. Use the **front trouser pocket**, same side every time. It doesn't matter which way up the board faces: the code learns your two positions. Re-save them if the board moves. Keep the USB cable and power bank from tugging.

## 3. Setup
1. **Upload** `lifetwin_band_single_file.ino` (*File → New Sketch*, paste everything, upload). Board: *ESP32S3 Dev Module*, *USB CDC On Boot: Enabled*. Library: **NimBLE-Arduino 2.x**. Serial shows `LifeTwin band fw 0.8 (thigh pocket)`.
2. Your accelerometer calibration (`c`, six poses) is kept.
3. Open **`lifetwin-band.html`** in **Chrome or Edge** on a laptop (not iPhone/Safari). Click **Connect band**. It sets the clock and downloads stored minutes.
4. **Save the two positions**, band in the pocket (page buttons, or `u` / `v` in the Serial Monitor):
   - **1. STANDING:** stand normally, leg vertical. It waits 5 s, then holds 3 s.
   - **2. SITTING:** sit in a chair, thighs roughly horizontal, feet on the floor. Same 5 s delay.
   - If they're under 45° apart, nothing is saved. Retry.
   - Positions saved in an earlier thigh session may load automatically; re-save them if the board moved.
5. `p` in the Serial Monitor prints the angle to each saved position. While sitting, the angle to *sitting* should be small (under about 30°); if not, re-save.

### Live timers (for testing)
Once connected, the page's **Live timers** card shows, counted by the band itself: elapsed **sitting**, **standing** (walking counts as standing), **steps**, and how long you've been in the **current position**. **Reset timers** (or `z` in the Serial Monitor) restarts them. In the Serial Monitor, `x` prints the same timers and one line is printed every minute. They survive closing the page, but not a power-off.

### Day summary file
**Download day summary (JSON)** (page) gives the selected day's totals: minutes per category, steps, moderate+vigorous minutes, sit-to-stand transitions, wear minutes and a valid-day flag (≥ 600 wear minutes). It has no per-minute data. Format and the planned iPhone transfer: `LifeTwin-band-day-summary-spec.md`.

### Day summary file kept ON the band (0.8): no web page needed
From 0.8 the band itself builds the day summary and saves it as `/day_YYYY-MM-DD.json` in its flash, every 10 minutes once its clock is set. Read it out with nRF Connect (iPhone) or the Serial Monitor: see `LifeTwin-band-nRF-Connect-guide.md`. New: characteristic `…0008` (headline JSON to read; notifications for the full file), control `0A` = save now, `0B` = save and send the full file, and the time can be typed as text (`2026-10-25 08:30:00 -07:00`). The Serial Monitor also has `T <time>`, `w`, `j`, `f`, `E yes`. The web page is now only a test tool.

### Sending the days to the app over Bluetooth (0.8)
The app connects to the band (the band never connects to the phone) and pulls each saved day. New control codes: `0D` list saved days, `0C` + `YYYY-MM-DD` send that day's file, `0E` + date delete a finished day. The app-side files, tests and the contract are in `app-integration/` (see its README and `docs/band-ble-contract.md`). The files the band makes were checked against the app's real `parseBandFile` (262 days accepted, including clock corrections and full 24-hour days).

### Step counting: what changed in 0.7 and how to tune it
You reported lag, over- and under-counting, and small steps being missed. Reading the old detector, five causes matched:

| Old behaviour | Effect | 0.7 |
|---|---|---|
| Fixed 0.05 g minimum, checked against peak *height* | small steps missed; steps riding on the thigh's slow swing missed | Judged by *prominence* (rise above the last low point); adjustable minimum, default about half the old one |
| Waited for 4 steps before counting any | lag; walks of under 4 steps counted nothing | Confirms after **3** regular steps, then counts every step immediately |
| Any odd gap restarted the 4-step wait | every pause or turn lost 3-4 steps | Pauses up to 3 s and single odd gaps no longer restart it; a skipped weak step is filled in |
| Fixed 250 ms minimum between steps | a double bump on one step could count twice | Minimum gap adapts to your walking pace |
| Nothing stopped a bouncing seated leg counting | false steps | **Steps are ignored while the posture reads "sitting"** |

**Controls (page "Step counting" card, or the Serial Monitor):**
- **Sensitivity 1-5** (`k 4`): 1 counts fewest, 5 counts smallest steps. Default 3. If small steps are still missed go up; if you get extra steps go down.
- **Ignore steps while sitting** (`g`): leave **on**. It needs your sitting position saved. If you walk and the band shows "Sitting", re-save your positions.
- **Count each detected step twice** (`d`): a last-resort field fix. Use it **only** if repeated step tests show the band counts about **half** your steps.
- Settings are stored on the band and survive power-off. `x` shows them.

**Measure it yourself:** the page's **Step test** card. Press Start, walk a number of steps while counting them, press Stop, type your count, Save. Do slow, normal, fast and small steps; it shows the error for each and the average.

**What I measured (on simulated signals only):** with a smooth, body-bounce step signal, normal / slow / fast walking came out within 1%, 0.06 g small steps within 1%, 0.035 g very small steps about 13% low, stop-start walking about 12% high, and 20 short bouts of 4 steps about 22% high (about one extra step per bout). With a sharper heel-strike signal it was weaker (normal walking about 22% low). With a signal dominated by the thigh swing it can count only strides (about half); that is what "count twice" is for. Without the sitting rule, one minute of seated leg-bouncing counted about 96 false steps in the simulation. **I don't know which signal type your leg produces. That is what a recording tells me.**

**Send me a recording so I can tune on your real leg:**
1. In the Serial Monitor (115200, Newline) send `r`. A CSV header and about 50 lines per second appear.
2. Walk 50 normal steps, stop for 5 seconds, 50 small steps, stop for 5 seconds, 50 fast steps. Write down the counts and the order.
3. Send `r` again to stop. Select all the Serial Monitor text, copy it into Notepad, save as `steps.csv`, and upload it to the chat with your notes.
The columns are `t_ms, ax, ay, az, steps, posture`. A few minutes is plenty.

## 4. Tests

| # | Test | Pass |
|---|---|---|
| T1 | Live posture: switch sit ↔ stand 10 times, 2 s each | ≥ 9 of 10 right |
| T2 | Page **Step test**: slow, normal, brisk and small-step walks of about 50 steps each | each within ±10%; note which are off and which way |
| T3 | Sit and type 30 min | stays Sitting, **no "not worn"**; note the `std` values |
| T4 | Band flat on a table 30+ min | "not worn" from the 30th minute |
| T5 | Stand 10 min, slow walk 10, brisk walk 10 | standing → light; brisk reaches moderate (about 100+ steps/min) |
| T6 | Labelled hour with the page's buttons | read agreement % per label |
| T7 | Sit 5 min, stand 5 min, walk 100 steps; read the Live timers | sitting ≈ 5:00, standing ≈ 5:00 + walk time, steps within ±10%; reset works |

**Known risk:** sitting very still might be mistaken for "not worn". Every minute stores its movement level (`std`) so the threshold can be tuned from T3/T4. A band flat on a table (chip up) also looks like sitting, so the movement level is the only separator.

## 5. Minute record, format version 2 (12 bytes, little-endian)

| Offset | Type | Field | Meaning |
|---|---|---|---|
| 0 | u32 | `ts` | unix seconds at minute close |
| 4 | u8 | `steps` | steps this minute |
| 5 | u16 | `enmo_mg10` | mean movement, 0.1 mg |
| 7 | u8 | `cls` | 0 sedentary, 1 light, 2 moderate, 3 vigorous (by steps/min: sitting no steps → 0; standing or 1–99 → 1; 100–129 → 2; 130+ → 3) |
| 8 | u8 | `flags` | 1 not worn · 2 still · 4 motion · 8 positions not saved · 16 time unsynced |
| 9 | u16 | `std_mg10` | movement std-dev, 0.1 mg |
| 11 | u8 | `posture` | 0 unknown · 1 sitting (or lying) · 2 standing · 3 other |

Python: `struct.unpack('<IBHBBHB', data)`. Bluetooth control codes: `05` save standing, `06` save sitting, `07` reset timers, `09`+byte step settings (bits 0-2 sensitivity, bit 3 ignore-while-sitting, bit 4 count-twice; also reported in the info message byte 9), `03`/`04` live on/off, `01`+u32 download since. The live timers are characteristic `…0007` (20 bytes: sitting s, standing s, other s, steps as u32; seconds in current position u16; posture u8; one spare). UUIDs are still my placeholders and the service has no pairing or encryption.

## 6. What this feeds
- **Weekly walking/running minutes** → a suggested `exercise_minutes_weekly` (user confirms).
- **Sitting hours** (waking hours only; lying down counts as sitting here) is a candidate new model input, but it's not a profile field today, so show it as a device estimate.
- Steps, standing time, sit-to-stand transitions, cadence: informational.
- Not available: sleep, heart rate, lying down as its own state.

## 7. Later: end-of-day transfer to the iPhone
Not built. The plan: press **End day** on the band, it syncs to the iPhone app, the app stores the day summary file, then you switch off. A hard power switch loses the band's memory, so a flash log is needed first. Details, the BLE sequence for the app developer, and what's missing: `LifeTwin-band-day-summary-spec.md`.

## 8. What I couldn't verify
Everything on a real leg. The new step detector was tuned and tested only on simulated signals I built, which can't tell me how your leg really moves; the earlier detector passed my cleaner simulations too and still gave you errors, so treat the numbers above as a best case. how steadily posture holds, the non-wear threshold, and the cadence cut-offs (100 and 130 steps/min, from my memory). The Bluetooth calls follow the NimBLE 2.x and Web Bluetooth documentation from memory, and the page was tested only against a simulated band. The issue #14 / PR #15 plan describes a wrist band.
