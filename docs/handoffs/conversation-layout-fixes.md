# Experiment and Check-in accessibility layout fixes

Local branch: `codex/c-conversation-layout-fixes`, based on merged main
`27c973654f4ca44475dbc4dddbcdbf5d0198bdf6`. No push, PR or merge is claimed.
Root coordinated the existing owners; these focused fixes address #147 and #149.

Experiment's Today and What-if pills now take their natural size in a wrapping row
below the mascot plate. They grow independently of the name banner and each other,
rather than sharing fixed overlay coordinates. Existing text, semantics and model
comparison behavior are preserved.

Check-in's speech bubble now takes real, full-width space below its mascot plate in
the page's scroll flow. The fixed plate no longer clips a growing question outside
its scroll extent. On a question/keyboard-geometry transition, the question is revealed
above the answer dock without moving text focus or clearing the draft. An unrelated
rebuild does not reset the person's scroll. Only Check-in's own answer region is bounded
against the keyboard-reduced height; its chips wrap and the answer region can scroll,
so extra choices do not consume the question's viewport.

No text-scale clamp, hidden question/label, health/model/state change, dependency or
contract change was added. Home, `room_scene`, `today_card`, shared `PlateWindow` and
shared `ExperimentPage` are untouched. The mascot remains in the conversation's
scrollable plate, with the prompt and detailed question below it.

Validation used Flutter 3.47.0 / Dart 3.13.0 in an isolated temporary app copy, with the
SDK floor changed only in that copy. The repository floor and lockfile are unchanged.
Bundled Fredoka/Atkinson fonts were loaded for actual glyph geometry.

- New geometry regressions: **7 failed before, 7 pass after**. Experiment checks normal,
  1.6 and `53 / 17` text scale; the last is the earlier native maximum read-back of
  17 → 53 pt. Pills clear the banner/each other and retain their chosen text size.
- Check-in checks 375 and 402 pt widths at 1.6 and maximum-equivalent scale, with a
  336 pt keyboard inset and safe areas. Sleep and next sitting prompts are fully above
  the dock and below the opaque header, input/Send remain visible, draft/focus persist,
  an unrelated rebuild preserves user scrolling, and no completed check-in is saved.
- Relevant combined run: **90 tests pass** (`conversation_layout_test.dart`, `checkin/`,
  `experiment/experiment_screen_test.dart`).
- Targeted analysis of both screens and the new test: **no issues found**.
- New test formatted; `git diff --check` passes.

These are host geometry and behavior tests. No simulator was booted or modified for
this fix, and no actual VoiceOver, native keyboard, native maximum-text screenshot,
landscape/tablet or dark-mode acceptance is claimed. Root's composed native regression
is the next dependency before closing the issues or claiming current app acceptance.
The earlier #134 partial report remains evidence of the preceding release, not proof
that these patches passed native verification.

For the native verifier, existing selectors are unchanged: Home's Check in action,
question `How did you sleep?`, text field `Type your answer`, `Send`, `Skip`; the next
sitting prompt is `How much sitting?`. Recheck both the initial keyboard-open question
and next-question transitions, plus independent body/dock scrolling. Experiment still
has `Today`, `What-if`, and the name banner, now in separate natural layout regions.
