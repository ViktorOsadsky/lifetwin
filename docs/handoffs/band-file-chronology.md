# Band chronology regressions after #122 — October 24, 2026

Track / task: C file/data intake, follow-up to merged [#122](https://github.com/ViktorOsadsky/lifetwin/pull/122), which closed [#114](https://github.com/ViktorOsadsky/lifetwin/issues/114). Existing UI and hardware/model owners are unchanged.

Baseline: `e3ba5da`, including the owner's import guards and the merged [#117 sitting boundary](https://github.com/ViktorOsadsky/lifetwin/pull/117). The earlier isolated chronology commit `9a175e5` remains preserved separately; this follow-up transplants only its 18-case test file, not its competing implementation.

Evidence before fixes: the transplanted tests produced 15 passes and 3 failures under UTC−11. Two failures showed an export instant before the last covered minute was accepted because #122 checked only the report day's start. The third showed an injected UTC clock used the UTC calendar rather than the phone's local date. Inclusive coverage, partial-day acceptance and atomic replacement already passed the owner's implementation.

Result and files changed: `app/lib/band/band_file.dart` compares export time against the last covered minute using the existing report-day UTC origin. It preserves the owner's day-start and inclusive-span guards. `band_store.dart` adds only `.toLocal()` when deriving today from the existing injected clock. The store's validation-before-mutation, explicit replacement, sitting aggregation and notifications are otherwise unchanged. No UI, engine or native change. Root coordinated one fixture correction in `band_sitting_test.dart`: its clock now constructs a local `DateTime` from the report calendar fields instead of treating UTC midnight as phone-local today. The unrelated v0/sitting assertion is unchanged.

Tests: `band_file_chronology_test.dart` adds 18 synthetic cases covering zero/one/full-day and inclusive-span boundaries, gaps, partial-day generation, export/report offset differences, UTC date crossings, local-phone today and clock rollover, atomic mixed-delivery replacement with existing reports/live minutes/last sync, and generic error privacy. Existing owner regression tests and the #117 sitting tests are retained.

Contract or model versions affected: none. The supplied `lifetwin.band_day.v0` schema and app-only `lifetwin.band_days.v0` wrapper remain unchanged. Consistency checks do not establish calibration or create questionnaire values. [Format and chronology](../wearable-file-format.md).

PR / merge state: local `codex/c-band-chronology-regressions` branch based on the combined main above; no push, new PR or post by this task. #114's existing closure is not a claim made by this follow-up.

Checks actually run:

- The combined committed `test/band` suite passed **242 tests** in both the normal environment and `TZ=Pacific/Pago_Pago` (UTC−11), including all 18 new chronology cases and the merged #117 sitting cases.
- The **18 chronology tests** separately passed with `TZ=Pacific/Kiritimati` (UTC+14). The injected-clock tests assert the expected local date in each configured zone.
- Targeted Dart analysis of `band_file.dart`, `band_store.dart`, `band_file_chronology_test.dart` and the corrected sitting test found no issues. Formatting, local documentation links and `git diff --check` passed.
- One **additional uncommitted local regression** parsed/imported the user-supplied daily v0 report with injected local today October 24: **accepted=true**. That private-file harness is outside Git and excluded from the 242/18 repository counts; no health/device/count values were printed.

The repository's SDK constraints and dependency files are unchanged; the temporary validation copy uses Flutter 3.47.0 / Dart 3.13.0 with only its SDK floor lowered to `^3.13.0` (Flutter also refreshes local tooling configuration). No physical iPhone was used.

Real, fixture or unavailable integrations: committed tests use synthetic v0 fixtures. Any user-supplied file regression is a separate temporary local harness, outside Git, reporting only acceptance or a generic safe error reason; its result is excluded from repository test counts.

Known limits: the fixed report offset cannot disambiguate repeated/missing daylight-saving hours. Future-date rejection is a store import guard; standalone parsing remains phone-clock independent. This follow-up does not add a separate future-export-instant check for reports dated today or earlier.

Next dependency: root reviews these remaining gaps and opens a focused follow-up PR if material, then checks the combined state under repository protections. Final UI/device acceptance remains with Daniel.
