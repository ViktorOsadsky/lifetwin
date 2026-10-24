/// The "swoosh" between Room (V-1) and Onboarding (V-2).
///
/// Implementation sketch in plain Flutter (no packages). It mirrors the web
/// prototype `design/swoosh/swoosh.html` beat for beat; the timeline lives in
/// `docs/design/motion-swoosh.md`. All numbers are logical pixels on the
/// 390 × 844 artboards and milliseconds on one shared clock.
///
/// How the pieces fit:
///
/// * [SwooshRoute] is a [PageRouteBuilder] that is see-through while it moves. It does not move the
///   page itself: each page reads the route clock and moves its own parts, so
///   Room and Onboarding feel like one world rather than two pages.
/// * [SwooshClock] turns a route animation (0..1, forward or reverse) into
///   "milliseconds since the transition started" for the active direction.
///   Forward and back have different choreography, not a mirrored one.
/// * [SwooshStage] (Onboarding page) and [SwooshRoomStage] (Room page) hand a
///   ready-made frame of values to a builder.
/// * [SwooshBearHero] is the anchor: a [Hero] whose [Hero.flightShuttleBuilder]
///   swaps the pose mid-flight and squashes on landing, and whose
///   [Hero.createRectTween] adds the hop arc.
/// * The sheet rides a [CurvedAnimation] along a quadratic bezier
///   ([quadBezier]) through a [Transform]. The plate window's bottom edge is
///   glued to the sheet's top edge, so the sheet pushes the window up.
/// * Reduced motion ([MediaQuery.disableAnimationsOf]): a 200 ms fade, no
///   travel, hero flights off.
///
/// Hand-off frames. The Onboarding route draws above Room, so Room's floating
/// bits (bubble, mood chip) must finish leaving before Onboarding's opaque
/// window covers them. Onboarding's window therefore appears at 140 ms
/// forward (when it is pixel-identical to Room's window underneath) and
/// disappears at 430 ms back (when it is pixel-identical again). Both
/// switches are invisible.
library;

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Timing and curves
// ---------------------------------------------------------------------------

/// Durations of the three variants.
abstract final class SwooshTiming {
  static const double forwardMs = 720;
  static const double reverseMs = 740;
  static const double reducedMs = 200;

  static const Duration forward = Duration(milliseconds: 720);
  static const Duration reverse = Duration(milliseconds: 740);
  static const Duration reduced = Duration(milliseconds: 200);

  /// Forward: Onboarding's window takes over from Room's at this time.
  static const double windowInMs = 140;

  /// Back: Onboarding's window hands back to Room's at this time.
  static const double windowOutMs = 430;
}

/// Critically-underdamped spring (damping ratio 0.72, omega 10 per unit of
/// interval time): about 4% overshoot and settled before the interval ends.
/// Same formula as `E.spring` in the prototype.
class SwooshSpringCurve extends Curve {
  const SwooshSpringCurve({this.damping = 0.72, this.omega = 10.0});

  final double damping;
  final double omega;

  @override
  double transformInternal(double t) {
    final double wd = omega * math.sqrt(1 - damping * damping);
    return 1 -
        math.exp(-damping * omega * t) *
            (math.cos(wd * t) + (damping * omega / wd) * math.sin(wd * t));
  }
}

/// `t^p`, used for the sheet falling away (p = 2.2).
class SwooshPowerCurve extends Curve {
  const SwooshPowerCurve(this.power);

  final double power;

  @override
  double transformInternal(double t) => math.pow(t, power).toDouble();
}

/// The motion palette. Entrances decelerate, exits accelerate, travel eases
/// both ends, pops overshoot a little. No linear spatial motion anywhere.
abstract final class SwooshCurves {
  static const Curve out = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Curve inn = Cubic(0.4, 0.0, 1.0, 1.0);
  static const Curve inOut = Cubic(0.45, 0.0, 0.25, 1.0);
  static const Curve back = Cubic(0.34, 1.4, 0.64, 1.0);
  static const Curve backSoft = Cubic(0.3, 1.22, 0.6, 1.0);
  static const Curve sine = Curves.easeInOutSine;
  static const Curve spring = SwooshSpringCurve();
  static const Curve fall = SwooshPowerCurve(2.2);
}

/// Quadratic bezier point at [t] (t may slightly exceed 1 during a spring
/// overshoot; the curve simply continues past [p2]).
Offset quadBezier(Offset p0, Offset p1, Offset p2, double t) {
  final double u = 1 - t;
  return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t);
}

double _parabola(double u) => 4 * u * (1 - u);

/// A keyframe for [_track]: reach [value] at [ms], easing in with [curve].
class _Key<T> {
  const _Key(this.ms, this.value, [this.curve = Curves.linear]);
  final double ms;
  final T value;
  final Curve curve;
}

