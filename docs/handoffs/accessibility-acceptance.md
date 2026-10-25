# Accessibility acceptance #134 — partial, October 24, 2026

**Findings reproduced; acceptance remains incomplete. Keep #134 open.** This is actual
simulator evidence from the product app, with missing routes and VoiceOver coverage
explicitly blocked. No production UI, engine, contract, SDK-floor or dependency changed.

## Release and environment

Final layout/native probe pin: **`1a648bd405df4c76b5c1dea3339194c31201913c`**. The prerequisite
#126 had merged before execution. Subsequent #138 centered the score at 0, and #141 changed
Home and the score explanation. Rosa's actual seeded score is **+0.59**, with 0 the group
middle; the circled information action now opens **About the health score**, rather than
the older drivers route. Earlier issue/preflight expectations 1.65/1.81 are superseded.
Historical 9ace captures are not current-main layout acceptance.

The isolated production app ran on iPhone 18 Pro, iOS 27.0 / Xcode 27.0, simulator
`AD68AA8D-3700-4E9C-B1E9-FE441057C67B`, bundle `com.danielqi.lifesim.a11y134`, with
production `DEMO_SEED=1` synthetic data. A keyless localhost 8134 server supplied real
check-in/template routes; no outside AI, real profile, HealthKit writes or physical phone.
Flutter 3.47.0/Dart 3.13.0 and a temporary compatible SDK floor were used only in the copy.
[Source comparison](../qa/accessibility-2026-10-24/evidence/source-check.json) found no asset
differences and only the disclosed test-only `lib/main.dart` font probe among app sources.

Light appearance was used throughout. The 1.6 pass used an isolated `TextScaler.linear(1.6)`
override: 17→27.2 pt,20→32 pt,48→76.8 pt. The native maximum pass used
`accessibility-extra-extra-extra-large` with **no override**: 17→53 pt,20→62.35294 pt,
48→149.64706 pt. See [1.6 read-back](../qa/accessibility-2026-10-24/evidence/scale16-font.json)
and [native maximum read-back](../qa/accessibility-2026-10-24/evidence/ax5-font.json).
“Sunlight” here means light appearance; physical sunlight and increased-contrast behavior
were not tested. Reduced motion/increased contrast were not changed.

## Confirmed findings

