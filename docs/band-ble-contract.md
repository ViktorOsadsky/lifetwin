# Activity band over Bluetooth: the app side

The protocol is the band firmware's own. Its source of truth is [LifeTwin-band-full-code/docs/band-ble-contract.md](../LifeTwin-band-full-code/docs/band-ble-contract.md), backed by [ble_service.h](../LifeTwin-band-full-code/arduino/lifetwin_band/ble_service.h) and [config.h](../LifeTwin-band-full-code/arduino/lifetwin_band/config.h) (firmware 0.8, `FORMAT_VERSION 2`). This page only records how the app implements that contract and where it adds rules. Issues: [#14](https://github.com/ViktorOsadsky/lifetwin/issues/14), [#67](https://github.com/ViktorOsadsky/lifetwin/issues/67).

The band sends the same `lifetwin.band_day.v0` file as a band file ([wearable-file-format.md](wearable-file-format.md)). Each day goes through `parseBandFile`, and the delivery goes through `BandStore.importReports`. Nothing received is stored on disk or sent anywhere. Only the person's "Yes" saves to the profile, with provenance `wristband`. The band is worn on the **thigh**, in a front trouser pocket or strapped on.

## What the app uses (from `ble_service.h`)

| UUID `4c5400NN-7b2a-4f0e-9a51-0d1e2c3b4a50` | Properties | App use |
|---|---|---|
| `01` service | advertised (name in the scan response) | scan filter, plus the name prefix `LifeTwin Band` |
| `02` Info | read | 10 bytes: `fw_major, fw_minor, record_format, record_size, capacity u16, stored_minutes u16, posture_state, step_settings`. The app requires `record_format == 2` and firmware ≥ 0.8; otherwise it shows "Your band needs a firmware update…" and writes nothing |
| `03` Clock | write (with response) | 6 bytes, sent on **every** connection: unix seconds `u32` LE, then minutes east of UTC `i16` LE. The app then waits 0.4 s |
| `04` Control | write (with response) | `0D` the index, `0C`+`YYYY-MM-DD` one day, `05`/`06` save standing/sitting position. The app **never** sends `0E` (delete) |
| `08` Summary | read, notify | every requested file arrives as notifications: text chunks of ≤ 180 bytes every 25 ms, then `<EOF>` |

The app does not use `05`, `06` or `07` (minute records, live posture, live timers).

## Sync, as `BleBandClient` does it

1. Scan by service UUID (at most 8 s), connect (15 s), discover services.
2. Read Info, and stop with the firmware-update message if it is unsupported.
3. Subscribe to `08`, write the clock, wait 0.4 s.
4. Write `0D`, then collect chunks until `<EOF>`. The result is `{"schema":"lifetwin.band_index.v0",…,"days":[…]}`.
5. For each of the **newest 14** dates, write `0C`+date and collect until `<EOF>`. Each answer is either one `band_day.v0` file or `{"error":"no_file_for_that_date"}`; that date is skipped. Any other `error` fails the sync.
6. Each day is checked with `parseBandFile` as it arrives. The days are then bundled and imported as one delivery through `BandStore.sync()`.

Rules the app adds:
- **Timeouts:** 10 s from a command to the file's first notification, and 12 s between notifications within a file. There is no total cap; 14 days take about 8–70 s.
- **Retry:** a file that is incomplete at `<EOF>`, isn't valid JSON, or that the parser rejects is asked for **once** more; a second failure fails the sync. There is no length or checksum, so a lost notification that still leaves balanced JSON is caught only by the parser.
- **Abandon without retry:** a band that stops without `<EOF>` (12 s of silence), disconnects mid-transfer, or sends a file over 64 KiB. Nothing is imported.
- **Re-sends:** every sync re-sends the newest 14 days, today included. Identical days are no-ops. A day that has **grown** (more recorded minutes, exported no earlier, as today does) replaces the stored one. Any other change to a stored date refuses the whole delivery and keeps what was there.
- **Unknown posture:** without saved positions, worn minutes are `positions_not_saved`. Those files import, their steps count, and posture shows as unknown; the parser requires `longest_sitting_minutes ≤ sitting_or_lying`, so it is 0 then. After pairing, while Info says the positions aren't both saved, the pair screen offers "Save standing position" and "Save sitting position" (`05`/`06`: the band waits about 5 s, then the person holds still about 3 s).
- **On failure:** nothing is imported, the phone disconnects, and the pairing screen shows its trouble state (H-4) with a plain reason. Bluetooth off or not allowed shows the existing checks ("Open Settings" when not allowed). Reasons never contain values, dates or device identifiers.
- **Lifetime:** foreground only, with no `UIBackgroundModes`. The phone stays connected while the app is open and disconnects on *Unpair*. Band days live in phone memory, so a new app session pairs again. "Try the demo band" and file import are unchanged.

## Code

| File | Role |
|---|---|
| `app/lib/band/band_ble.dart` | `BandGatt` UUIDs, control codes, `BandInfo`, `bandClockBytes`, `BandJsonAssembler`, the `BleRadio` / `BleLink` interface, `BleBandClient` |
| `app/lib/band/band_ble_fbp.dart` | `FlutterBluePlusRadio`, the only file that uses the plugin. `flutter_blue_plus` 2.3.13 with `License.nonprofit`, which the owner said to keep for now (2026-10-25) |
| `app/lib/band/band_store.dart` | `BandClient.fetchDays` / `savePosition`, `BandStore.pair` / `sync()`, `importReports(replaceGrown:)`, `pairProblem` |
| `app/test/band/band_ble_test.dart` | a fake firmware 0.8 band running the real index-then-days flow |
| `tools/ble_probe.py` | `--sync` runs the same sync from a Mac and saves `index.json` and `day_*.json`; plain `--connect` dumps the GATT read-only |

## Before it works on the real band

- The band probed on 2026-10-25 runs **firmware 0.7**: Info `00 07 02 0c a0 05 2f 00 07 0b`, with no `08` characteristic. It must be reflashed with 0.8. Until then the app shows the firmware-update message.
- Nothing has run between this app and a real 0.8 band yet. Verify with `tools/ble_probe.py --connect "LifeTwin Band" --sync`, then pair from the phone.
- The other gaps listed in the firmware's contract still apply: no checksum, no bonding, a clock lost at power-off, and no background sync.