/// Piecewise keyframe track, the Dart twin of `track()` in the prototype.
T _track<T>(double ms, List<_Key<T>> keys, T Function(T a, T b, double t) lerp) {
  if (ms <= keys.first.ms) return keys.first.value;
  for (int i = 1; i < keys.length; i++) {
    final _Key<T> k1 = keys[i];
    if (ms <= k1.ms) {
      final _Key<T> k0 = keys[i - 1];
      return lerp(k0.value, k1.value, k1.curve.transform((ms - k0.ms) / (k1.ms - k0.ms)));
    }
  }
  return keys.last.value;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
Offset _lerpOffset(Offset a, Offset b, double t) => Offset.lerp(a, b, t)!;

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------

/// Milliseconds since the transition started, in the active direction.
///
/// Push runs the route animation 0 → 1 over 720 ms; pop runs it 1 → 0 over
/// 740 ms. Reading `status == reverse` tells the two apart, so the back trip
/// gets its own choreography instead of the forward one played backwards.
/// (A user-driven back swipe would need its own handling; this route has none.)
@immutable
class SwooshClock {
  const SwooshClock._(this.popping, this.ms);

  factory SwooshClock.of(Animation<double> routeAnimation) {
    final double v = routeAnimation.value;
    if (routeAnimation.status == AnimationStatus.reverse) {
      return SwooshClock._(true, (1 - v) * SwooshTiming.reverseMs);
    }
    return SwooshClock._(false, v * SwooshTiming.forwardMs);
  }

  /// True while Onboarding → Room is playing.
  final bool popping;

  /// Elapsed milliseconds within the active direction.
  final double ms;

  /// Eased 0..1 progress of a beat that starts at [startMs] and lasts [durMs].
  double seg(double startMs, double durMs, [Curve curve = Curves.linear]) =>
      curve.transform(((ms - startMs) / durMs).clamp(0.0, 1.0));

  /// Linear 0..1 progress (for gravity arcs, which must stay parabolic).
  double lin(double startMs, double durMs) => ((ms - startMs) / durMs).clamp(0.0, 1.0);
}

// ---------------------------------------------------------------------------
// Geometry from V-1 / V-2
// ---------------------------------------------------------------------------

abstract final class SwooshGeometry {
  // Plate window.
  static const Rect windowRoom = Rect.fromLTWH(14, 77, 362, 615);
  static const double windowOnbHeight = 397;
  static const double windowInset = 7.5; // 1.5 line + 6 cream rim

  // Plate image inside the window (Room framing → Onboarding framing).
  static const Rect plateRoom = Rect.fromLTWH(-50, 0, 446, 669);
  static const Rect plateOnb = Rect.fromLTWH(-136, -70, 484, 726);

  // Bear feet anchor inside the plate area, and its scale.
  static const Offset feetRoom = Offset(173.5, 370.4);
  static const Offset feetOnb = Offset(105.8, 324.2);
  static const double bearOnbScale = 0.793;

  /// Sprite box at Room scale. The 512 px sprite canvas maps to 290.2 pt;
  /// the feet sit at 488 / 512 of the box height (see [feetAlignment]).
  static const double bearBox = 290.2;
  static const Alignment feetAlignment = Alignment(0, 0.906);

  // Sheet: resting rect, and the two bezier paths (offsets from rest).
  static const Rect sheet = Rect.fromLTWH(14, 452, 362, 354);
  static const Offset enterP0 = Offset(-44, 400);
  static const Offset enterP1 = Offset(36, 70);
  static const Offset enterP2 = Offset.zero;
  static const Offset exitP0 = Offset.zero;
  static const Offset exitP1 = Offset(-26, -30);
  static const Offset exitP2 = Offset(64, 430);

  /// Room's action bar top: the back-trip wind lines are clipped above it.
  static const double barTop = 668;

  /// Hero rect for the bear at framing [b] (0 Room, 1 Onboarding), in the
  /// coordinates of the 390 × 844 artboard.
  static Rect bearRect(double b) {
    final Offset feet = Offset.lerp(feetRoom, feetOnb, b)! +
        Offset(windowRoom.left + windowInset, windowRoom.top + windowInset);
    final double size = bearBox * _lerp(1, bearOnbScale, b);
    return Rect.fromLTWH(feet.dx - size / 2, feet.dy - size * 0.953, size, size);
  }
}

// ---------------------------------------------------------------------------
// Route
// ---------------------------------------------------------------------------

/// Non-opaque route that lets both pages choreograph themselves.
///
/// Use [SwooshRoute.push] so reduced motion is picked up at push time.
class SwooshRoute<T> extends PageRouteBuilder<T> {
  SwooshRoute({required WidgetBuilder builder, this.reducedMotion = false, super.settings})
      : super(
          // Opaque once it has arrived (a TransitionRoute is see-through only while it
          // moves), so the Room under it is neither tapped nor read by VoiceOver.
          opaque: true,
          barrierColor: null,
          maintainState: true,
          pageBuilder: (BuildContext context, Animation<double> a, Animation<double> s) =>
              builder(context),
          transitionsBuilder: (BuildContext context, Animation<double> animation,
              Animation<double> secondary, Widget child) {
            if (!reducedMotion) return child; // the pages move their own parts
            // Reduced motion: a 200 ms crossfade, nothing travels.
            return FadeTransition(
              opacity: CurvedAnimation(parent: animation, curve: SwooshCurves.out),
              child: child,
            );
          },
        );

  /// When true: 200 ms fade, no travel, no hero flight.
  final bool reducedMotion;

  @override
  Duration get transitionDuration =>
      reducedMotion ? SwooshTiming.reduced : SwooshTiming.forward;

  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? SwooshTiming.reduced : SwooshTiming.reverse;

  /// Pushes [page] with the swoosh, honouring the platform's reduce-motion
  /// setting (`MediaQuery.disableAnimationsOf`).
  static Future<T?> push<T>(BuildContext context, WidgetBuilder page) {
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    return Navigator.of(context).push<T>(SwooshRoute<T>(builder: page, reducedMotion: reduced));
  }
}

// ---------------------------------------------------------------------------
// Onboarding side
// ---------------------------------------------------------------------------

/// One wind line: a path plus the visible slice of it (0..1 of its length).
@immutable
class SwooshWindStroke {
  const SwooshWindStroke(this.path, this.from, this.to, this.width, this.edgeAlpha);
  final Path path;
  final double from;
  final double to;
  final double width;
  final double edgeAlpha;
}

/// Everything the Onboarding page needs for one frame.
@immutable
class SwooshFrame {
  const SwooshFrame({
    required this.framing,
    required this.hop,
    required this.sheetOffset,
    required this.sheetRotation,
    required this.windowHeight,
    required this.windowVisible,
    required this.backScale,
    required this.backOpacity,
    required this.bubbleScale,
    required this.bubbleOpacity,
    required this.contentOffsetY,
    required this.contentOpacity,
    required this.wind,
    required this.windClipBottom,
  });

  /// Onboarding at rest (also the reduced-motion frame).
  factory SwooshFrame.rest() => const SwooshFrame(
        framing: 1,
        hop: 0,
        sheetOffset: Offset.zero,
        sheetRotation: 0,
        windowHeight: SwooshGeometry.windowOnbHeight,
        windowVisible: true,
        backScale: 1,
        backOpacity: 1,
        bubbleScale: 1,
        bubbleOpacity: 1,
        contentOffsetY: <double>[0, 0, 0, 0, 0],
        contentOpacity: <double>[1, 1, 1, 1, 1],
        wind: <SwooshWindStroke>[],
        windClipBottom: double.infinity,
      );

  /// Computes the frame. [sheet] is the [CurvedAnimation] owned by
  /// [SwooshStage]: forward it is the spring over 120–620 ms, back it is the
  /// fall over 140–460 ms (see [SwooshStage]).
  factory SwooshFrame.compute(Animation<double> route, Animation<double> sheet) {
    final SwooshClock c = SwooshClock.of(route);
    return c.popping ? _back(c, sheet.value) : _forward(c, sheet.value);
  }

  static SwooshFrame _forward(SwooshClock c, double sheetValue) {
    // Sheet: spring along the entry bezier, leaning into the motion (≤ 2.2°).
    final Offset off = quadBezier(
        SwooshGeometry.enterP0, SwooshGeometry.enterP1, SwooshGeometry.enterP2, sheetValue);
    final double rot = 2.2 * (1 - sheetValue) * math.pi / 180;

    // Wind: a left-to-right gust riding just above the sheet's leading edge.
    final double top = SwooshGeometry.sheet.top + off.dy;
    final List<SwooshWindStroke> wind = <SwooshWindStroke>[];
    const List<List<double>> lines = <List<double>>[
      <double>[30, 360, 16, 22, 170, 3.8],
      <double>[74, 300, 30, 15, 200, 2.8],
      <double>[122, 252, 42, 9, 230, 2.4],
    ];
    for (final List<double> l in lines) {
      final double y = top - l[2];
      final Path p = Path()
        ..moveTo(l[0] + off.dx, y + 4)
        ..quadraticBezierTo((l[0] + l[1]) / 2 + off.dx, y - l[3], l[1] + off.dx, y - 2);
      final double head = c.seg(l[4], 200, SwooshCurves.out);
      final double tail = c.seg(l[4] + 90, 220, SwooshCurves.inn);
      if (head > tail) wind.add(SwooshWindStroke(p, tail, head, l[5], 1));
    }

    final double u = c.lin(140, 420);
    return SwooshFrame(
      framing: c.seg(140, 420, SwooshCurves.inOut),
      hop: 40 * _parabola(u),
      sheetOffset: off,
      sheetRotation: rot,
      windowHeight: _windowFor(off),
      windowVisible: c.ms >= SwooshTiming.windowInMs,
      backScale: _lerp(0.6, 1, c.seg(460, 200, SwooshCurves.back)),
      backOpacity: c.seg(460, 120),
      bubbleScale: _lerp(0.4, 1, c.seg(540, 180, SwooshCurves.back)),
      bubbleOpacity: c.seg(540, 90),
      // 35 ms micro-cascade: dots, Hold to talk, Type instead, two chips.
      contentOffsetY: List<double>.generate(
          5, (int i) => 16 * (1 - c.seg(300 + 35.0 * i, 240, SwooshCurves.out))),
      contentOpacity:
          List<double>.generate(5, (int i) => c.seg(300 + 35.0 * i, 140, SwooshCurves.out)),
      wind: wind,
      windClipBottom: double.infinity,
    );
  }

  static SwooshFrame _back(SwooshClock c, double sheetValue) {
    // Sheet: 10 px anticipation lift, then falls away down-right.
    final double q = 1 - sheetValue; // 0 at rest → 1 gone
    final double lift = -10 * c.seg(40, 100, SwooshCurves.out);
    final Offset off = quadBezier(
            SwooshGeometry.exitP0, SwooshGeometry.exitP1, SwooshGeometry.exitP2, q) +
        Offset(0, lift * (1 - q));
    final double rot = 2.2 * SwooshCurves.inn.transform(q) * math.pi / 180;

    // Wind: short streaks trailing above the falling sheet.
    final double top = SwooshGeometry.sheet.top + off.dy;
    final List<SwooshWindStroke> wind = <SwooshWindStroke>[];
    const List<List<double>> streaks = <List<double>>[
      <double>[86, 46, 200, 3.8],
      <double>[196, 62, 225, 2.8],
      <double>[300, 40, 250, 2.4],
    ];
    for (final List<double> s in streaks) {
      final double x = s[0] + off.dx, y0 = top - 10, len = s[1];
      final Path p = Path()
        ..moveTo(x, y0)
        ..quadraticBezierTo(x - 7, y0 - len / 2, x - 3, y0 - len);
      final double vis =
          c.seg(s[2], 160, SwooshCurves.out) * (1 - c.seg(s[2] + 80, 200, SwooshCurves.inn));
      if (vis > 0.002) wind.add(SwooshWindStroke(p, 0, vis, s[3], 0.35));
    }

    final double u = c.lin(110, 310), v = c.lin(470, 160);
    final double backPress = _track<double>(c.ms, const <_Key<double>>[
      _Key<double>(0, 1),
      _Key<double>(80, 0.92, SwooshCurves.out),
    ], _lerp);
    final double bubbleOut = c.seg(0, 150, SwooshCurves.inn);
    return SwooshFrame(
      framing: 1 - c.seg(110, 310, SwooshCurves.inOut),
      hop: 48 * _parabola(u) + 22 * _parabola(v),
      sheetOffset: off,
      sheetRotation: rot,
      windowHeight: _windowFor(off),
      windowVisible: c.ms < SwooshTiming.windowOutMs,
      backScale: backPress,
      backOpacity: 1 - c.seg(60, 140, SwooshCurves.inn),
      bubbleScale: _lerp(1, 0.6, bubbleOut),
      bubbleOpacity: 1 - bubbleOut,
      contentOffsetY: const <double>[0, 0, 0, 0, 0],
      contentOpacity: const <double>[1, 1, 1, 1, 1],
      wind: wind,
      windClipBottom: SwooshGeometry.barTop,
    );
  }

  /// The window's bottom edge rides 22 pt below the sheet's top edge (the
  /// overlap in V-2), clamped between the two resting heights.
  static double _windowFor(Offset sheetOffset) => (SwooshGeometry.windowOnbHeight + sheetOffset.dy)
      .clamp(SwooshGeometry.windowOnbHeight - 12, SwooshGeometry.windowRoom.height);

  /// 0 = Room framing, 1 = Onboarding framing: drives plate pan/zoom, bear
  /// base position and scale, glow, shadow and grass tufts together so the
  /// bear stays planted on the painted island.
  final double framing;

  /// Bear height above the ground (pt). The ground shadow shrinks with it.
  final double hop;
  final Offset sheetOffset;
  final double sheetRotation;
  final double windowHeight;
  final bool windowVisible;
  final double backScale;
  final double backOpacity;
  final double bubbleScale;
  final double bubbleOpacity;
  final List<double> contentOffsetY;
  final List<double> contentOpacity;
  final List<SwooshWindStroke> wind;
  final double windClipBottom;

  /// Plate image rect inside the window's plate area.
  Rect get plateRect => Rect.lerp(SwooshGeometry.plateRoom, SwooshGeometry.plateOnb, framing)!;

  /// Feet anchor inside the plate area (ground level, without the hop).
  Offset get feet => Offset.lerp(SwooshGeometry.feetRoom, SwooshGeometry.feetOnb, framing)!;

  /// Ground-shadow scale: smaller and lighter while the bear is airborne.
  double get shadowScale => _lerp(1, 0.86, framing) * (1 - 0.38 * (hop / 48).clamp(0.0, 1.0));
}

/// Builds the Onboarding page from the route clock.
///
/// Owns the sheet's [CurvedAnimation]:
/// * forward: `Interval(120/720, 620/720)` with [SwooshSpringCurve];
/// * reverse: `Interval(1 − 460/740, 1 − 140/740)` with the fall curve
///   flipped, because a reversing [CurvedAnimation] applies `reverseCurve`
///   to the parent's value as it runs 1 → 0.
class SwooshStage extends StatefulWidget {
  const SwooshStage({super.key, required this.builder});

  final Widget Function(BuildContext context, SwooshFrame frame) builder;

  @override
  State<SwooshStage> createState() => _SwooshStageState();
}

class _SwooshStageState extends State<SwooshStage> {
  Animation<double>? _route;
  CurvedAnimation? _sheet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final Animation<double> route = ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    if (!identical(route, _route)) {
      _sheet?.dispose();
      _route = route;
      _sheet = CurvedAnimation(
        parent: route,
        curve: const Interval(120 / 720, 620 / 720, curve: SwooshCurves.spring),
        reverseCurve: const Interval(1 - 460 / 740, 1 - 140 / 740,
            curve: FlippedCurve(SwooshCurves.fall)),
      );
    }
  }

  @override
  void dispose() {
    _sheet?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.builder(context, SwooshFrame.rest());
    }
    return AnimatedBuilder(
      animation: _route!,
      builder: (BuildContext context, Widget? _) =>
          widget.builder(context, SwooshFrame.compute(_route!, _sheet!)),
    );
  }
}

