import 'package:flutter/widgets.dart';

import '../theme/lifetwin_theme.dart';
import 'vector/shapes.dart';

/// Which artboard background to draw.
enum SceneKind {
  /// Main.dc.html: the tall room (wave, three squiggles, mint island). viewBox 390x400.
  room,

  /// Question.dc.html: the low strip behind Pip under a question. viewBox 390x150.
  strip,
}

const _roomShapes = <Shape>[
  PathShape('M0 110 C70 50 150 40 210 80 C270 120 330 60 390 90 L390 300 C320 330 250 318 195 322 C130 326 60 336 0 312 Z', fill: LtColors.lavenderWash),
  PathShape('M26 150 C50 136 76 136 100 148', stroke: LtColors.lavender, strokeWidth: 3.5, round: true),
  PathShape('M298 128 C318 116 340 116 360 126', stroke: LtColors.lavender, strokeWidth: 3.5, round: true),
  PathShape('M322 214 C336 206 350 206 364 212', stroke: LtColors.lavender, strokeWidth: 3.5, round: true),
  PathShape('M30 320 C40 296 130 290 200 292 C290 294 368 302 366 324 C364 346 290 356 200 356 C110 356 22 348 30 320 Z', fill: LtColors.mint),
  PathShape('M66 336 C96 342 128 344 158 344', stroke: LtColors.mintDeep, strokeWidth: 3.5, round: true),
  PathShape('M248 342 C278 340 304 336 326 330', stroke: LtColors.mintDeep, strokeWidth: 3.5, round: true),
  PathShape('M300 306 C312 306 322 308 332 312', stroke: LtColors.white, strokeWidth: 3.5, round: true),
];

const _stripShapes = <Shape>[
  PathShape('M0 70 C80 40 170 50 240 80 C300 104 350 90 390 72 L390 150 L0 150 Z', fill: LtColors.lavenderWash, opacity: .7),
  PathShape('M268 64 C288 52 312 52 334 62', stroke: LtColors.lavender, strokeWidth: 3.5, round: true),
  PathShape('M30 132 C40 116 90 112 130 114 C170 116 196 122 194 134 C192 146 160 150 110 150 C60 150 24 146 30 132 Z', fill: LtColors.mint),
];

/// The paper scene: lavender waves and a mint ground, stretched to the width given,
/// with [child] (Pip, the twin, a bubble) laid on top. Purely decorative.
class ScenePaper extends StatelessWidget {
  const ScenePaper({super.key, this.kind = SceneKind.strip, this.height, this.child});

  final SceneKind kind;

  /// Defaults to the artboard height (400 room, 150 strip).
  final double? height;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final room = kind == SceneKind.room;
    final box = room ? const Size(390, 400) : const Size(390, 150);
    return SizedBox(
      height: height ?? box.height,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(painter: ShapePainter(room ? _roomShapes : _stripShapes, box, stretch: true)),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}
