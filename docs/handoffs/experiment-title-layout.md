# Experiment titles at large text sizes

Track / task: C — follow-up to accessibility QA #134. The native AX5 check after the #147/#149 fixes exposed a separate clipped Experiment header.

Result and files changed: `app/lib/experiment/experiment_page.dart` places the title and optional What-if pill in the existing full-width scrolling body. The title keeps its 26 pt style and the selected text scaler, wraps naturally, and has no line cap or ellipsis. The back-only 76 pt chrome remains pinned. Titles can scroll away, so long headings do not consume the body viewport. The untitled Check-in layout, keyboard behavior, and independently scrolling dock are preserved. `app/test/experiment/experiment_page_layout_test.dart` covers the new layout.

PR / merge state: locally committed on `codex/c-large-title-layout`; not pushed or merged. Base is `50cdac993c108fc156858169d65d213feb093ccf`, which includes #159 Health/reset, #160 Home accessibility, #161 conversation layout, #164 full reset, and #165 score collapse. The earlier `codex/c-conversation-layout-fixes` branch remains intact.

Contract or model versions affected: none. No health, profile, prediction, state, API, or provider logic changed.

Checks actually run:

- 107 tests passed: `flutter test test/experiment test/conversation_layout_test.dart test/checkin/daily_checkin_test.dart`. This includes 13 new geometry tests plus the existing keyboard-open Check-in and Experiment mode-label regressions.
- New portrait cases use bundled app fonts at 320 and 375 pt widths, 1.6 scaling and 53/17 scaling (the ratio observed in the native accessibility-size read-back). They check complete title semantics, every non-space glyph's layout, unclamped text scaling, clearance from navigation and the pill, body/dock reachability, and the pinned 52×52 pt Back action.
- A long-title case at 568×320 pt checks landscape scrolling and Back reachability. Words wider than the phone may wrap naturally; no horizontal title interaction is introduced.
- Negative control against the original header: 12 portrait tests failed; the landscape reachability control passed. With the fix, all 13 pass.
- Targeted `flutter analyze` for the production file and new test: no issues. `git diff --check`: clean.

Validation used Flutter 3.47.0 / Dart 3.13.0 in an isolated temporary copy. Only that copy's SDK requirement was relaxed to 3.13.0; repository SDK and lockfiles are unchanged. All guides and owners' production changes remain intact.

Real, fixture, or unavailable integrations: geometry tests render the actual ExperimentPage with synthetic body/dock content and the real fonts. Existing tests exercise actual Experiment and Check-in routes with their established fakes. No simulator, physical device, live provider, or native VoiceOver test was run for this patch.

Known limits / blockers: widget geometry does not establish native accessibility traversal. Native AX5 validation of the title, scrolling, Back, and dock is the next dependency, owned by the agent holding the iOS 27 simulator. This patch does not close the remaining #134 acceptance gaps.

## Merged with #212

#212 (merged to main) put Back, Home and the title in one pinned top row. This branch combines the two: the pinned 76 pt bar holds Back and, where #212 shows it, Home (the Home button rides with `RoundBackButton`, which also carries `onLeaveCheck`); the title and optional What-if pill stay in the scrolling body as above, so large-text titles are never clipped and Home can never cover them. Plate-window pages without a title keep #212's behaviour (Back moves into the bar row when Home is shown). `home_button_placement_test` title-overlap assertions were updated to the new layout.