/// Positions the sheet: translate along the bezier, then a small lean about
/// its top centre. Wrap the cream sheet panel in this.
class SwooshSheetTransform extends StatelessWidget {
  const SwooshSheetTransform({super.key, required this.frame, required this.child});

  final SwooshFrame frame;
  final Widget child;

  @override
  Widget build(BuildContext context) => Transform.translate(
        offset: frame.sheetOffset,
        child: Transform.rotate(
          angle: frame.sheetRotation,
          alignment: Alignment.topCenter,
          child: child,
        ),
      );
}

/// Paints the wind lines: white core with a soft line-colour edge.
class SwooshWindPainter extends CustomPainter {
  SwooshWindPainter(this.strokes, this.clipBottom);

  final List<SwooshWindStroke> strokes;
  final double clipBottom;

  static const Color _edge = Color(0xFFA88B7D);

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, math.min(size.height, clipBottom)));
    for (final SwooshWindStroke s in strokes) {
      for (final PathMetric m in s.path.computeMetrics()) {
        final Path part = m.extractPath(m.length * s.from, m.length * s.to);
        canvas.drawPath(
            part,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = s.width + 2.2
              ..color = _edge.withValues(alpha: 0.55 * s.edgeAlpha * 0.95));
        canvas.drawPath(
            part,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = s.width
              ..color = Colors.white.withValues(alpha: 0.95));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SwooshWindPainter old) => true; // driven every frame
}

