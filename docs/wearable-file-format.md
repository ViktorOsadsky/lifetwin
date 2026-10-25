# Proposed end-of-day wristband file format

Status: **proposal for hardware-owner agreement**, October 24, 2026 (Pacific), for [#67](https://github.com/ViktorOsadsky/lifetwin/issues/67). This document does not claim firmware compatibility or a tested physical import. @shpatel2823-create and Daniel must confirm the fields and clock behavior before dependent implementation.

The earlier prototype plan is preserved on [PR #15](https://github.com/ViktorOsadsky/lifetwin/pull/15); it is not present on current main. The rulings in [#14](https://github.com/ViktorOsadsky/lifetwin/issues/14) and the existing `app/lib/band/` code govern privacy, confirmation and calibration. File import is primary; Bluetooth is a stretch.

## File envelope

Use UTF-8 JSON with extension `.lifetwinband`, MIME `application/vnd.lifetwin.band+json`, and one explicit schema version:

```json
{
  "schema_version": "lifetwin.band.minutes.v1",
  "device_id": "prototype-01",
  "firmware_version": "0.1.0",
  "minutes": [
    {"timestamp": "2026-10-24T08:00:00-07:00", "steps": 80,
     "intensity": "moderate", "worn": true, "heart_rate": 92}
  ]
}
```

These are proposed **engineering limits**, not clinical cut-points: at most 5 MiB and 21,000 records per file; nonempty device/firmware labels at most 80 characters; steps integer 0–400 per minute; optional heart rate null or integer 20–300. Heart rate is informational and never a model input. Reject unknown schema versions, unknown intensity labels, booleans represented as strings, malformed JSON, missing required fields, invalid calendar dates and duplicate UTC minutes. Errors identify a row/reason without echoing raw record contents or device identifiers.

`intensity` is exactly `sedentary`, `light`, `moderate` or `vigorous`. It is the firmware's classification estimate, **not** a clinical measurement or a validated NHANES mapping. `worn` is an actual JSON boolean. Missing/non-worn minutes never become sedentary or zero activity. Non-worn rows may retain sensor counts in the file, but those counts are excluded from aggregates.

## Time and repeat imports

`timestamp` describes the start of a whole minute, with zero seconds and an explicit UTC offset (`Z` allowed). The offset convention follows [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339.html#section-5.6). An offset is required because the phone's current zone may differ from where the band was worn.

Proposed behavior: use the **recorded local calendar date** for day grouping; use the UTC instant to detect duplicates and order records. A file may span midnight or a time-zone transition. A repeated local clock minute during a daylight-saving fallback is valid only when its offsets denote different instants. Reject a repeated instant even if written with a different offset. Sort an otherwise valid file before aggregation. Do not use elapsed 24-hour arithmetic to infer calendar dates.

Importing the same device/minute a second time is idempotent; a changed record for an already imported instant needs an explicit replacement decision. Validate the entire file before replacing any in-memory band data. Cancellation or any validation failure preserves the previous import. Device ID and firmware are held only as import metadata, never logged or sent to a provider.

## Aggregation and confirmation boundary

Aggregate on the phone by recorded date: worn minutes, steps while worn, separate moderate/vigorous minutes and observed sedentary minutes. Expose missingness and valid-day status. The existing band flow uses 600 worn minutes for a valid day and at least four valid days in seven for a weekly suggestion; these are prototype sufficiency conventions, **not** validation of this band's intensity or posture detection ([current band data](../app/lib/band/band_data.dart); [prototype plan](https://github.com/ViktorOsadsky/lifetwin/pull/15)).

Below the wear threshold, daily activity/sitting suggestions are unavailable rather than zero. Observed sedentary minutes are not automatically a full day's sitting: unknown wear time and stationary standing remain unresolved. Moderate/vigorous movement also does not identify recreation versus commuting/work. Preserve those distinctions and ask for confirmation/clarification; do not silently write model inputs or fabricate missing time.

The current `BandMinute.moderate` field combines moderate and vigorous movement and `BandService` offers only a weekly moderate-field suggestion. The importer must preserve separate intensity classes and coordinate any additive data-layer API with that owner. It must not silently collapse vigorous minutes into NHANES recreational moderate minutes. After the existing explicit read-back, confirmed supported answers use `source: wristband`, `estimated: true`, through `TwinRepository.saveConversationProfile`. `repo.outsideAiProfile()` excludes those values. Raw minute records remain in phone memory and never leave the phone. UI entry points belong to Daniel's design session.

## Synthetic contract examples

`../app/test/fixtures/band/` contains proposed examples only, not hardware recordings:

- `full_day.lifetwinband`: twelve hours worn, separate activity classes and optional heart rate.
- `gaps_nonwear.lifetwinband`: missing time and explicit non-wear; insufficient wear must stay unknown.
- `midnight_offsets.lifetwinband`: midnight plus a recorded offset change; dates/instants must remain distinct.

## Agreement and acceptance still needed

1. Hardware owner: can firmware emit these fields and separate moderate/vigorous classes, with a reliable clock/offset and wear flag? Supply the real current export if its shape differs.
2. Daniel/model owner: which observed summaries may be offered to which profile fields, especially recreational-only minutes and total sitting? Confirmation does not itself establish calibration.
3. Confirm JSON envelope/extension, limits, duplicate/replacement policy and whether daily files can contain buffered prior days.
4. Then implement native Files and Open-in delivery, strict parser, calendar aggregation, atomic/idempotent import and fake-picker tests. Native URLs need security-scoped access and bounded reads; received files must be deleted from app Inbox after processing.
5. Acceptance requires a **real band export on an iPhone**, its confirmable suggestions/provenance, and all `test/band/` checks. Synthetic fixture success is not that acceptance test. BLE requires a separately agreed GATT service/characteristic and stays optional.
