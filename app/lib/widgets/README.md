# LifeTwin widgets

Parts ported from the Claude Design proposal **LifeTwin Pip Screens**
(https://claude.ai/artifact/BeaMykv5bsekurR3eoMg8x, files `project/*.dc.html`).
The design is a proposal and will change. To apply a change:

- **Colors, fonts, sizes, radii, outlines, lip depths:** edit `lib/theme/lifetwin_theme.dart` only.
- **Drawings (Pip, twin, scene, badge, icons):** paste the new SVG `d`/`cx`/`r` values
  into the shape lists. `vector/shapes.dart` reads `path` (M L H V C Q Z), `circle`,
  `ellipse`, `rect` and `g` transforms. Arcs (`a`) and smooth curves (`s`, `t`) are
  refused with an error: convert them or add the command.

| Part | File | Artboard it comes from |
|---|---|---|
| Tokens + `lifeTwinTheme()` | `../theme/lifetwin_theme.dart` | canvas.json "Visual system" note; values from all artboards |
| `LipButton`, `LipStyle` (shared face + lip + press) | `lip_button.dart` | button CSS on every artboard |
| `LtPrimaryButton` | `lt_buttons.dart` | 1 Room "Talk with Pip", 4 Read-back "Yes" |
| `LtSecondaryButton` | `lt_buttons.dart` | 1 Room "See my forecast", 2 "Use the keyboard", 6 "What this means" |
| `LtBackButton` | `lt_buttons.dart` | 2–6 "Back" pill |
| `LtChoiceTile` | `lt_buttons.dart` | 6 Fortune time-span tiles (1 / 3 / 5 years) |
| `LtTextLink` | `lt_text_link.dart` | 2 "Skip this question", 3 "Use the keyboard instead" |
| `SpeechBubble` (tail down / left / none) | `speech_bubble.dart` | 2 question bubble (down), 3 listening bubble (left) |
| `Pip` (`asking`, `listening`, `pleased`) | `pip.dart` | 2 & 5 (asking), 3 (listening), 4 (pleased) |
| `Twin` | `twin.dart` | 1 Room, the waving twin |
| `ScenePaper` (`room`, `strip`) | `scene_paper.dart` | 1 Room background (room), 2 Question bottom strip (strip) |
| `MagicBallBadge` | `magic_ball_badge.dart` | 6 Fortune header "Pip beside the magic ball" |
| `LtIcon` (back, check, info, mic, keyboard, pencil, speaker, stop) | `lt_icons.dart` | 2–6 line icons; mic, keyboard, pencil from Question/Readback (arcs drawn as cubics) |
| `LtStepProgress` | `lt_progress.dart` | 2–4 "Question 3 of 11" and its 11 segments |
| `ShapeView`, `ShapePainter`, `parseSvgPath` | `vector/shapes.dart` | (renderer for the drawings) |

Used by `lib/forecast/forecast_screen.dart` (artboard 6, Fortune),
`lib/onboarding/voice_onboarding_screen.dart` (Question, Listening, Readback, QuickAnswer,
QuestionLargeText; consent screens) and `lib/health/health_screen.dart`.

Rules the parts keep: primary buttons 96 pt, secondary 78 pt, nothing a "button" under
72 pt, small controls (Back, links) at least 56 pt; selection is never shown by color
alone (thicker outline + check mark); Pip, the twin and icons keep their size when text
is enlarged, while labels wrap; with reduced motion Pip does not bob or cross-fade.
Widget tests: `test/lt_widgets_test.dart`.
