# Activity band over Bluetooth

Status, 2026-10-25: the band is an MPU-6050 on an ESP32-S3 running the team's own firmware. It is worn on the thigh, in a front trouser pocket or strapped on, and it **already sends its JSON over Bluetooth**. Its firmware source is not in this repo. This page records:
- the layout **observed** on the real band with [tools/ble_probe.py](../tools/ble_probe.py);
- what the firmware side has told us (relayed by the owner);
- how the app speaks the protocol.

Anything not yet confirmed is marked as such. Issues: [#14](https://github.com/ViktorOsadsky/lifetwin/issues/14), [#67](https://github.com/ViktorOsadsky/lifetwin/issues/67).

The band's JSON is the same `lifetwin.band_day.v0` day report as a band file ([wearable-file-format.md](wearable-file-format.md)). The app runs what arrives through the same `parseBandFile` and `BandStore.importReports`, so every validation rule and the whole-delivery rule (one bad day rejects the delivery) are unchanged. Nothing received is stored on disk or sent anywhere. Only the person's "Yes" saves to the profile, with provenance `wristband`.

## Observed layout

The band advertises the name `LifeTwin Band`. The MTU negotiated from the Mac is 256. Every UUID shares the base `4c5400XX-7b2a-4f0e-9a51-0d1e2c3b4a50`.

| UUID | Properties | Observed | Use in the app |
|---|---|---|---|
| `4c540001-…` | primary service | advertised | scan filter |
| `4c540002-…` | read | 10 bytes, `00 07 02 0c a0 05 0e 00 07 0b` | read once on connect, kept raw, **not interpreted** |
| `4c540003-…` | write | — | **unconfirmed** send and clock characteristic |
| `4c540004-…` | write | — | unknown (perhaps clock or acknowledge) |
| `4c540005-…` | notify | silent without a command | day JSON, then `<EOF>` |
| `4c540006-…` | notify | silent without a command | unknown (perhaps status); not subscribed |
| `4c540007-…` | notify, read | 20 zero bytes | optional live counters, passed through raw |

## What the firmware side says

- **End of a delivery:** after the file, the band sends the 5 characters `<EOF>` as one last notification. There is no length prefix and no checksum. A band that gives up just stops, and the app abandons the delivery after 12 s of silence and imports nothing.
- **What a sync sends:** each sync re-sends the newest 14 days in full, today included, rebuilt just before answering and current to the last finished minute. Days stay on the band until the app acknowledges them. The app never acknowledges today.
- **Throughput:** a ~3.9 KB day takes about 0.6 s at the negotiated MTU and up to about 5 s at the default MTU, so 14 days take ~8–70 s.
- **Clock:** the band has no real-time clock. The phone must write the time and time zone on every connection, and until then the band builds no day files.
- **Calibration:** the firmware has commands to save the standing and sitting positions, but the app has no screen for them yet. Without calibration, worn minutes arrive as `positions_not_saved`.

## The constants to set

In [band_ble.dart](../app/lib/band/band_ble.dart):

```dart
const String bandSendCharacteristic = '4c540003$_base';
const List<int>? bandSendCommand = null;                        // the sync trigger bytes
const String bandClockCharacteristic = '4c540003$_base';
const List<int> Function(DateTime now)? bandClockCommand = null; // time + zone, format TBD
```

While these are null, the phone writes **nothing** to the band. Pairing connects, reads `0002`, subscribes to `0005`, and listens for 10 s. Silence means "no days", so nothing is imported. If the band sends on a **read** instead of a write, set `readToSend: true` on `lifeTwinBandProfile`.

## Framing

`BandJsonAssembler` turns `0005` notifications into JSON values:
- **`jsonStream`** (the default): UTF-8 JSON split across notifications, or one value per notification. A value ends when its braces balance; strings and escapes are respected. Bytes outside a value are skipped.
- **`endMarker`** (default `<EOF>`): ends the delivery, whether it arrives as its own notification or glued to the end of the last one outside a value. `<EOF>` inside a JSON string does not end it.
- **`lengthPrefixed`**: an alternative where each value starts with its length. Use it with `endMarker: null`.

A single `lifetwin.band_days.v0` bundle is used as it is. Otherwise the values (one `band_day.v0` per day) are wrapped byte for byte into a bundle and parsed as one file.

## Phone behaviour

- **Scan:** by the service UUID (an OS filter), keeping results whose name, when present, starts with `LifeTwin Band`. Strongest signal first; at most 8 s.
- **Pair (foreground only):**
  1. Connect (15 s timeout).
  2. MTU 256: Android requests it; iOS negotiates on its own.
  3. Discover services.
  4. Read `0002`.
  5. Subscribe to `0005`.
  6. Write the clock, on every connection.
  7. Send the trigger.
  8. Reassemble the JSON until `<EOF>`.
  9. `parseBandFile`, then `importReports`.

  The phone stays connected while the app is open and disconnects on *Unpair*. Band days live in phone memory only, so a new app session pairs again. There are no `UIBackgroundModes`.
- **Timeouts:** 10 s from the trigger to the first notification, and **12 s between notifications**. There is no total cap, so a 70 s transfer is fine.
- **Re-sends:** `BandStore.sync()` imports the band's 14 days as one delivery. Identical days are no-ops. A day that has **grown** (more recorded minutes, exported no earlier, as today does) replaces the stored one. Any other change to a stored date refuses the whole delivery and keeps what was there. Pairing calls `sync()`; nothing in the UI calls it again yet.
- **Retry:** the phone asks once more when a value is still open at `<EOF>` (a lost notification), when JSON doesn't decode, or when the parser rejects the delivery; a lost notification can still leave balanced JSON. A second failure is an error. A band that stops without `<EOF>` (12 s of silence), disconnects mid-transfer, or sends more than 256 KiB fails at once, without a retry.
- **On failure:** nothing is imported, the phone disconnects, and the pairing screen shows its trouble state (H-4) with a plain reason. Bluetooth off or not allowed shows the existing H-4 checks ("Open Settings" when not allowed). Reasons never contain values, dates or device identifiers.
- **Unknown posture:** files whose worn minutes are all `positions_not_saved` import, and their steps are kept; posture is shown as unknown and weekly suggestions are withheld (`BandWeek.hasUnknownActivityCoverage`). Such a file must still be internally consistent. In particular, the parser requires `longest_sitting_minutes` to be at most `sitting_or_lying`, so it must be `0` when no sitting is known.
- **Demo and files:** "Try the demo band" and file import are unchanged. Real band days replace the built-in recorded demo only after they validate.

## Code

| File | Role |
|---|---|
| `app/lib/band/band_ble.dart` | `lifeTwinBandProfile` and its constants, `BandJsonAssembler`, the `BleRadio` / `BleLink` interface, `BleBandClient` |
| `app/lib/band/band_ble_fbp.dart` | `FlutterBluePlusRadio`, the only file that uses the plugin |
| `app/lib/band/band_store.dart` | `BandClient.fetchDays`, `BandStore.pair` and `sync()`, `importReports(replaceGrown:)`, `pairProblem` |
| `app/test/band/band_ble_test.dart` | tests against a fake band with this layout |
| `tools/ble_probe.py` | read-only probe: scan, dump, read, subscribe, log and reassemble; one write only with `--write` |

`flutter_blue_plus` is pinned at 2.3.13. Its licence is free for personal, nonprofit and educational use and paid for for-profit use, and it may send a build-time licence ping (package and app name, versions; no user data). `bandBlePluginLicense` declares `License.nonprofit`. The owner ruled on 2026-10-25: keep it for now.

## Still needed from the firmware side

1. The exact bytes of the sync trigger, and which characteristic receives it (`0003` or `0004`).
2. The clock command's format: epoch or text, the time-zone field, and which characteristic.
3. The acknowledge command, which days it covers, and its characteristic. The app sends no acknowledge yet, so days stay on the band.
4. What `0006` notifies, and the byte layout of `0002` and `0007`.
5. The calibration commands, for a later app screen.