// ---------------------------------------------------------------------------
// Room side
// ---------------------------------------------------------------------------

/// Everything the Room page needs for one frame. Driven by the Room route's
/// `secondaryAnimation` (the Onboarding route's animation as seen from below).
@immutable
class SwooshRoomFrame {
  const SwooshRoomFrame({
    required this.tint,
    required this.bubbleScale,
    required this.bubbleOpacity,
    required this.chipOffsetY,
    required this.chipOpacity,
    required this.talkScale,
    required this.barOffsetY,
    required this.barOpacity,
    required this.sideOffsetY,
    required this.sideOpacity,
  });

  factory SwooshRoomFrame.compute(Animation<double> secondary, {required bool reduced}) {
    final SwooshClock c = SwooshClock.of(secondary);
    if (reduced) {
      // Only the background crossfades; Onboarding fades in over the rest.
      return SwooshRoomFrame._rest(tint: secondary.value);
    }
    if (!c.popping) {
      final double out = c.seg(20, 120, SwooshCurves.inn); // all gone by 140 ms
      return SwooshRoomFrame(
        tint: c.seg(80, 480, SwooshCurves.sine),
        bubbleScale: _lerp(1, 0.6, out),
        bubbleOpacity: 1 - out,
        chipOffsetY: 16 * out,
        chipOpacity: 1 - out,
        talkScale: _track<double>(c.ms, const <_Key<double>>[
          _Key<double>(0, 1),
          _Key<double>(90, 0.94, SwooshCurves.out),
        ], _lerp),
        barOffsetY: 36 * c.seg(60, 180, SwooshCurves.inn),
        barOpacity: 1 - c.seg(90, 130, SwooshCurves.inn),
        sideOffsetY: const <double>[0, 0],
        sideOpacity: const <double>[1, 1],
      );
    }
    final double chip = c.seg(520, 180, SwooshCurves.out);
    return SwooshRoomFrame(
      tint: 1 - c.seg(60, 460, SwooshCurves.sine),
      bubbleScale: _lerp(0.4, 1, c.seg(580, 160, SwooshCurves.back)), // pops in last
      bubbleOpacity: c.seg(580, 90),
      chipOffsetY: 16 * (1 - chip),
      chipOpacity: chip,
      talkScale: _lerp(0.9, 1, c.seg(380, 180, SwooshCurves.back)),
      barOffsetY: 120 * (1 - c.seg(300, 260, SwooshCurves.backSoft)),
      barOpacity: c.seg(300, 120, SwooshCurves.out),
      sideOffsetY: <double>[
        10 * (1 - c.seg(400, 160, SwooshCurves.out)),
        10 * (1 - c.seg(430, 160, SwooshCurves.out)),
      ],
      sideOpacity: <double>[c.seg(400, 120, SwooshCurves.out), c.seg(430, 120, SwooshCurves.out)],
    );
  }