- [#142](https://github.com/ViktorOsadsky/lifetwin/issues/142): Home automatic mascot
  live-region announcements interrupt control speech. The original 9ace actual VoiceOver
  trace established the interruption; source `room_scene.dart:493` is unchanged at the
  final pin, and the final native probe again interleaves activity announcements.
  This does not establish unreachable controls or a focus trap.
- [#147](https://github.com/ViktorOsadsky/lifetwin/issues/147): Experiment name badge
  overlaps Today/What-if labels at 1.6; native maximum text worsens the same overlap.
  [1.6 evidence](../qa/accessibility-2026-10-24/evidence/scale16-experiment-hub.png),
  [native maximum](../qa/accessibility-2026-10-24/evidence/ax5-experiment-hub.png).
- [#150](https://github.com/ViktorOsadsky/lifetwin/issues/150): Home at native maximum fragments Higher risk / Better health into letters around
  Average, and reduces the Today summary to fragments beside Check in.
  [Scale labels](../qa/accessibility-2026-10-24/evidence/ax5-home-scroll1.png),
  [Today summary](../qa/accessibility-2026-10-24/evidence/ax5-home-scroll4.png).
  [Local draft](../qa/accessibility-2026-10-24/local-drafts/home-largest-text-readability.md).
  This is readability failure, not navigation loss.
- [#149](https://github.com/ViktorOsadsky/lifetwin/issues/149): Check-in clips the current sleep question behind the fixed Skip/input dock while the
  keyboard is open, at 1.6 and native maximum. Two attempted scrolls retain the crop;
  a background tap did not dismiss the keyboard. Keyboard-dismissal recovery remains
  unverified. [1.6](../qa/accessibility-2026-10-24/evidence/scale16-daily-checkin.png),
  [maximum](../qa/accessibility-2026-10-24/evidence/ax5-daily-checkin.png),
  [local draft](../qa/accessibility-2026-10-24/local-drafts/checkin-keyboard-clipping.md).
  No claim of permanent loss or unreachable input.

All four confirmed findings are filed on GitHub. The retained drafts record their reproduction details.
Design owners choose fixes; this QA does not assign new owners or change production UI.

## Seventeen-state matrix

PASS means the captured content/action was readable in a settled, correct-route image.
It is not whole-app acceptance. BLOCKED includes incomplete capture, unproven destination
or native VoiceOver diagnostic limitations; these are not product failure claims.
The machine-readable [matrix](../qa/accessibility-2026-10-24/matrix.json) records the same
coverage. No current default-font full sweep is claimed.

| Required state |1.6 layout|Native maximum layout|Actual VoiceOver|Coverage/remaining dependency|
|---|---|---|---|---|
|Onboarding consent|PASS|BLOCKED|BLOCKED|Voice/typed consent choices captured; maximum not run|
|Onboarding conversation|BLOCKED|BLOCKED|BLOCKED|Capture reached AI consent, not actual question/input|
|Onboarding read-back|BLOCKED|BLOCKED|BLOCKED|Typed end-to-end sequence not completed|
|Onboarding reveal|BLOCKED|BLOCKED|BLOCKED|Actual reveal not reached|
|Home|PASS|FAIL|FAIL, partial|Large-text failures above; score/value/info spoken order still incomplete|
|Score information|PASS|PASS|BLOCKED|New zero/group explanation, caveats and Got it reached by scroll|
|Daily check-in|FAIL|FAIL|BLOCKED|Keyboard-open prompt crop; full recovery not proven|
|Experiment hub|FAIL|FAIL|BLOCKED|Mode-label overlap; footer reachability not disproven|
|Experiment lever|BLOCKED|BLOCKED|BLOCKED|Native navigation did not establish actual Sleep route|
|Experiment result|BLOCKED|BLOCKED|BLOCKED|No current valid result capture|
|Ideas list|BLOCKED|BLOCKED|BLOCKED|Earlier named capture remained on hub|
|Ideas detail|BLOCKED|BLOCKED|BLOCKED|No current valid detail capture|
|Ideas effect sheet|BLOCKED|BLOCKED|BLOCKED|No current valid effect-sheet capture|
|Band panel|BLOCKED|BLOCKED|BLOCKED|Pairing introduction only; aggregate panel not reached|
|Settings|PASS|BLOCKED|BLOCKED|1.6 choices/My data readable; maximum captures only upper/mid rows|
|History list|PASS|BLOCKED|BLOCKED|Readable 1.6 list; no maximum capture or actual spoken traversal|
|History day sheet|BLOCKED|BLOCKED|BLOCKED|Named detail image was list; excluded from acceptance|

Home's Customize/Fortune labels are below the initial 1.6 viewport but fully visible after
normal scrolling: [scrolled Home](../qa/accessibility-2026-10-24/evidence/scale16-home-scroll4.png).
Expanded cards covering the mascot alone are not accessibility defects. The score sheet
retains the group/zero explanation, confirmation caveat and Linked, not proven text;
[1.6 sheet](../qa/accessibility-2026-10-24/evidence/scale16-score-info.png) and
[maximum scrolled sheet](../qa/accessibility-2026-10-24/evidence/ax5-score-info-scroll2.png).
At maximum, the Experiment footer is scrollable in source; an initially below-viewport
button does not prove it is unreachable. No such issue is filed.

## Native speech, targets and contrast

The final-pin actual `XCUIVoiceOverService` probe asserted enabled=YES, recorded current
speech and eight forward utterances, then restored initialEnabled=0/finalEnabled=0.
It completed **1 test, 0 failures, 28.680s**. [Compact speech trace](../qa/accessibility-2026-10-24/evidence/voiceover.txt)
contains twin name, Quiz, Add band, My history, Settings and What moves your score,
interleaved with automatic activity speech. Eight steps did not reach numeric score/info
read-back; those are not passed. Earlier secondary-route probes returned NoSpeech when
moving forward and repeated Back when moving backward despite populated native trees.
This remains a traversal/API diagnostic limitation, not proof those routes trap VoiceOver.
No static Semantics tree is represented as actual spoken navigation.

[29 sampled fully visible native button frames](../qa/accessibility-2026-10-24/evidence/target-samples.json)
on reliable 1.6 screens all meet 44×44 pt; most meet 48×48 pt. Offscreen/zero-size/clipped frames
were excluded. This does not certify all targets, spacing, actions or maximum-size controls.
[Source-palette samples](../qa/accessibility-2026-10-24/evidence/contrast-samples.json) give
ink/paper 11.98:1, secondary/paper 7.40:1, ink/mint 7.65:1 and ink/lavender 6.29:1. These are
limited source-color calculations, not an exhaustive rendered contrast/sunlight audit.
Native audit findings were collected for review; a handler allowing audit collection and
`ran=1` are never counted as an accessibility pass.

## Execution, artifacts and handoff

Current 1.6 native capture batch: 9 targets, 4 navigation/assertion failures (History,
Experiment, Ideas, band); an attempted deep-route supplement was stopped. Final bounded
native-maximum batch:5 targets, 1 harness navigation failure (Sleep),146.053 s. Completed
capture methods are not equivalent to visual PASS; the matrix reflects observed failures.
There were no further navigation repairs after that bound. The actual app and native target
built successfully; Ruby setup syntax and Python server syntax checks pass. No full suite
was repeated for this documentation/evidence change.

[Harness/protocol](../qa/accessibility-2026-10-24/harness/README.md) includes actual native
source, font-only patch and keyless server. Deep-route methods remain follow-up drafts;
use destination postconditions before any acceptance claim. The reproducible target is
iOS 27 because the installed VoiceOver API is 27+. Native control trees/audits on 26.4 alone
cannot establish actual VoiceOver speech.

Committed images are original native PNGs from settled synthetic captures; captured pixels are preserved. No xcresult,
giant tree, transition frame or wrong-route detail image is committed. The
[raw manifest](../qa/accessibility-2026-10-24/raw-manifest.json) records SHA256 and local paths
for retained full-resolution frames/logs under `/private/tmp/lifetwin-accessibility-134`;
local paths are diagnostic retention, not durable shared hosting. The old preflight protocol
remains temporary/historical and is superseded by this final pin/expectation record.

Cleanup completed: VoiceOver disabled by finally, native font restored Large, appearance
restored light, only `.a11y134` app/runner removed, assigned simulator restored Shutdown;
local 8134 server/exporter stopped. [Cleanup record](../qa/accessibility-2026-10-24/evidence/cleanup.json).
No physical phone or other owner's simulator/app was changed.

Branch `codex/c-accessibility-acceptance` is prepared for a documentation/evidence PR.
Root publishes the reviewed record; #134 stays open for the coverage gaps above.
Next dependency: design-owner fixes confirmed bugs, then targeted actual-app rechecks plus
completion of blocked routes, full numeric score/caveat VoiceOver read-back, secondary
VoiceOver order/actions, all-target measurement and comprehensive contrast validation.
