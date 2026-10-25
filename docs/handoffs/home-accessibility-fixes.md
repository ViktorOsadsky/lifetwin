# Home accessibility fixes — #142 and #150

Track C, coordinated with the #134 audit. Daniel's screen ownership is unchanged.
Product branch `codex/c-home-accessibility-fixes` started at `27c9736`; PR160
merged as `bda309e`. The final tested production fix is `3930b80`. This evidence
is on separate branch `codex/c-accessibility-fix-evidence` from owner main `50cdac9`.
Focused native evidence composes it with conversation PR161 (`828f624`, merged `ef4d20c`);
actual VoiceOver traversal remains blocked, separately from host semantics.
Later owner PR165 score collapse and PR164 reset changes are outside that native
source and remain unverified by these captures.

## Result and affected contracts

- `room/room_scene.dart`: the activity pill is no longer a live region. Ambient
  walking/relaxing changes update its accessible current-activity label quietly.
  Its button role, 48-point hit area and change-activity action remain available.
- `wellness/home_panel.dart`: score direction labels use their measured width at
  the selected text size and bold setting. They stack with full available width
  before the horizontal arrangement would fragment words. Score, percentile,
  marker and caveats keep the existing model values and meaning.
- `wellness/today_card.dart`: the condensed card retains its two-line compact preview
  at normal text size. At scale >=1.5 it shows the full summary above the separate
  Check in action. The normal layout keeps the action alongside the summary. Both actions retain
  their existing callbacks; no text-size cap or scale-down widget is added.

No profile, model, API, planner or persistence contract changes. The natural card
height can increase, so Home may need scrolling at larger accessibility sizes.
The original defects are captured in the [#134 evidence](../qa/accessibility-2026-10-24/).

## Checks actually run

Host validation used `/private/tmp/lifetwin-home-accessibility-validation/work/app`,
Flutter 3.47.0 / Dart 3.13.0 and the existing package cache. Only that temporary
copy lowers the SDK floor from `^3.13.7` to `^3.13.0`; repository requirements are
unchanged. Test plans are synthetic and clients deterministic; no provider calls.

- 16 focused regressions pass: quiet changing activity semantics with an operable
  action, and geometry/tap tests at 375/402 logical pixels with scales 1, 1.6 and
  53/17 (the observed native AX5 equivalent). Actual glyph-selection boxes must
  keep each word on one line; large-text summaries must not exceed their laid-out text, and
  tapping Check in must not open the plan. The selected scaler is checked directly.
- Negative control in the temporary copy, using the original three production
  files: 9 expected failures / 4 passes. It detects the ambient live-region flag,
  AX5 word fragmentation and truncated summaries. Three additional intrinsic-sheet cases protect the shared score scale.
- The initial 91 related tests passed across `home_accessibility_test.dart`, `today_card_test.dart`,
  `score_index_ui_test.dart`, `home_card_test.dart`, `home_layout_test.dart`,
  `home_order_test.dart` and `room_screen_test.dart`.
- Focused analysis of all three changed production files and the new test file
  passes with no issues. `git diff --check` passes.

The first broader run had three temporary-path failures because existing screenshot
tests write two directories above the app. A nested validation directory corrected
that environment issue; no production or existing test change was needed.

## Next dependency and limits

The focused native regression with the separate Experiment/check-in fixes is
recorded in [the composed evidence](../qa/accessibility-fixes-2026-10-24/README.md).
It captures 1.6 and maximum native text with readback and inspects scrolling content.
The bounded actual VoiceOver attempt could read the initial room description but
returned NoSpeech on traversal; quiet ambient speech acceptance remains BLOCKED.
Host semantics flags do not establish spoken output, focus retention or native
touch accessibility. This patch does not claim a full accessibility audit pass.
No physical iPhone was used. Native evidence uses only the isolated iOS27 simulator.


CI follow-up: the full suite exposed two integration regressions missed by the initial focused set.
The score scale now uses intrinsic-compatible `OverflowBar`, protecting the existing score/reveal sheet.
Normal-size Today keeps its existing two-line compact preview and opens the full plan on tap; at large text
it expands fully with Check in beneath. The existing long-plan compact-height test and lifespan reveal flow
are included in the expanded validation. Native capture uses these corrections. Root then ran all 35 focused/integration tests,
all 1191 Flutter tests (41 seconds), and focused analysis cleanly. The first full
temporary copy lacked sibling contracts/model fixtures (1185 passed, three environment
failures); syncing them yielded the complete pass. A separate latest-main composition
with Health/reset `8b6e91f` plus both UI patches passed all 1217 Flutter tests and full
analysis; that host composition is distinct from the native base `27c9736` overlay.
