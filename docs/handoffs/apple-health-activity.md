# Apple Health activity handoff — October 24, 2026

Track / task: C data/native adapter, #106. Numeric workout estimates implemented in the data API; UI/device
acceptance remains. Sitting is unavailable. Do not claim measured minutes in zones.

Result and files changed: `app/lib/health/health_summary.dart` adds the three model fields, availability reasons and
native estimate candidates with `isEstimate: true`. `health_reader.dart` exposes the real `readSummary()` path;
`workout_averages.dart` strictly parses the bounded native aggregate. `readback.dart` explains whole-workout mean
intensity grouping, incomplete recordings, recreational context and usual-week representativeness before explicit
confirmation. `HealthActivityBridge.swift` directly reads optional native MET quantities and recorded active duration,
with native registration in AppDelegate/project and simulator fixture tests. No screens, widgets or engine edits.

PR URL / merge state / merge commit: local branch `codex/c-health-activity`, extending partial baseline `8e6de0e`;
not pushed, no PR, not merged. Root owns integration and QA #107.

Contract or model versions affected: app-only channel `lifetwin/health_activity.readWorkoutAverages`, schema
`apple_health_workout_averages.v0`. [Coordination](https://github.com/ViktorOsadsky/lifetwin/issues/106#issuecomment-6393243281).
Existing server/profile/model contracts
are unchanged. Existing generic `read()`/`summarize()`, Exercise Time suggestion and onboarding split are preserved.

Method: native query covers 28 days, maximum 2,000 workouts plus overflow sentinel, five-second timeout. Compatible
`HKMetadataKeyAverageMETs` quantities classify each whole workout as mean 3–<6 METs or ≥6 METs. Recorded active
seconds per group / 240 gives four-week average weekly minutes. Available pause/resume events must agree with
recorded duration. Duplicate UUIDs count once; overlap groups, boundary workouts, invalid duration/metadata and
light intensity are excluded. Query overflow suppresses estimates. Missing buckets and sub-minute rounded averages
remain unanswered. No heart-rate/workout-name classification and no standing-to-sitting conversion.

Checks actually run and results: all 57 focused Dart/Flutter tests passed across the new native-aggregate/parser
tests and existing Health summary/contract/read-back/screen/offer suites. Targeted analysis of `lib/health` and those
seven test files found no issues. All seven `HealthActivityTests` passed through `xcodebuild test` on iOS 26.4
simulator `7F21AE4A-232B-458E-A5B7-F7EA7952BD01`; native extraction used actual HKWorkout/MET/pause-event objects.
The first native run rejected one malformed-metadata test fixture during HealthKit construction; the final suite
tests that malformed value at the conversion boundary and passes. Project plist lint, Dart formatting and
`git diff --check` passed. Native result bundle: `/private/tmp/lifetwin-health106-native-final-results.xcresult`.
Validation uses Flutter 3.47.0 / Dart 3.13.0 in `/private/tmp/lifetwin-health-106-validation/app`, lowering the SDK floor
only in that temporary copy. The repository's Dart `^3.13.7` floor remains unchanged. The simulator-only validation
bundle is `com.danielqi.lifesim.healthqa106`; no physical iPhone or HealthKit writes are authorized/used.
After native tests, only that isolated simulator app and its test suffixes were removed and verified absent;
the assigned simulator was restored to its initial Shutdown state. Production apps were not changed.

Real, fixture, or unavailable integrations: `HealthReader.readSummary()` calls the real native adapter. Native tests
construct actual HKWorkout/MET/pause-event objects without writing HealthKit; Dart tests mock channel responses.
Availability of optional MET metadata on a user's actual workout source remains unverified. The pinned health 13.3.2
plugin omits workout metadata, which this app-owned helper bypasses. All raw native workouts/MET metadata stay
native/on-phone; only bounded averages and exclusion counts cross to Dart. No new provider payload or retention.

Known limits / blockers: whole-workout mean intensity is an approximation, not time in zones or a validated match
for the model's self-reported relative effort. Missing recordings, unrecorded pauses and source errors remain possible.
Read-back must retain explicit recreation and representativeness confirmation; no unconfirmed value enters the
profile. Sitting requires its own supported awake-sitting source. Unsupported platforms/native errors/invalid results
preserve legacy candidates and typed unavailable reasons. Source-linked method/API notes are in `docs/apple-health.md`.

Next dependent task: Daniel switches the current generic HealthImportScreen data call to `readSummary()` while
retaining explicit confirmation/rejection, then verifies real-source MET availability and the final read-back flow on
his device. Root handles integration/QA #107; this data task does not claim end-to-end #106 acceptance.
