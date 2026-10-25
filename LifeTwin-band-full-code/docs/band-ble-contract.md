# Band Bluetooth contract (daily files over BLE)

Status: **proposal, implemented in band firmware 0.8** (`firmware/lifetwin_band` in the hardware kit) and in the app files listed below. It answers the open point in [wearable-file-format.md](wearable-file-format.md): "BLE needs an agreed GATT contract". It does **not** change the daily file: the band sends the exact `lifetwin.band_day.v0` file the app already parses, so [band_file.dart](../app/lib/band/band_file.dart), the store and the intake rules stay in charge of validation. Nothing here claims calibration or accuracy.

## Who connects to whom
The **phone connects to the band**. The band is a Bluetooth Low Energy *peripheral*: it advertises a service and waits. The app (iPhone = central, via CoreBluetooth through a Flutter plugin) scans for that service, connects, reads, writes and subscribes. The band cannot start a connection to a phone, and it never appears in iOS *Settings → Bluetooth* (iOS lists only pairable accessories there). No pairing step exists yet.

## Service `4c540001-7b2a-4f0e-9a51-0d1e2c3b4a50`
Every characteristic UUID is the same with `4c54000N` (N = 2..8).

| N | Properties | Use |
|---|---|---|
| 2 | read | **Info**, 10 bytes: `fw_major, fw_minor, record_format, record_size, capacity u16, stored_minutes u16, posture_state, step_settings`. The app requires `record_format == 2` and firmware ≥ 0.8 |
| 3 | write | **Clock**: `unix seconds u32 LE` + `zone minutes east of UTC i16 LE` (6 bytes). The band has no clock chip; set it on every connection. The zone decides which local day each minute belongs to |
| 4 | write | **Control** (below) |
| 5 | notify | minute records (not used for daily files) |
| 6 | notify | live posture (testing) |
| 7 | read, notify | live timers: sitting s, standing s, other s, steps (u32 each), seconds in current position u16, posture u8, spare |
| 8 | read, notify | **Summary**: read = headline JSON ≤ 512 bytes; notify = the file requested through Control, as text chunks |

### Control codes (first byte)
`0A` save today's file now · `0B` save and send the latest day · **`0D` send the list of saved days** · **`0C` + `YYYY-MM-DD` (ASCII) send that day's file** · **`0E` + `YYYY-MM-DD` delete that day's file** (only days before today; the band ignores anything else) · `07` reset live timers · `03`/`04` live on/off · `05`/`06` save standing/sitting position · `09`+byte step settings · `01`+u32 stream minute records.

## Sync sequence the app performs
1. Scan with the service UUID as the filter (required on iOS), connect, discover services.
2. **Read Info.** Stop with a safe message if the format or firmware is not supported.
3. **Write the clock** (6 bytes), wait about 0.4 s (the band applies it in its main loop).
4. **Subscribe to notifications on `…0008`.**
5. Write `0D` to Control. The band replies with the list of saved days as text chunks, then the five characters `<EOF>`:
   `{"schema":"lifetwin.band_index.v0","firmware":"0.8","timezone_offset_minutes":-420,"days":["2026-10-24","2026-10-25"]}`
6. For each date (newest 14 at most): write `0C` + the date; collect chunks until `<EOF>`; that is one `lifetwin.band_day.v0` file, up to about 3.9 KB. A missing date returns `{"error":"no_file_for_that_date"}`.
7. Hand the files to `BandFileIntake` exactly like imported files; its strict validation, idempotence and replacement rules apply unchanged.
8. Only after a **finished** day is really stored, optionally write `0E` + date so the band frees the space. The app does not do this automatically.

Chunk size is the negotiated MTU minus 3, at most 180 bytes (20 bytes if the link stays at the default size), one chunk every 25 ms. A day (about 3.9 KB) therefore takes about 0.6 s at the size iOS normally negotiates and about 5 s at the default; 14 days is about 8 s or about 70 s. A transfer with no data for 12 s is abandoned (nothing is imported).

**How a send ends:** the band sends the file, then the five characters `<EOF>` as one last notification. There is **no length prefix and no checksum**. A dropped notification is retried by the band (it only moves on after a notification is accepted), and Bluetooth itself checks and retransmits each packet; if the band gives up (nobody listening for about 2 s) it simply stops and the app times out. A truncated or garbled file is then caught only by the app's JSON parse and its strict consistency checks (category sums, hourly totals, coverage window), which is a sanity check, not an integrity guarantee.

## What the band guarantees about its files
It builds the file on the band from its minute records and keeps it in flash as `/day_YYYY-MM-DD.json` (rewritten every 10 minutes once the clock is set; survives power-off; a restart mid-day adds to what was saved). Every file was checked against the app's real `parseBandFile` on 262 generated days: regular days, days with clock corrections mid-recording, and full 24-hour days with one-second timing wobble. A minute is counted at most once, so a clock correction cannot make the file claim more minutes than its first-to-last window (the app rejects that). `sitting_or_lying` includes lying down. `positions_not_saved` is unknown posture, as the app already treats it.

## Known gaps found in review (not fixed yet)
1. **No length or checksum** on a file send (see above). Proposed: a first notification carrying the byte length and a CRC-32, checked before import.
2. **Every sync re-sends the newest 14 days in full**, including today's unfinished day (which the band rebuilds just before answering, so it is current to the last finished minute). Import is idempotent and `sync()` replaces a changed day, so the store is correct, but it is wasteful and nothing older than 14 days is fetched. Proposed: the index carries each day's minute count and a CRC, and the app skips finished days it already holds.
3. **The clock must be set by the phone.** Until it is, the band records minutes but builds and saves no day files, so a run that is switched off before its first sync is lost. Proposed: a small real-time-clock module, or saving minute records to flash.
4. **Where it is worn must be the thigh.** Posture comes from the thigh's tilt (horizontal seated, vertical standing). On the lower leg both look the same. The pairing screen (`band_screens.dart`, "just above the ankle") says otherwise, and the app has no step for saving the standing and sitting positions the band needs (control codes `05`/`06`); without them every minute is `positions_not_saved`.

## Not built / not verified
- **Nothing here has run on a real band and phone together.** The firmware's flash writing and Bluetooth chunking were syntax-checked only; the app's sync logic was run on a computer against a fake band that behaves like the firmware, using the real parser. The adapter that talks to the plugin was type-checked against the documented API, not run.
- **No pairing, bonding or encryption.** Anyone in range can read the band. Add bonding before real use.
- **No background sync.** The user presses Sync. iOS can wake an app for a band that advertises its service (background mode `bluetooth-central`, state restoration), but connection timing is limited and untested.
- **Live connection status** (`BandClient`: connected, low power, not worn) is separate and not done; Bluetooth sync only produces day files.
- **The clock is lost at power-off.** After switching the band off, the next connection sets it again; minutes recorded before that are corrected when it is set, provided the band stayed on.
- **Plugin licence:** `flutter_blue_plus` is free for personal, nonprofit and educational use; commercial use needs its paid licence. The plugin is used in one file behind a small interface (`BandLink`) so it can be swapped.
- Sitting time and intensity keep the caveats already in the file format document: thigh sensor, lying counted as sitting, provisional steps-per-minute cut-offs.
