# Motion spec: the Room ↔ Onboarding swoosh

Status: prototype and Flutter sketch, 2026-10-24. The screens are V-1 Room and V-2 Onboarding at 390 × 844. The tokens are in `painted-card-direction.md` §3.

- Web prototype: `design/swoosh/swoosh.html`. Tap Talk, then Back. It has Slow-mo ×4 and Reduced motion toggles.
- Flutter sketch: `app/lib/ui/swoosh_route.dart`.

## Intent

Tapping Talk should feel as if the world turns to face you: the bear hops a step closer, the cream sheet sweeps up like a gust, and Mochi asks the question. Back is the same world exhaling: the sheet falls away, the bear hops home and gives a little jump of joy.

- **Personality:** playful but calm. It uses arcs, small overshoots (at most about 8%) and one spring. Nothing snaps or flashes.
- **The bear is the anchor.** It is visible in every frame, it never leaves the plate window, and it stays planted on the painted island. The plate pans and zooms with the same easing as the bear's base position.
- **One clock.** Every element reads milliseconds from one timeline: `render(dir, ms)` on the web, and `SwooshClock` in Flutter. That is why the choreography can be scrubbed, frozen and slowed down.

### Guardrails for older adults

| Risk | Rule used here |
|---|---|
| Disorientation | The layout doesn't move. The window, banner and bear stay on screen throughout. The longest travel (the sheet, about 400 px) follows a single curved path with no direction reversals. |
| Large rotations | The sheet leans at most 2.2°, and nothing else rotates. The mood chip keeps its static −3° tilt. |
| Fast flashes | There are no flashes, no full-screen opacity pulses, no sparkles and no blur. Pose swaps are 30–60 ms crossfades that happen inside a moving hop. |
| Unreadable text | Text never animates while you are meant to read it. Sheet rows fade in from 300 ms and are fully opaque by 680 ms. The question bubble pops in last, at 540–720 ms. |
| Lost focus | Keyboard focus moves to Back after the forward trip and to Talk after the return trip. Only the active screen's controls can be focused or tapped. |

## Shared geometry

