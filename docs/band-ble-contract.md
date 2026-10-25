# Activity band over Bluetooth

Status, 2026-10-25: the band (an MPU-6050 on an ESP32-S3, leg-worn, the team's own firmware) **already sends its JSON over Bluetooth**. Its firmware source is not in this repo, so this page records the layout **observed** on the real band with [tools/ble_probe.py](../tools/ble_probe.py), and how the app speaks it. Anything not observed is marked unconfirmed. Issues: [#14](https://github.com/ViktorOsadsky/lifetwin/issues/14), [#67](https://github.com/ViktorOsadsky/lifetwin/issues/67).

The band's JSON is the same `lifetwin.band_day.v0` day report as a band file ([wearable-file-format.md](wearable-file-format.md)). The app runs what arrives through the same `parseBandFile` and `BandStore.importReports`, so every validation rule and the whole-delivery rule (one bad day rejects the delivery) are unchanged. Nothing received is stored on disk or sent anywhere; only the person's "Yes" saves to the profile, with provenance `wristband`.

## Observed layout

Advertised name `LifeTwin Band`; negotiated MTU 256 (from the Mac). Every UUID shares the base `4c5400XX-7b2a-4f0e-9a51-0d1e2c3b4a50`.

| UUID | Properties | Observed | Use in the app |
|---|---|---|---|
| `4c540001-…` | primary service | advertised | scan filter |
| `4c540002-…` | read | 10 bytes, `00 07 02 0c a0 05 0e 00 07 0b` | read once on connect, kept raw, **not interpreted** |
| `4c540003-…` | write | — | **unconfirmed** send trigger (`bandSendCharacteristic`) |
| `4c540004-…` | write | — | unknown |
| `4c540005-…` | notify | silent without a command | day JSON (`data`), reassembled |
| `4c540006-…` | notify | silent without a command | unknown (perhaps status); not subscribed |
| `4c540007-…` | notify, read | 20 zero bytes | optional live counters, passed through raw |

No notification arrives in 20 s without a command, so a write (to `0003` or `0004`) presumably starts the send. **The command is not known and the app never writes a guessed one.** The guesses about `0002` (`a0 05` = 1440 minutes a day, `0e` = 14 days) are not used.

## The one thing to set

In [band_ble.dart](../app/lib/band/band_ble.dart):

```dart
const String bandSendCharacteristic = '4c540003$_base'; // or 0004
const List<int>? bandSendCommand = null;                 // e.g. utf8.encode('{"cmd":"send"}') or [0x01]
```

While `bandSendCommand` is null, pairing connects, reads `0002`, subscribes to `0005` and listens for 10 s; silence means "no days" (nothing written, nothing imported). If the band sends on a **read** instead, set `readToSend: true` on `lifeTwinBandProfile`. If its JSON is framed differently, set `framing` there (below).

## Framing (configurable)

`BandJsonAssembler` turns `0005` notifications into JSON values:

- `jsonStream` (default): UTF-8 JSON split across notifications, or one per notification; a value ends when its braces balance (strings and escapes respected). Bytes outside a value are skipped.
- `terminated`: each value ends with `terminator` (default `\n`).
- `lengthPrefixed`: each value starts with its length, `lengthBytes` little-endian bytes.

A delivery is every value received after the trigger until no notification has arrived for 2 s. One `lifetwin.band_days.v0` bundle is used as is; otherwise the values (one `band_day.v0` per day) are wrapped byte for byte into a bundle and parsed as one file.

## Phone behaviour

- **Scan**: by the service UUID (OS filter), keeping results whose name, when present, starts with `LifeTwin Band`; strongest first; at most 8 s.
- **Pair** (foreground only): connect (15 s) → MTU 256 (Android asks; iOS negotiates itself) → discover → read `0002` → subscribe `0005` → trigger → reassemble → `parseBandFile` → `importReports`. It stays connected while the app is open and disconnects on *Unpair*. Band days live in phone memory only, so a new app session pairs again. No `UIBackgroundModes`.
- **Retry**: an incomplete value at the end (a lost notification), undecodable JSON, or a delivery the parser rejects is asked for **once** more; a second failure is an error. The band sends no length or checksum that we know of, so a lost notification that still leaves balanced JSON is caught only by the parser's consistency checks (totals, 24 hourly bins); a length or CRC-32 from the firmware would make this exact.
- **Errors**: no first notification within 10 s of a trigger (a timeout), a disconnect mid-transfer, or more than 256 KiB received: nothing is imported, the phone disconnects, and the pairing screen shows its trouble state (H-4) with a plain reason. Bluetooth off or not allowed shows the existing H-4 checks ("Open Settings" when not allowed). Reasons never contain values, dates or device identifiers.
- **Demo and files**: "Try the demo band" and file import are unchanged. Real band days replace the built-in recorded demo only after they validate.

## Code

| File | Role |
|---|---|
| `app/lib/band/band_ble.dart` | `lifeTwinBandProfile`, `BandJsonAssembler`, the `BleRadio`/`BleLink` interface, `BleBandClient` |
| `app/lib/band/band_ble_fbp.dart` | `FlutterBluePlusRadio`, the only file that uses the plugin |
| `app/lib/band/band_store.dart` | `BandClient.fetchDays`, `BandStore.pair` (fetch, then import the whole delivery), `pairProblem` |
| `app/test/band/band_ble_test.dart` | a fake band with this layout |
| `tools/ble_probe.py` | read-only probe (scan, dump, read, subscribe, log, reassemble; one write only with `--write`) |

`flutter_blue_plus` is pinned at 2.3.13. Its licence is free for personal, nonprofit and educational use and paid for for-profit use, and it may send a build-time licence ping (package and app name, versions; no user data). `bandBlePluginLicense` declares `License.nonprofit`; an owner should confirm that, or the plugin can be swapped behind `BleRadio`.

## Still needed from the band's builder

1. The command that starts the send: which characteristic (`0003` or `0004`), the exact bytes, and whether one command sends all stored days or one day.
2. How a delivery ends (an end marker, a length, or just silence) and whether there is a checksum.
3. What `0006` notifies, and the byte layout of `0002` and `0007`.
4. Whether today's day in progress is sent, and whether a day already sent is sent again (a changed report for a date the phone already holds is refused unless replaced explicitly).
5. Whether the band needs the phone's time (a set-time command) and its format.