  factory SwooshRoomFrame._rest({double tint = 0}) => SwooshRoomFrame(
        tint: tint,
        bubbleScale: 1,
        bubbleOpacity: 1,
        chipOffsetY: 0,
        chipOpacity: 1,
        talkScale: 1,
        barOffsetY: 0,
        barOpacity: 1,
        sideOffsetY: const <double>[0, 0],
        sideOpacity: const <double>[1, 1],
      );

  /// 0 = lavender (Room), 1 = mint (Onboarding).
  final double tint;
  final double bubbleScale;
  final double bubbleOpacity;
  final double chipOffsetY;
  final double chipOpacity;
  final double talkScale;
  final double barOffsetY;
  final double barOpacity;
  final List<double> sideOffsetY;
  final List<double> sideOpacity;
}

/// Builds the Room page from its route's `secondaryAnimation`.
class SwooshRoomStage extends StatelessWidget {
  const SwooshRoomStage({super.key, required this.builder});

  final Widget Function(BuildContext context, SwooshRoomFrame frame) builder;

  @override
  Widget build(BuildContext context) {
    final Animation<double> secondary =
        ModalRoute.of(context)?.secondaryAnimation ?? kAlwaysDismissedAnimation;
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: secondary,
      builder: (BuildContext context, Widget? _) =>
          builder(context, SwooshRoomFrame.compute(secondary, reduced: reduced)),
    );
  }
}

