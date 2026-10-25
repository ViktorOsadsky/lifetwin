# Focused native regression of Home and conversation fixes

Synthetic demo data only. Native source is base `27c973654f4ca44475dbc4dddbcdbf5d0198bdf6`
with Home `3930b80a597da725166cee3bb2d213ff2c80ae1a` and conversation
`828f624f461ebe42afc097710c5d1bcee678eb14` overlays. This checks proposed fixes
before merge, not every screen or the current engine's numerical parity.
Daniel retains ownership of the screens.

**Historical source boundary:** the record branch starts from owner main
`50cdac993c108fc156858169d65d213feb093ccf`, after PR160 merged as `bda309e`
and PR161 as `ef4d20c`. The screenshots still show the explicitly pinned proposed
composition above. Subsequent PR165 collapsible score and PR164 full reset are
**not** accepted by these native captures; do not use them as the current Home
layout or as reset acceptance.

## Environment and provenance

- iOS 27.0 simulator, iPhone 18 Pro, `AD68AA8D-3700-4E9C-B1E9-FE441057C67B`.
  Initial state Shutdown; light appearance and Large content size.
- Temporary app `/private/tmp/lifetwin-a11y134-validation`; isolated bundle
  `com.danielqi.lifesim.fixes134`, runner suffix `.A11y134UITests.xctrunner`.
- Flutter 3.47.0 / Dart 3.13.0. SDK floor lowered only in the temporary copy;
  repository SDK requirements unchanged. Real product demo seed and screens,
  plus a test-only font probe/optional scaler override around the existing wrapper.
- Keyless local template server on 127.0.0.1:8134, provider keys explicitly blank,
  access logs disabled. No real profiles, physical devices or paid provider calls.
- Original screenshots are 1206 × 2622 pixels, unedited. SHA-256 manifest records
  committed evidence; `source-manifest.json` records actual copied app sources.
  The displayed score is a UI observation, not fresh model-parity acceptance.

## Host validation (separate from simulator)

Root ran 35 focused Home/intrinsic/lifespan-reveal/Ideas tests and analysis of the
four changed/test files on Home `3930b80`; all passed. Its full copy passed all
1191 Flutter tests in 41 seconds after syncing sibling contracts and model-handoff
fixtures. An earlier incomplete copy passed 1185 with three environment failures.

CI had exposed two real integration regressions in the initial Home patch: a
LayoutBuilder under IntrinsicHeight and loss of the compact normal-size Today
preview. `3930b80` corrects both with intrinsic-compatible OverflowBar and a
normal-size two-line preview; full Today text expands at scale >=1.5.

Root separately composed latest owner main/Health/reset `8b6e91f` with these two
UI patches: 1217 Flutter tests passed and full analysis was clean. Its source
overlays are recorded in `composed-host-source.json`. That newer host composition
is not the source used for the native screenshots below.

## Actual native results

| Focused check | 1.6 | Maximum native AX5 |
| --- | --- | --- |
| Home direction words, Today summary and separate Check in | Observed pass | Observed pass across scrolls1–2 |
| Score explanation caveats and Got it | Observed pass | Observed pass across explanation scrolls |
| Experiment banner/mode separation (#147) | Observed pass | Targeted separation/What-if observed; Today only partially captured |
| Initial sleep prompt with keyboard, exact draft retained | Observed before unrelated harness-title failure | Final focused test passes, 22.332s |
| Shared Experiment toolbar title | No separate acceptance | **FAIL** vertical cropping/ellipsis; separate header follow-up |
| Actual quiet ambient VoiceOver (#142) | **BLOCKED** NoSpeech traversal | Not rerun |

The Experiment header is a separate discovered defect, visible in
`ax5/ax5-experiment-body1.png`; the fixed-height toolbar crops the title as text
scales. These observations do not establish a whole-Experiment accessibility pass.
At AX5, the generic body gesture starts over the dock, so independent body scroll
offset is not established by this native keyboard method. Full prompt visibility,
exact draft and keyboard retention are established; body scrolling is separately
observed at 1.6 and covered by host tests.

See `results.json` for per-check outcomes. Passing an XCTest that collects a
blocked diagnostic does not make VoiceOver pass. Speech verification remains
BLOCKED and #134 remains open: the bounded initial probe and one clean Home retry
could not traverse to unrelated Settings while observing ambient transitions.
The retry read an initial room utterance, then `moveForward` returned
`com.apple.xctest.voiceoverservice` Code 3 `No speech available`. Original VO state
was false and restored false. Host semantics prove removal of the live-region
flag and retained activity action; they do not prove spoken non-interruption.

The first keyboard harness dragged over the software keyboard and changed its
own draft. A corrected measured-dock run preserved exact draft `7` and keyboard,
and Skip visibly reached `Did you move?`; that method still failed an incorrect
expected sitting title. A later attempt failed on XCTest's inconsistent Flutter
TextField hit frame before typing. These are retained as failed harness attempts,
not product passes or product defects. Final keyboard scope is initial full sleep
prompt, focused typing, independent body/dock scrolling, exact draft and keyboard.
Dynamic next-question behavior is covered by host tests, not claimed as a complete
native check here.

## Reproduction

Use the existing [native harness setup](../accessibility-2026-10-24/harness/README.md)
in a temporary copy, but use the base/overlays and isolated fixes134 identifiers
above and replace its Objective-C helper with `harness/A11y134UITests.m` here.
Keep the existing setup script's scheme and font probe; do not alter product UI.

Build with `DEMO_SEED=1`, `API_BASE_URL=http://127.0.0.1:8134` and, for the 1.6
run only, `QA134_SCALE=1.6`; the helper variant changes output names only. For AX5,
omit QA134_SCALE and set simulator content_size to
`accessibility-extra-extra-extra-large`. Verify app `tmp/qa134-font.json` after
launch. Select only test01Home/test02ExperimentModes/test03KeyboardCheckIn for
layout. Test04 is the bounded optional speech diagnostic; never convert NoSpeech
to pass. Use explicit simulator ID, `-parallel-testing-enabled NO`,
`-collect-test-diagnostics never`, `CODE_SIGNING_ALLOWED=NO`, and maximum test
execution allowance 180. Refresh the runner data-container path after every
invocation; copy only the current variant from Documents/fixes134-shots.

Raw xcresults/build logs stay in `/private/tmp/lifetwin-accessibility-fixes-134`.
Do not treat offscreen viewport crops as missing content: inspect each full scroll
sequence and actual destination. Restore original settings/state and uninstall
only the isolated app/runner after execution.

## Cleanup actually completed

The isolated app and runner were uninstalled. Large content size and light
appearance were restored/read back; actual native VO state was restored false.
The simulator returned to its initial Shutdown state, and the owned 8134 template
server stopped. No other app or physical device was used or removed.
