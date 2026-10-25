# Apple Health activity handoff — October 24, 2026

Track / task: C data layer, #106. Partial implementation; do not close the issue.

Result and files changed: `app/lib/health/health_summary.dart` adds the three model field names, bounded validation
ranges and `summarizeWithAvailability()`. It reports why each new field remains unavailable instead of supplying
zeros. `health_reader.dart` exposes `readSummary()` over the real reader. `readback.dart` covers the three fields with
Apple Health attribution, recreational/awake-sitting context, four-week averaging and confirmation. Fixed-sample
tests cover absent data, walking/Exercise Time without a validated split, running/heart rate, stand-hour ambiguity,
old/future/malformed readings, unchanged legacy suggestions and raw payload shape. The Apple Health guide records
primary-source findings and the exact positive-path gap. No screen or engine edits.

PR URL / merge state / merge commit: local branch `codex/c-health-activity`; not pushed, no PR, not merged. Root owns
integration and QA #107.

Contract or model versions affected: app-only Health enum/read-back/summary APIs; existing profile keys and ranges
already accept the three fields. No JSON schema, server, model or provider contract change. Existing Exercise Time
suggestion and the other owner's onboarding split are preserved.

Checks actually run and results: 34 tests passed across `health_activity_test`, `health_summary_test`,
`health_contract_test`, `readback_test`, `health_screen_test` and `health_offer_test`. Targeted analysis of
`lib/health` and those six test files found no issues. Dart formatting (120-column repository convention) and
`git diff --check` passed. Validation uses Flutter 3.47.0 / Dart 3.13.0 in
`/private/tmp/lifetwin-health-106-validation/app`, lowering the SDK floor
only in that temporary copy. The repository's Dart `^3.13.7` floor remains unchanged.

Real, fixture, or unavailable integrations: `HealthReader.readSummary()` calls the real HealthKit reader. Tests use
fixed samples. Real numeric suggestions for **all three new fields are unavailable and unimplemented**. Native iOS
`health` 13.3.2 omits workout metadata, and even average METs/heart rate would not establish recreational active
minutes. Stand Hour counts hours with at least a minute standing/moving, not sitting duration.

Known limits / blockers: no native numeric-mapping positive path. It needs supported recreational context plus
intensity-specific active-minute/coverage data and an approved estimator; awake sitting needs its own measurement
that separates sleep and non-wear. Do not claim synthetic fixtures establish that capability. No new raw data or
metadata leaves the phone; a future agreed implementation may send only confirmed bounded averages for these fields.
Existing raw-sample provider policy remains separately scoped and unchanged. No device/permission validation claimed.

Next dependent task: Daniel/model owner decides a supported estimator/source or keeps these inputs as conversation
questions. Then implement and validate the numeric path before closing #106. Root handles integration/QA #107.