/// The mode tint behind every panel. The tween lives on the Room page (the
/// bottom layer) so the Onboarding route can stay transparent and never
/// washes over Room's rising action bar.
class SwooshTint extends StatelessWidget {
  const SwooshTint({super.key, required this.t});

  /// 0 = lavender, 1 = mint.
  final double t;

  static const RadialGradient lavender = RadialGradient(
    center: Alignment(0, -0.64),
    radius: 1.4,
    colors: <Color>[Color(0xFFF0ECFD), Color(0xFFE6E0FA)],
    stops: <double>[0, 0.72],
  );
  static const RadialGradient mint = RadialGradient(
    center: Alignment(0, -0.64),
    radius: 1.4,
    colors: <Color>[Color(0xFFE3F5EC), Color(0xFFD3EEE2)],
    stops: <double>[0, 0.72],
  );

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: RadialGradient.lerp(lavender, mint, t)),
        child: const SizedBox.expand(),
      );
}

// ---------------------------------------------------------------------------
// Bear hero
// ---------------------------------------------------------------------------

/// Bear sprite paths (same scheme as `twinAsset()` in `twin_assets.dart`).
abstract final class SwooshBearAssets {
  static const String stand = 'assets/twin/bear/pose/stand.png';
  static const String wave = 'assets/twin/bear/pose/wave.png';
  static const String jump = 'assets/twin/bear/pose/jump.png';
}

/// The bear as a shared element. Put one in each page, inside the plate
/// window, sized by [SwooshGeometry.bearRect] (framing 0 in Room, 1 in
/// Onboarding).
///
/// [resting] is the pose shown when not flying: `stand` in Room, `wave` in
/// Onboarding. Hero flights are turned off under reduced motion.
class SwooshBearHero extends StatelessWidget {
  const SwooshBearHero({super.key, required this.resting, required this.isRoom});

  final String resting;

  /// Which page this hero lives in. The destination hero's
  /// [Hero.createRectTween] is used, so Room's describes the trip home.
  final bool isRoom;

  static const Object tag = 'twin-bear';

  @override
  Widget build(BuildContext context) {
    return HeroMode(
      enabled: !MediaQuery.disableAnimationsOf(context),
      child: Hero(
        tag: tag,
        createRectTween: (Rect? begin, Rect? end) =>
            SwooshHopRectTween(begin: begin, end: end, homeward: isRoom),
        flightShuttleBuilder: swooshBearShuttle,
        child: SwooshBearSprite(weights: _weightsFor(resting)),
      ),
    );
  }

  static List<double> _weightsFor(String pose) => <double>[
        pose == SwooshBearAssets.stand ? 1 : 0,
        pose == SwooshBearAssets.wave ? 1 : 0,
        pose == SwooshBearAssets.jump ? 1 : 0,
      ];
}

/// Three poses stacked and cross-faded by [weights] (stand, wave, jump),
/// optionally squashed about the feet.
class SwooshBearSprite extends StatelessWidget {
  const SwooshBearSprite({super.key, required this.weights, this.squash = const Offset(1, 1)});

  final List<double> weights;

  /// (scaleX, scaleY) about the feet.
  final Offset squash;

