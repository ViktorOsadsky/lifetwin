# Band daily export and on-phone intake

Status: the user supplied a `lifetwin.band_day.v0` export on October 24, 2026 for [#67](https://github.com/ViktorOsadsky/lifetwin/issues/67). The parser now targets that existing format. It replaces the earlier minute-record proposal; it does not claim firmware changes or calibration. The supplied report is local acceptance input and is **not committed**. File intake stays available; Bluetooth now uses the same parser ([band-ble-contract.md](band-ble-contract.md)).

The original hardware/confirmation decisions remain in [#14](https://github.com/ViktorOsadsky/lifetwin/issues/14) and [PR #15](https://github.com/ViktorOsadsky/lifetwin/pull/15). Existing `BandService` confirmation behavior is preserved. UI ownership stays with Daniel.

## Daily contract

Accept UTF-8 JSON (`.json` or `.lifetwinband`), bounded to 5 MiB per delivery, at most 14 files and 14 dated reports. The parser is [band_file.dart](../app/lib/band/band_file.dart). The complete, explicitly synthetic examples are in [the fixtures directory](../app/test/fixtures/band/).

| Field | Meaning and validation |
|---|---|
| `schema` | Exactly `lifetwin.band_day.v0` |
| `date`, `timezone_offset_minutes` | Actual `YYYY-MM-DD` calendar date and integer offset −840 to +840; retain the recorded date. At import it must not be after the phone's local today (the store clock is injectable) |
| `generated_at` | Valid ISO timestamp with an explicit offset; must not be before the last covered minute on the report date, interpreted with `timezone_offset_minutes`. The export offset may differ from the record offset |
| `device` | Bounded `mount` and `firmware` strings, positive integer `record_format`; preserve `thigh_pocket` as supplied rather than relabeling the hardware as wrist mounted |
| `coverage` | Integer `minutes_recorded`, `wear_minutes` (0–1440), boolean `valid_day`, and first/last `HH:MM` within one date. Recorded minutes cannot exceed the inclusive first-to-last span |
| `minutes` | Integer counts for `sitting_or_lying`, `standing`, `walking_light`, `walking_moderate`, `running_vigorous`, `other_posture`, `not_worn`, `positions_not_saved` |
| `moderate_vigorous_minutes` | Must equal `walking_moderate + running_vigorous`; separate classes remain available |
| `steps`, `sit_to_stand_transitions`, `longest_sitting_minutes` | Bounded nonnegative daily counters; sensor estimates, without clinical interpretation |
| `hourly` | Exactly 24 unique hours 0–23, each containing `sitting_lying_min`, `standing_min`, `walking_min`, `running_min`, `other_min`, `not_worn_min`, `steps` |
| `notes` | At most 20 strings of 500 characters; untrusted metadata, never instructions or provider prompts |
| `synthetic_demo` | Optional app/demo annotation; `true` forces the entire import into recorded-demo mode |

All category counts must sum to recorded minutes. Recorded minutes must equal wear plus non-wear. Classified posture plus `positions_not_saved` must equal wear. Each hourly category sum must be at most 60; hourly category/step totals must match the daily totals, with hourly walking equal to daily light plus moderate walking. Reject malformed dates, offsets, types, fractions, inconsistent flags/totals, missing fields, unsupported schemas and duplicate hours. Validation errors never echo health records or device metadata.

Chronology uses inclusive minute buckets: `00:00` through `23:59` covers at most 1440 minutes and `08:00` through `08:30` at most 31. Gaps may remain unknown. A partial-day export may end at its actual last covered minute and be generated then; no end-of-day or midnight timestamp is required. Export and coverage timestamps are compared as instants after applying their own offsets, including across UTC date boundaries. The v0 offset is fixed for that report; it does not reconstruct daylight-saving transitions.

The store reads its injected clock once per delivery and converts it to the phone's local calendar day. Future recorded dates are rejected even if their report offset differs from the phone's zone; accepted dates are not shifted into that zone. Entire deliveries validate before mutation, including explicit replacements: a future or inconsistent report leaves existing reports, live minutes and `lastSynced` unchanged. Failures contain generic reasons, never health values, recorded dates or device identifiers. The [chronology regression handoff](handoffs/band-file-chronology.md) records the follow-up to merged [#122](https://github.com/ViktorOsadsky/lifetwin/pull/122), which closed [#114](https://github.com/ViktorOsadsky/lifetwin/issues/114).

The app also accepts a **local wrapper**, `{"schema":"lifetwin.band_days.v0","days":[...]}`, holding 1–14 complete daily reports. This is not a claim that firmware emits bundles. Duplicate dates in a delivery are rejected even when offsets differ. Different recorded dates around midnight/travel remain separate. The v0 daily format cannot disambiguate repeated daylight-saving hours or recover minute order; do not fabricate that detail.

## Leg placement and threshold audit

The supplied band is **leg-worn**, with `device.mount: thigh_pocket`. The parser reads the firmware's already-classified `walking_light`, `walking_moderate` and `running_vigorous` totals; it does not classify acceleration, compute cadence, apply wrist cut-points or convert steps into intensity. The summaries add those observed categories without reclassifying them. Their validity on this leg-worn hardware still needs calibration; accepting a consistent file does not establish accuracy.

The parser's limits (minute counts within a day/hour, step counters, file size and metadata bounds) are engineering validation bounds, not wrist/leg intensity thresholds. The 600-worn-minute day and four-day week are inherited prototype sufficiency rules, not placement calibration. The legacy `BandMinute.moderate` comment mentions unverified cut-points, but that path accepts an already-classified boolean; the daily-file path does not use those cut-points. BLE classification remains deferred. Stored provenance stays `wristband` for contract compatibility; user-facing copy is **activity band**.

## Unknown time and model boundary

`positions_not_saved` is unknown posture, not sitting, zero activity, or non-wear. Hourly bins do not locate those unknown minutes. Keep them unknown and do not manufacture minute records. `sitting_or_lying` includes lying down according to the supplied export notes; it is not a validated measure of awake NHANES sitting. Provisional walking-intensity classifications do not identify recreation versus work/transport.

The existing band policy counts at least 600 worn minutes as a valid day and requires at least four valid days in a seven-day window for its weekly suggestion. The export's `valid_day` must agree with the daily rule. Below that threshold, report-level activity/sitting suggestions are unavailable rather than zero. These are prototype sufficiency conventions documented by the existing band code and [PR #15](https://github.com/ViktorOsadsky/lifetwin/pull/15), not validation of this sensor or a new model mapping.

Existing `BandDay.moderateMinutes`/`BandWeek` retain their legacy **combined MVPA** meaning. `BandDayReport` additionally preserves separate moderate/vigorous observations and unknown posture. The existing `BandService` maps its combined suggestion to `moderate_recreation_min_week` only after read-back, saving `source: wristband`, `estimated: true` through `TwinRepository`; `outsideAiProfile()` excludes it. This pre-existing mapping remains a model-owner limitation: confirmation alone does not establish recreational context or calibration. Do not present the importer as resolving it. Sitting/lying is not mapped to a profile field.

Weekly suggestions are also withheld when any otherwise valid day used by the week contains `positions_not_saved`: known wear does not establish zero movement during unclassified time. `BandWeek.hasUnknownActivityCoverage` exposes that reason to the UI owner; observed daily counts and wear status remain available. This conservative guard does not calibrate the sensor or resolve recreational context.

One real day cannot establish a measured week. User-authorized extrapolation must add `synthetic_demo: true` and use a separate demo store. Synthetic and measured report imports cannot mix, and imported synthetic reports never qualify as live data or a band suggestion. The design-owned built-in recorded-minute demo is a separate path: current `BandStore.demoOnly` permits a visibly labelled, explicitly confirmed demo suggestion only when there is no live connection or imported file. That does not promote an imported extrapolation to measured data.

## Native delivery and route integration

`BandFileBridge.swift` registers Files document types, a native multiple-file picker, security-scoped bounded reads, and cold/warm SceneDelegate Open-in delivery. It consumes only app `Documents/Inbox` copies; it never deletes the user's original Files document. No HTTP client, provider upload or raw-payload logging is involved. In-memory event buffers are bounded. Native reads share one serial queue, and SceneDelegate delivery and startup recovery claim Inbox URLs before scheduling work so the same copy is consumed once. A transport failure retains the whole batch of Inbox copies for retry; successful reads consume those copies. `forgetImports()` clears pending copies too. Imports are held only in phone memory and disappear when the session is disposed.

`BandFileIntake` validates an entire delivery before changing `BandStore`. Re-importing equivalent data is a no-op; a changed report for an occupied date requires `replaceExisting: true` after an explicit replacement decision. Cancellation, malformed files and stale picker replies preserve prior state. Imported files do not claim Bluetooth pairing. `forgetImports()` invalidates pending reads, clears native Inbox/queues and clears the store; confirmed profile answers retain the existing repository policy.

The app starts native delivery on iOS through `BandFileSession.instance.start()`. For the design-owned band route, use the **same** `BandFileSession.instance.store` and `.intake`; call `importFromFiles()` from its import action and observe `busy`/`outcome` for result presentation. Its My data/unpair action should call `forgetImports()`. No band screen was edited in this task. Starting a second private store will not display files received by the root session. Daniel's current route wires the shared session to an import action, outcome messages and forgetting controls. Native Files selection and cold Share/Open-in have now passed actual simulator UI tests with a synthetic report; explicit changed-date replacement presentation and the final designed/device flow remain his UI acceptance dependency.

## Verification and handoff

- Synthetic `valid_day.json`, `low_wear.json` and `midnight_bundle.json` exercise the actual schema, missing posture and distinct recorded dates/offsets.
- `test/band/band_file_test.dart` covers strict rejection, atomic/idempotent imports, explicit replacement, fake-picker cancel/stale delivery, Inbox/warm streams, demo isolation and the existing confirmation/provenance boundary. Controlled measured-feed fixtures are test inputs, not evidence of real wear or calibration.
- `integration_test/band_file_device_test.dart` accepts the supplied file from the test app's native iOS Inbox (simulator here; Daniel owns physical-device testing). It checks parsing/store delivery, unknown posture, repeat import, Inbox cleanup and the insufficient-week rule; optional shifted demo days stay synthetic. The real file is copied locally before running and is never bundled.
- Separate, temporary XCUITests passed actual Files-picker selection/cancellation and Files → Share → registered-handler cold launch on the iOS 26.4 simulator. They used the synthetic fixture with the production native bridge/intake/store; the original document was preserved. Exact scope, results and local evidence are in [the handoff](handoffs/band-file-intake.md). These tests do not validate final product-screen presentation, physical-device behavior, Bluetooth transport or model calibration.

Track: C data/native file intake (#67). Contracts: band daily v0 plus app-only multi-day wrapper; no server/model contract change. Next dependencies: Daniel accepts the final designed route, replacement controls and physical-device flow; hardware/model owners validate intensity, posture and recreational-context mapping before stronger claims. Bluetooth delivery of the same JSON is described in [band-ble-contract.md](band-ble-contract.md); the band's send command is still unconfirmed.

## Demo bundle

`demo/band/band-two-weeks-demo.json` is a 14-day synthetic `lifetwin.band_days.v0` bundle (a retired woman, thigh band), generated by `tools/build_demo_band_days.py` (seeded). The same script writes `app/lib/band/band_demo_templates.dart`, the in-app "Recorded demo", whose dates are shifted at load time so the last day is always yesterday. Regenerate the bundle with `--today` to refresh its dates.
