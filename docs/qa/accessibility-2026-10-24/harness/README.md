# Isolated native accessibility harness

This is test instrumentation, not a product UI change or an automated acceptance pass.
Use a fresh `/private/tmp` copy of `app/` from pin
`1a648bd405df4c76b5c1dea3339194c31201913c`. Keep the shipping SDK floor unchanged;
this run used Flutter 3.47.0/Dart 3.13.0 with a temporary floor only in that copy.

Apply `font-probe.patch` inside that copy. It adds an app-temp JSON font read-back
and optional compile-time `QA134_SCALE` override around the existing app wrapper.
Without that define, the native text scaler passes through unchanged. Seed data is
production `DEMO_SEED=1`; never substitute expected score constants. Use only the
isolated `com.danielqi.lifesim.a11y134` bundle. Copy `A11y134UITests.m` into
`ios/A11y134UITests/`, then run `ruby setup_native.rb /private/tmp/COPY` once.
The script requires the already-installed xcodeproj gem and preserves Flutter's
Prepare preaction from the canonical scheme. Do not add a package dependency.

Run `server134.py` with the repository's Python environment and its `server/` on
PYTHONPATH. It binds only 127.0.0.1:8134, explicitly blanks all provider keys,
uses onboarding demo/template responses and disables access logging. Coordinate
ports and simulator exclusivity before execution. No physical phone.

Build the isolated app with `flutter build ios --simulator --debug --no-codesign
--no-pub --dart-define=DEMO_SEED=1 --dart-define=API_BASE_URL=http://127.0.0.1:8134`.
For 1.6 add `--dart-define=QA134_SCALE=1.6`; for largest native text omit it and set
`xcrun simctl ui UUID content_size accessibility-extra-extra-extra-large`.
The native helper's `variant` changes screenshot names only; set it to the mode.
Read actual `tmp/qa134-font.json` from the isolated app data container after launch.

Use `xcodebuild build-for-testing` and `test-without-building`, workspace
`ios/Runner.xcworkspace`, scheme `A11y134Acceptance`, Debug, explicit simulator UUID,
isolated derivedData/resultBundle paths, `CODE_SIGNING_ALLOWED=NO`,
`-parallel-testing-enabled NO -collect-test-diagnostics never`. Bound test execution
with `-test-timeouts-enabled YES -maximum-test-execution-time-allowance 180`.
The final bounded AX5 run selects only tests 01/02/03/05/08. Other deep-route methods
are follow-up drafts: failed navigation must remain BLOCKED, never a product failure.

Screenshots/text are written into the UI test runner's Documents/qa134-shots and
xcresult. Refresh its data-container path after each run: XCTest reinstalls it.
Only settled, correct-route images count. `exists`/`hittable` may be true for 0×0
Flutter nodes; the helper requires a nonempty visible frame before attempting a
measured-center tap. Always assert/inspect the actual destination afterward.

Actual VoiceOver APIs are iOS 27+. The native probe records enabled state, spoken
output/errors and finally restores the initial state. Tree labels/order and audit
reports alone do not prove VoiceOver traversal. Secondary-route NoSpeech results
in this run remain a diagnostic limitation. Audit issueHandler returns YES solely
to collect findings; `ran=1` is never an accessibility pass. Verify exact visible
controls manually; exclude offscreen/clipped frames from target-size conclusions.

Restore initial font/appearance/VoiceOver and simulator state. Remove only the
isolated app and runner, stop this server. Preserve raw results locally; commit
compact evidence and a hash manifest, not xcresult or giant native trees.