  @override
  Widget build(BuildContext context) {
    const List<String> poses = <String>[
      SwooshBearAssets.stand,
      SwooshBearAssets.wave,
      SwooshBearAssets.jump,
    ];
    return Transform(
      alignment: SwooshGeometry.feetAlignment,
      transform: Matrix4.diagonal3Values(squash.dx, squash.dy, 1),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          for (int i = 0; i < 3; i++)
            if (weights[i] > 0.005)
              Opacity(
                opacity: weights[i].clamp(0.0, 1.0),
                child: Image.asset(poses[i],
                    fit: BoxFit.fitHeight, alignment: Alignment.bottomCenter, gaplessPlayback: true),
              ),
        ],
      ),
    );
  }
}

/// Undoes Flutter's hero curve (`Curves.fastOutSlowIn`) to recover the
/// linear elapsed fraction, so the hero can follow our own timeline.
double _uncurveHero(double y) {
  double lo = 0, hi = 1;
  for (int i = 0; i < 24; i++) {
    final double mid = (lo + hi) / 2;
    if (Curves.fastOutSlowIn.transform(mid) < y) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// Hero bounds: our own travel easing plus a gravity hop.
///
/// The hero machinery feeds this tween `fastOutSlowIn(elapsed)` in both
/// directions (begin = departing hero, end = arriving hero). We invert that
/// to elapsed time and apply the spec: forward travel 140–560 ms with a
/// 40 pt hop; homeward travel 110–420 ms with a 48 pt hop, then the small
/// 22 pt bear_jump at 470–630 ms. Verify against your Flutter version's
/// `heroes.dart` if the hero curve ever changes.
class SwooshHopRectTween extends RectTween {
  SwooshHopRectTween({super.begin, super.end, required this.homeward});

  final bool homeward;

  @override
  Rect? lerp(double t) {
    if (begin == null || end == null) return super.lerp(t);
    final double elapsed = _uncurveHero(t.clamp(0.0, 1.0));
    final double ms = elapsed * (homeward ? SwooshTiming.reverseMs : SwooshTiming.forwardMs);
    double seg(double s, double d, Curve c) => c.transform(((ms - s) / d).clamp(0.0, 1.0));
    double lin(double s, double d) => ((ms - s) / d).clamp(0.0, 1.0);

    final double travel = homeward ? seg(110, 310, SwooshCurves.inOut) : seg(140, 420, SwooshCurves.inOut);
    final double hop = homeward
        ? 48 * _parabola(lin(110, 310)) + 22 * _parabola(lin(470, 160))
        : 40 * _parabola(lin(140, 420));
    return Rect.lerp(begin, end, travel)!.shift(Offset(0, -hop));
  }
}

/// [Hero.flightShuttleBuilder]: swaps the pose mid-flight and squashes on
/// take-off and landing. `animation` is the hero's curved animation; for a
/// pop it runs 1 → 0 through `fastOutSlowIn.flipped`, hence `1 − value`.
Widget swooshBearShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final bool homeward = flightDirection == HeroFlightDirection.pop;
  return AnimatedBuilder(
    animation: animation,
    builder: (BuildContext context, Widget? _) {
      final double elapsed = homeward
          ? _uncurveHero((1 - animation.value).clamp(0.0, 1.0))
          : _uncurveHero(animation.value.clamp(0.0, 1.0));
      final double ms = elapsed * (homeward ? SwooshTiming.reverseMs : SwooshTiming.forwardMs);
      return SwooshBearSprite(
        weights: homeward ? _homewardPoses(ms) : _forwardPoses(ms),
        squash: _track<Offset>(ms, homeward ? _homewardSquash : _forwardSquash, _lerpOffset),
      );
    },
  );
}

double _segAt(double ms, double s, double d, [Curve c = Curves.linear]) =>
    c.transform(((ms - s) / d).clamp(0.0, 1.0));

/// stand → wave at the top of the hop (325–375 ms).
List<double> _forwardPoses(double ms) {
  final double wave = _segAt(ms, 325, 50, SwooshCurves.inOut);
  return <double>[1 - wave, wave, 0];
}

/// wave → stand while crouching, stand → jump on the landing bounce, back to
/// stand on the final touch-down.
List<double> _homewardPoses(double ms) {
  final double wave = 1 - _segAt(ms, 40, 60, SwooshCurves.inOut);
  final double jump =
      _segAt(ms, 455, 30, SwooshCurves.inOut) * (1 - _segAt(ms, 628, 28, SwooshCurves.inOut));
  return <double>[(1 - wave - jump).clamp(0.0, 1.0), wave, jump];
}

const List<_Key<Offset>> _forwardSquash = <_Key<Offset>>[
  _Key<Offset>(0, Offset(1, 1)),
  _Key<Offset>(60, Offset(1, 1)),
  _Key<Offset>(140, Offset(1.05, 0.93), SwooshCurves.out), // anticipation
  _Key<Offset>(220, Offset(0.97, 1.05), SwooshCurves.out), // take-off stretch
  _Key<Offset>(380, Offset(1, 1), SwooshCurves.inOut),
  _Key<Offset>(520, Offset(0.99, 1.02), SwooshCurves.inn),
  _Key<Offset>(560, Offset(1, 1)),
  _Key<Offset>(620, Offset(1.07, 0.92), SwooshCurves.out), // landing squash
  _Key<Offset>(720, Offset(1, 1), SwooshCurves.back),
];

const List<_Key<Offset>> _homewardSquash = <_Key<Offset>>[
  _Key<Offset>(0, Offset(1, 1)),
  _Key<Offset>(40, Offset(1, 1)),
  _Key<Offset>(110, Offset(1.05, 0.93), SwooshCurves.out),
  _Key<Offset>(180, Offset(0.97, 1.05), SwooshCurves.out),
  _Key<Offset>(340, Offset(1, 1), SwooshCurves.inOut),
  _Key<Offset>(420, Offset(1, 1)),
  _Key<Offset>(450, Offset(1.06, 0.92), SwooshCurves.out), // touch-down
  _Key<Offset>(470, Offset(1.03, 0.96), SwooshCurves.out),
  _Key<Offset>(520, Offset(0.97, 1.04), SwooshCurves.out), // bear_jump
  _Key<Offset>(600, Offset(1, 1), SwooshCurves.inOut),
  _Key<Offset>(630, Offset(1, 1)),
  _Key<Offset>(670, Offset(1.05, 0.94), SwooshCurves.out),
  _Key<Offset>(740, Offset(1, 1), SwooshCurves.back),
];

// ---------------------------------------------------------------------------
// Wiring example (artboard coordinates; the real pages use the shared
// widgets from painted-card-direction.md §6: PlateWindow, Bubble, LipButton…)
// ---------------------------------------------------------------------------

/// Minimal Onboarding page showing how a [SwooshFrame] maps onto widgets.
/// Room is analogous with [SwooshRoomStage] and its own [SwooshBearHero]
/// (`isRoom: true`, resting `stand`), and calls
/// `SwooshRoute.push(context, (_) => const SwooshOnboardingSketch())` on Talk.
class SwooshOnboardingSketch extends StatelessWidget {
  const SwooshOnboardingSketch({super.key, this.sheetChildren = const <Widget>[]});

  /// Rows of the sheet (dots, Hold to talk, Type instead, two chips).
  final List<Widget> sheetChildren;

  @override
  Widget build(BuildContext context) {
    return SwooshStage(builder: (BuildContext context, SwooshFrame f) {
      const Rect w = SwooshGeometry.windowRoom;
      const double inset = SwooshGeometry.windowInset;
      final Rect bear = SwooshGeometry.bearRect(1);
      return Stack(
        children: <Widget>[
          // Plate window, glued to the sheet. Hidden until the hand-off frame.
          Positioned(
            left: w.left,
            top: w.top,
            width: w.width,
            height: f.windowHeight,
            child: Visibility.maintain(
              visible: f.windowVisible,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF8),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFA88B7D), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Positioned.fromRect(
                          rect: f.plateRect,
                          child: Image.asset('assets/scene/room.jpg', fit: BoxFit.cover),
                        ),
                        // Ground shadow: stays on the island, shrinks while airborne.
                        Positioned(
                          left: f.feet.dx - 85,
                          top: f.feet.dy - 16,
                          width: 170,
                          height: 30,
                          child: Transform.scale(
                            scale: f.shadowScale,
                            child: Opacity(
                              opacity: 1 - 0.5 * (f.hop / 48).clamp(0.0, 1.0),
                              child: const DecoratedBox(
                                decoration: ShapeDecoration(
                                  color: Color(0x2E4A2F25),
                                  shape: OvalBorder(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // The bear: at rest it sits at its Onboarding rect.
                        Positioned(
                          left: bear.left - w.left - inset,
                          top: bear.top - w.top - inset,
                          width: bear.width,
                          height: bear.height,
                          child: const SwooshBearHero(resting: SwooshBearAssets.wave, isRoom: false),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Wind lines above the window, below the sheet.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: SwooshWindPainter(f.wind, f.windClipBottom)),
            ),
          ),
          // Sheet on its bezier.
          Positioned.fromRect(
            rect: SwooshGeometry.sheet,
            child: SwooshSheetTransform(
              frame: f,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF8),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFA88B7D), width: 1.5),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(color: Color(0x244A2F25), offset: Offset(0, 6), blurRadius: 16),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int i = 0; i < sheetChildren.length && i < 5; i++)
                        Opacity(
                          opacity: f.contentOpacity[i],
                          child: Transform.translate(
                            offset: Offset(0, f.contentOffsetY[i]),
                            child: sheetChildren[i],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Back button and question bubble pop in last.
          Positioned(
            left: 32,
            top: 99,
            width: 52,
            height: 52,
            child: Opacity(
              opacity: f.backOpacity,
              child: Transform.scale(
                scale: f.backScale,
                child: IconButton.outlined(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.chevron_left),
                ),
              ),
            ),
          ),
          Positioned(
            left: 210,
            top: 112,
            width: 156,
            child: Opacity(
              opacity: f.bubbleOpacity,
              child: Transform.scale(
                scale: f.bubbleScale,
                alignment: const Alignment(-1.13, 0.0), // the tail, on the left edge
                child: const Text('How tall\nare you?'),
              ),
            ),
          ),
        ],
      );
    });
  }
}

