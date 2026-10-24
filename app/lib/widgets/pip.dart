import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/lifetwin_theme.dart';
import 'vector/shapes.dart';

/// Pip's moods, one per artboard drawing.
enum PipMood {
  /// Question.dc.html / QuickAnswer.dc.html: soft smile.
  asking,

  /// Listening.dc.html: leaves up, wide eyes, "o" mouth, sound waves.
  listening,

  /// Readback.dc.html: happy closed eyes, open smile.
  pleased,
}

const _ink = LtColors.ink;
const _w = 3.5; // outline width in Pip's 120x140 drawing

// Shared by every mood (Pip's body, highlight and shadow).
const _shadow = Ellipse(60, 133, 34, 5, fill: _ink, opacity: .12);
const _body = PathShape(
  'M60 34 C90 34 103 62 102 90 C101 116 84 130 60 130 C36 130 18 116 18 90 C18 60 31 34 60 34 Z',
  fill: LtColors.mint,
  stroke: _ink,
  strokeWidth: _w,
  round: true,
);
const _shine = PathShape('M33 70 C36 57 43 49 52 46', stroke: LtColors.white, strokeWidth: 5, round: true);

const _restingSprout = <Shape>[
  PathShape('M60 36 V24', stroke: _ink, strokeWidth: _w, round: true),
  PathShape('M59 25 C46 8 26 10 21 22 C33 33 50 33 59 25 Z', fill: LtColors.mintDeep, stroke: _ink, strokeWidth: _w, round: true),
  PathShape('M61 25 C70 5 95 5 100 17 C91 31 72 33 61 25 Z', fill: LtColors.mintDeep, stroke: _ink, strokeWidth: _w, round: true),
];

Ellipse _cheek(double cx, double cy) => Ellipse(cx, cy, 6, 3.8, fill: LtColors.coral, opacity: .8);

final Map<PipMood, List<Shape>> _drawings = {
  PipMood.asking: [
    _shadow,
    ..._restingSprout,
    _body,
    _shine,
    const Circle(49, 80, 4.6, fill: _ink),
    const Circle(75, 80, 4.6, fill: _ink),
    const PathShape('M55 92 Q62 98 69 92', stroke: _ink, strokeWidth: 3.2, round: true),
    _cheek(38, 92),
    _cheek(84, 92),
  ],
  PipMood.listening: [
    _shadow,
    const PathShape('M60 36 V22', stroke: _ink, strokeWidth: _w, round: true),
    const PathShape('M59 23 C52 4 32 0 24 9 C31 25 49 30 59 23 Z', fill: LtColors.mintDeep, stroke: _ink, strokeWidth: _w, round: true),
    const PathShape('M61 23 C66 2 88 -2 97 6 C92 23 73 30 61 23 Z', fill: LtColors.mintDeep, stroke: _ink, strokeWidth: _w, round: true),
    _body,
    _shine,
    const Circle(49, 80, 6, fill: _ink),
    const Circle(75, 80, 6, fill: _ink),
    const Circle(51, 78, 1.8, fill: LtColors.white),
    const Circle(77, 78, 1.8, fill: LtColors.white),
    const Ellipse(62, 96, 4, 5, fill: _ink),
    _cheek(38, 93),
    _cheek(86, 93),
    const PathShape('M114 72 C120 80 120 92 114 100', stroke: LtColors.lavender, strokeWidth: 4.5, round: true),
    const PathShape('M126 64 C136 76 136 96 126 108', stroke: LtColors.lavender, strokeWidth: 4.5, round: true),
  ],
  PipMood.pleased: [
    _shadow,
    ..._restingSprout,
    _body,
    _shine,
    const PathShape('M41 83 Q47 76 53 83', stroke: _ink, strokeWidth: 3.6, round: true),
    const PathShape('M67 83 Q73 76 79 83', stroke: _ink, strokeWidth: 3.6, round: true),
    const PathShape('M51 92 Q60 105 69 92 Z', fill: _ink, stroke: _ink, strokeWidth: 2.5, round: true),
    _cheek(36, 93),
    _cheek(84, 93),
  ],
};

/// The drawing for [mood] and its viewBox. Listening is wider: it has sound waves.
(List<Shape>, Size) pipDrawing(PipMood mood) =>
    (_drawings[mood]!, mood == PipMood.listening ? const Size(146, 140) : const Size(120, 140));

/// Pip, the guide. Changing [mood] cross-fades; [bob] adds a slow idle float.
/// With reduced motion (MediaQuery.disableAnimations) both are off.
class Pip extends StatefulWidget {
  const Pip({super.key, this.mood = PipMood.asking, this.height = 112, this.bob = false, this.label});

  final PipMood mood;

  /// Pip keeps its size when text is enlarged.
  final double height;

  /// Off by default so screens stay calm and tests can settle.
  final bool bob;

  /// Screen-reader label; defaults to "Pip, asking" and so on.
  final String? label;

  @override
  State<Pip> createState() => _PipState();
}

class _PipState extends State<Pip> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBob();
  }

  @override
  void didUpdateWidget(Pip old) {
    super.didUpdateWidget(old);
    _syncBob();
  }

  void _syncBob() {
    final on = widget.bob && !MediaQuery.disableAnimationsOf(context);
    if (on && !_bob.isAnimating) {
      _bob.repeat();
    } else if (!on && _bob.isAnimating) {
      _bob
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (shapes, box) = pipDrawing(widget.mood);
    final size = Size(widget.height * box.width / box.height, widget.height);
    final still = MediaQuery.disableAnimationsOf(context);
    final drawing = ShapeView(
      key: ValueKey(widget.mood),
      shapes: shapes,
      viewBox: box,
      size: size,
      label: widget.label ?? 'Pip, ${widget.mood.name}',
    );
    return AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 220),
      child: AnimatedBuilder(
        key: ValueKey(widget.mood),
        animation: _bob,
        builder: (context, child) =>
            Transform.translate(offset: Offset(0, -3 * math.sin(_bob.value * 2 * math.pi)), child: child),
        child: drawing,
      ),
    );
  }
}