| Thing | Room (start) | Onboarding (end) |
|---|---|---|
| Plate window | 14, 77, 362 × **615** | 14, 77, 362 × **397** (the bottom edge rides 22 px below the sheet's top) |
| Plate image (in the plate area) | −50, 0, 446 × 669 | −136, −70, 484 × 726 |
| Bear feet anchor (in the plate area) | 173.5, 370.4 · scale 1 | 105.8, 324.2 · scale 0.793 |
| Sheet | off-screen at offset (−44, 400) | 14, 452, 362 × 354 |
| Sheet entry path | quadratic bezier P0 (−44, 400) → P1 (36, 70) → P2 (0, 0) | |
| Sheet exit path | P0 (0, 0) → P1 (−26, −30) → P2 (64, 430) | |

All sprites share one pixel scale (290.2 pt per 512 px of sprite canvas), and their feet sit at the canvas's bottom centre. Swapping poses therefore never changes the bear's size.

## Easing palette

| Name | Value | Use |
|---|---|---|
| out | cubic-bezier(0, 0, .2, 1) | entrances, landings |
| in | cubic-bezier(.4, 0, 1, 1) | exits |
| inOut | cubic-bezier(.45, 0, .25, 1) | on-screen travel (bear base, plate) |
| sine | ease-in-out sine | tint crossfade |
| back | cubic-bezier(.34, 1.4, .64, 1) | pops (bubbles, Back, Talk), about 8% overshoot |
| backSoft | cubic-bezier(.3, 1.22, .6, 1) | Room bar returning |
| spring | damped spring, ζ 0.72, ω 10 per interval | sheet entry, about 4% overshoot |
| fall | t^2.2 | sheet falling away |
| gravity | parabola 4u(1−u) on linear time | every hop, so the arcs stay physical |

## Timeline: Room → Onboarding (tap Talk), 720 ms

| ms | Element | Property | Easing |
|---|---|---|---|
| 0–90 | Talk button | scale 1 → 0.94 (press, held) | out |
| 20–140 | "Hi! Want to chat?" bubble | opacity 1 → 0, scale 1 → 0.6 toward its tail | in |
| 20–140 | "Feeling cozy" chip | opacity 1 → 0, y +16 | in |
| 60–240 | Room action bar | y +36 | in |
| 90–220 | Room action bar | opacity 1 → 0 (the rising sheet covers it) | in |
| 80–560 | Background tint | lavender → mint | sine |
| 60–140 | Bear | anticipation squash to (1.05, 0.93) | out |
| 120–620 | **Sheet** | offset along the entry bezier; lean 2.2° → 0 | spring |
| 120–620 | Plate window | bottom edge = sheet top + 22 (height 615 → 397, about 3 px overshoot) | follows the sheet |
| 140–560 | **Bear** | feet anchor and scale Room → Onboarding | inOut |
| 140–560 | Bear | hop of 40 px, peaking at 350 ms | gravity |
| 140–220 | Bear | take-off stretch to (0.97, 1.05) | out |
| 140–560 | Plate image, glow, grass tufts | Room framing → Onboarding framing (synced with the bear) | inOut |
| 140–560 | Ground shadow | follows the feet on the ground; scale and opacity dip with the hop | follows the hop |
| 170–390 | Wind line 1 (long arc, 30 → 360 px) | drawn left to right, then its tail retracts; rides 16 px above the sheet's top | out / in |
| 200–420 | Wind line 2 | the same, 30 px above | out / in |
| 230–540 | Wind line 3 | the same, 42 px above | out / in |
| 325–375 | Bear | pose `stand` → `wave` (crossfade at the top of the hop) | inOut |
| 300–680 | Sheet rows (dots, Hold to talk, Type instead, two chips) | y +16 → 0 over 240 ms; opacity over 140 ms; 35 ms stagger | out |
| 560–620 | Bear | landing squash to (1.07, 0.92) | out |
| 620–720 | Bear | settles to (1, 1) with a slight overshoot | back |
| 460–660 | Back button | scale 0.6 → 1; opacity over the first 120 ms | back |
| 540–720 | **"How tall are you?" bubble** | scale 0.4 → 1 from its tail; opacity over the first 90 ms | back |

## Timeline: Onboarding → Room (Back or Done), 740 ms

The return trip has its own character, with a lift, a fall and a celebratory jump. It is not the forward trip played in reverse.

| ms | Element | Property | Easing |
|---|---|---|---|
| 0–80 | Back button | scale 1 → 0.92 (press) | out |
| 60–200 | Back button | opacity 1 → 0 | in |
| 0–150 | Question bubble | opacity 1 → 0, scale 1 → 0.6 toward its tail | in |
| 60–520 | Background tint | mint → lavender | sine |
| 40–140 | Sheet | anticipation lift of −10 px | out |
| 140–460 | **Sheet** | offset along the exit bezier (down and to the right, off screen); lean 0 → 2.2° | fall |
| 140–460 | Plate window | bottom edge follows the sheet back down to 615 | follows the sheet |
| 200–530 | Wind streaks (3, 40–62 px) | short vertical streaks trailing above the falling sheet; soft edge; clipped above the bar | out / in |
| 40–100 | Bear | pose `wave` → `stand` | inOut |
| 40–110 | Bear | crouch to (1.05, 0.93) | out |
| 110–420 | **Bear** | feet anchor and scale Onboarding → Room | inOut |
| 110–420 | Bear | hop of 48 px | gravity |
| 110–420 | Plate image, glow, tufts | Onboarding framing → Room framing | inOut |
| 420–470 | Bear | touch-down squash to (1.06, 0.92) | out |
| 455–485 | Bear | pose `stand` → `jump` | inOut |
| 470–630 | Bear | small `bear_jump` of 22 px, with a stretch to (0.97, 1.04) | gravity |
| 628–656 | Bear | pose `jump` → `stand` | inOut |
| 630–740 | Bear | final squash to (1.05, 0.94), then settles | out → back |
| 300–560 | Room action bar | y +120 → 0 (rises under the departing sheet); opacity over the first 120 ms | backSoft |
| 380–560 | Talk button | scale 0.9 → 1 | back |
| 400–560, 430–590 | Customize, then Fortune | y +10 → 0; opacity | out |
| 520–700 | "Feeling cozy" chip | opacity 0 → 1, y +16 → 0 | out |
| 580–740 | **"Hi! Want to chat?" bubble** | scale 0.4 → 1 from its tail; opacity over the first 90 ms | back |

## Reduced motion

This applies when `prefers-reduced-motion: reduce` is set on the web (or the prototype's toggle is on), and when `MediaQuery.disableAnimationsOf(context)` is true in Flutter.

- **200 ms crossfade, with no travel, hops, squash, wind or pose swaps.** The old screen dissolves over the new one with `out` easing.
- Web: the prototype snapshots the old screen, sets the new screen to its rest state underneath, and fades the snapshot out.
- Flutter: `SwooshRoute(reducedMotion: true)` sets 200 ms durations and wraps the page in a `FadeTransition`. `SwooshStage` renders `SwooshFrame.rest()`. `HeroMode(enabled: false)` turns off the bear's flight. On the Room page, only the background tint follows the route.
- The bear is visible throughout, because it exists in both screens.

## Mapping to the Dart sketch

| Spec / prototype | `swoosh_route.dart` |
|---|---|
| One clock, `render(dir, ms)` | `SwooshClock.of(routeAnimation)`: forward ms = value × 720; back ms = (1 − value) × 740 when the status is `reverse` |
| `seg(ms, start, dur, ease)` | `SwooshClock.seg(start, dur, curve)` |
| Keyframe `track()` | `_track<T>()` with `_Key` lists (`_forwardSquash`, `_homewardSquash`) |
| Easing palette | `SwooshCurves` (`Cubic`s, `SwooshSpringCurve`, `SwooshPowerCurve`) |
| Route | `SwooshRoute` (non-opaque `PageRouteBuilder`; 720 / 740 ms, or 200 ms when reduced) and `SwooshRoute.push` |
| Sheet on its bezier | `SwooshStage` owns a `CurvedAnimation`: forward `Interval(120/720, 620/720, spring)`, reverse `Interval(1−460/740, 1−140/740, FlippedCurve(fall))`. `quadBezier()` and `SwooshSheetTransform` (translate, then rotate about the top centre) |
| Window glued to the sheet | `SwooshFrame.windowHeight` = clamp(397 + sheet dy, 385, 615) |
| Plate, glow, shadow, tufts | `SwooshFrame.framing`, `plateRect`, `feet`, `shadowScale` |
| Bear travel and hop | `SwooshBearHero`, with `createRectTween` set to `SwooshHopRectTween`. The tween inverts Flutter's `fastOutSlowIn` hero curve to recover elapsed time, then applies inOut travel and the gravity hop |
| Pose swap and squash | `swooshBearShuttle` (`flightShuttleBuilder`): `_forwardPoses` / `_homewardPoses` plus the squash tracks, rendered by `SwooshBearSprite` (three stacked sprites with opacity) |
| Background tint | `SwooshTint` (`RadialGradient.lerp`, lavender → mint), driven by `SwooshRoomFrame.tint` from the Room route's `secondaryAnimation` |
| Room exits and returns | `SwooshRoomStage`, which reads `secondaryAnimation`, and `SwooshRoomFrame` |
| Wind lines | `SwooshWindPainter` (a `CustomPainter`; `PathMetric.extractPath` gives the drawn and retracting slice) |
| Reduced motion | `MediaQuery.disableAnimationsOf`, `FadeTransition`, `SwooshFrame.rest()`, `HeroMode` |

### Flutter layering (why the hand-off frames exist)

The Onboarding route draws above Room, and it is transparent. So:

1. The **tint lives on the Room page**, which is the bottom layer. Otherwise the mint tint would wash over Room's action bar while the bar rises on the way back.
2. Onboarding's **plate window appears at 140 ms forward**. By then Room's bubble and chip have left, and both windows are still identical. It **disappears at 430 ms back**, after the window is back to 615 and the plate is back in Room framing, so that Room's chip and bubble can return. Both switches are invisible.
3. The **bear Hero shuttle** flies in the navigator overlay, above both pages. That is harmless, because the bear never overlaps the sheet or a bubble during its flight.
4. The return trip's **wind streaks are clipped above y = 668**, so they never draw over Room's bar.

## Verification

- Prototype frames (headless Chrome, 390 × 844, frozen through the local test hook `#t=<0..1>&dir=fwd|back[&rm=1]`) are in `design/swoosh/frames/`: `fwd-000/025/050/075/100.png`, `back-000/025/050/075/100.png` and `rm-fwd-050.png`. The test hook is inert unless the hash is set.
- I ran a click-through test in headless Chrome on the forward, back, reduced-motion and slow-mo paths. The end states and focus hand-off were correct, with no script errors.
- The Dart sketch passes `flutter analyze` with `flutter_lints` in a fresh package (Flutter 3.47.8). A widget smoke test runs the push/pop round trip with hero flights and the reduced-motion path, and passes.

## Known limits

- In the sketch, the Hero's rect timing depends on Flutter's internal hero curve (`fastOutSlowIn`, with begin = departing hero). If a future Flutter changes `heroes.dart`, `_uncurveHero` must change with it.
- The route does not handle a user-driven back swipe, which would make the status ambiguous. Keep `PageRouteBuilder`'s default (no swipe), or add a gesture that scrubs `SwooshClock`.
- During the 50 ms pose crossfade at the top of the hop, the two poses overlap faintly. At normal speed this is not visible, but it shows in slow-mo.
- The ground shadow uses `filter: blur` on the web. Flutter must use a soft radial gradient instead, because the painted-card direction says no blur effects.
