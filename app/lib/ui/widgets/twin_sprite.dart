import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../swoosh_route.dart';
import '../theme.dart';
import '../twin_appearance.dart';
import '../twin_assets.dart';

/// Twin poses for the conversation: waving while it asks, thinking while it
/// listens, jumping when an answer was taken or is read back.
enum TwinMood {
  asking(TwinPose.wave),
  listening(TwinPose.think),
  pleased(TwinPose.jump);

  const TwinMood(this.pose);
  final TwinPose pose;
}

/// The chosen twin, feet-anchored: [height] is the sprite box, and the feet
/// sit at the manifest's anchor so swapping sprites never moves them. The
/// contact shadow is drawn under the feet (two flat ovals, no blur).
class TwinSprite extends StatelessWidget {
  const TwinSprite({
    super.key,
    required this.appearance,
    this.pose = TwinPose.stand,
    this.height = 180,
    this.shadow = true,
    this.hero = false,
    this.isRoom = true,
    this.glow = 0,
    this.ballLottie,
  });

  final TwinAppearance appearance;
  final TwinPose pose;
  final double height;
  final bool shadow;

  /// Fly between Room and Onboarding as one shared element (one per page).
  final bool hero;
  final bool isRoom;

  /// A soft glow behind the ball (0 = none, 1 = full). Drawn only when the
  /// twin really holds the ball ([TwinPose.holdBall] art exists for it).
  final double glow;

  /// Draws the vector `ball_glow` Lottie behind the held ball (the fortune
  /// ceremony), driven by this animation: 0 is its resting first frame, and
  /// one run 0 → 1 plays its two glow pulses. Under reduced motion it shows
  /// frame 0, still.
  final Animation<double>? ballLottie;

  bool get holdsBall => pose == TwinPose.holdBall && twinHasPose(appearance.type, appearance.look, pose);

  /// The feet, as a fraction of [height] from the top.
  double get feet => twinFeetAnchor(appearance.type, appearance.look, pose);

  @override
  Widget build(BuildContext context) {
    final asset = appearance.sprite(pose);
    Widget sprite = Image.asset(
      asset,
      height: height,
      width: height,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      gaplessPlayback: true,
      excludeFromSemantics: true,
    );
    if (hero) {
      // The swoosh's pose-swapping flight only has bear Cal-hat poses.
      final swoosh =
          appearance.type == TwinType.bear &&
          appearance.look == TwinLook.calHat &&
          (pose == TwinPose.stand || pose == TwinPose.wave || pose == TwinPose.jump);
      sprite = SizedBox.square(
        dimension: height,
        child: swoosh
            ? SwooshBearHero(resting: asset, isRoom: isRoom)
            : HeroMode(
                enabled: !MediaQuery.disableAnimationsOf(context),
                child: Hero(tag: SwooshBearHero.tag, child: sprite),
              ),
      );
    }
    return Semantics(
      image: true,
      label: twinDescription(appearance.type, appearance.look),
      child: SizedBox.square(
        dimension: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (shadow) ...[
              _oval(height * feet, height * 0.59, height * 0.1, 0.10),
              _oval(height * feet, height * 0.41, height * 0.055, 0.26),
            ],
            if (ballLottie != null && holdsBall) _ballLottie(context),
            if (glow > 0 && holdsBall) _glow(),
            Positioned.fill(child: sprite),
          ],
        ),
      ),
    );
  }

  /// The Lottie's globe (centre 256,236, radius 150 on its 512 canvas) is
  /// laid just behind the painted ball, a little larger, so its halo pulses
  /// around it; the Lottie's stand stays hidden behind the twin.
  Widget _ballLottie(BuildContext context) {
    final c = twinBallCenter(appearance.type);
    final side = height * twinBallRadius(appearance.type) * 1.12 * 512 / 150;
    return Positioned(
      key: const ValueKey('ball-glow-lottie'),
      left: height * c.dx - side * 0.5,
      top: height * c.dy - side * 236 / 512,
      width: side,
      height: side,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: MediaQuery.disableAnimationsOf(context)
              ? Lottie.asset(ballGlowLottie, animate: false)
              : Lottie.asset(ballGlowLottie, controller: ballLottie),
        ),
      ),
    );
  }

  Widget _glow() {
    final c = twinBallCenter(appearance.type);
    final r = height * 0.36;
    final a = glow.clamp(0.0, 1.0);
    return Positioned(
      left: height * c.dx - r,
      top: height * c.dy - r,
      width: r * 2,
      height: r * 2,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFFFFE6A8).withValues(alpha: 0.55 * a),
                const Color(0xFFC9B8FF).withValues(alpha: 0.28 * a),
                const Color(0x00C9B8FF),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
      ),
    );
  }

  Widget _oval(double cy, double w, double h, double alpha) => Positioned(
    left: (height - w) / 2,
    top: cy - h / 2,
    width: w,
    height: h,
    child: DecoratedBox(
      decoration: ShapeDecoration(
        color: LtColors.ink.withValues(alpha: alpha),
        shape: const OvalBorder(),
      ),
    ),
  );
}

/// A painted plate, cover-fitted and panned so a chosen point of the
/// painting (the island's feet spot) lands at [focusTarget] in the box.
/// [twinBuilder] gets the feet position, the plate's pixel scale and the box, so the
/// twin stays planted on the paint at any window size.
class PlateScene extends StatelessWidget {
  const PlateScene({
    super.key,
    required this.asset,
    this.focus = const Offset(0.5, 0.554),
    this.focusTarget = const Offset(0.5, 0.6),
    this.zoom = 1,
    this.semanticLabel,
    this.twinBuilder,
    this.background,
  });

  final String asset;

  /// The point in the painting (fractions of the 390 × 585 image).
  final Offset focus;

  /// Where that point should land (fractions of the box).
  final Offset focusTarget;

  /// Extra zoom over a plain cover fit.
  final double zoom;
  final String? semanticLabel;
  final Widget Function(Offset feet, double scale, Size box)? twinBuilder;
  final Color? background;

  static const Size plateSize = Size(390, 585);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final scale = math.max(w / plateSize.width, h / plateSize.height) * zoom;
        final iw = plateSize.width * scale, ih = plateSize.height * scale;
        // Pan so the focus lands on target, but never show past the paint.
        final dx = (w * focusTarget.dx - iw * focus.dx).clamp(math.min(0.0, w - iw), 0.0).toDouble();
        final dy = (h * focusTarget.dy - ih * focus.dy).clamp(math.min(0.0, h - ih), 0.0).toDouble();
        final feet = Offset(dx + iw * focus.dx, dy + ih * focus.dy);
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (background != null) Positioned.fill(child: ColoredBox(color: background!)),
            Positioned(
              left: dx,
              top: dy,
              width: iw,
              height: ih,
              child: Image.asset(
                asset,
                fit: BoxFit.cover,
                semanticLabel: semanticLabel,
                excludeFromSemantics: semanticLabel == null,
              ),
            ),
            if (twinBuilder != null) twinBuilder!(feet, scale, Size(w, h)),
          ],
        );
      },
    );
  }
}

/// Places [sprite] (a [TwinSprite] of [size]) with its feet on [feet].
Widget plantTwin(Offset feet, TwinSprite sprite) => Positioned(
  left: feet.dx - sprite.height / 2,
  top: feet.dy - sprite.height * sprite.feet,
  width: sprite.height,
  height: sprite.height,
  child: sprite,
);
