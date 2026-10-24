import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The airy card frame around a painted plate: a 1.5px outer line, a 6px
/// cream rim, a 1px gold inner rule at 70% and a 30px radius, with the
/// `{ Name }` banner half over the top edge.
///
/// [plate] is clipped to the inner window; [overlay] (back button, bubble,
/// chips) sits above it, unclipped, in the same coordinates as the frame.
class PlateWindow extends StatelessWidget {
  const PlateWindow({
    super.key,
    required this.plate,
    this.name,
    this.night = false,
    this.overlay,
    this.showBanner = true,
  });

  final Widget plate;
  final String? name;
  final bool night;
  final Widget? overlay;
  final bool showBanner;

  /// Space the banner needs above the frame.
  static const double bannerOverhang = 22;

  @override
  Widget build(BuildContext context) {
    final frame = DecoratedBox(
      decoration: BoxDecoration(
        color: night ? LtColors.night : LtColors.paper,
        borderRadius: BorderRadius.circular(LtRadii.window),
        border: Border.all(color: night ? LtColors.nightLine : LtColors.container, width: LtBorders.container),
        boxShadow: night ? LtShadows.night : LtShadows.soft,
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(LtRadii.plate), child: plate),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(LtRadii.plate),
                  border: Border.all(color: LtColors.goldRule.withValues(alpha: 0.7), width: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: showBanner ? bannerOverhang : 0),
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          frame,
          // Gold corner sparkles only at night; day plates have painted ones.
          if (night) ...[
            const Positioned(right: 18, top: 30, child: _Sparkle(size: 14)),
            const Positioned(left: 20, bottom: 26, child: _Sparkle(size: 10)),
          ],
          if (overlay != null) Positioned.fill(child: overlay!),
          if (showBanner)
            Positioned(
              top: -bannerOverhang,
              left: 0,
              right: 0,
              // Not a control: taps go through to the corner button it may overlap at large text.
              child: IgnorePointer(
                child: Center(child: NameBanner(name: name)),
              ),
            ),
        ],
      ),
    );
  }
}

/// `{ Name }`: 44pt tall, Fredoka 22, at most 240 wide. A long name scales
/// down to 18, then ellipsises. No name reads "My twin".
class NameBanner extends StatelessWidget {
  const NameBanner({super.key, this.name});

  final String? name;

  static const double maxWidth = 240;

  @override
  Widget build(BuildContext context) {
    final shown = (name == null || name!.trim().isEmpty) ? 'My twin' : name!.trim();
    final scaler = MediaQuery.textScalerOf(context);
    final brace = LtText.display(22, color: LtColors.brace);
    double measure(String s) {
      final p = TextPainter(
        text: TextSpan(text: s, style: LtText.display(22)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = p.width;
      p.dispose();
      return w;
    }

    final braceWidth = measure('{ ') * 2;
    final room = maxWidth - 40 - braceWidth;
    final natural = measure(shown);
    final size = natural <= room ? 22.0 : math.max(18.0, 22 * room / natural);
    return Semantics(
      label: 'Twin name: $shown',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: LtColors.container, width: LtBorders.container),
          boxShadow: LtShadows.soft,
        ),
        // One line inside the banner: at very large text the whole banner shrinks to fit.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('{ ', style: brace, maxLines: 1),
              ConstrainedBox(
                // Long names ellipsise; at large text the whole banner shrinks instead.
                constraints: BoxConstraints(maxWidth: math.max(room, 420)),
                child: Text(
                  shown,
                  style: LtText.display(size),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              Text(' }', style: brace, maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: _SparklePainter()),
  );
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = LtColors.gold);
  }

  @override
  bool shouldRepaint(_SparklePainter oldDelegate) => false;
}
