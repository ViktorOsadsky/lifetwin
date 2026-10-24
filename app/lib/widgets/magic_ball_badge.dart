import 'package:flutter/widgets.dart';

import '../theme/lifetwin_theme.dart';
import 'vector/shapes.dart';

const _ink = LtColors.ink;

/// "Pip beside the magic ball", the header badge on Fortune.dc.html (viewBox 150x72).
const magicBallBadgeShapes = <Shape>[
  Group(dx: 0, dy: 4, scale: 0.48, [
    PathShape('M60 36 V24', stroke: _ink, strokeWidth: 5, round: true),
    PathShape('M59 25 C46 8 26 10 21 22 C33 33 50 33 59 25 Z', fill: LtColors.mintDeep, stroke: _ink, strokeWidth: 5, round: true),
    PathShape('M61 25 C70 5 95 5 100 17 C91 31 72 33 61 25 Z', fill: LtColors.mintDeep, stroke: _ink, strokeWidth: 5, round: true),
    PathShape(
      'M60 34 C90 34 103 62 102 90 C101 116 84 130 60 130 C36 130 18 116 18 90 C18 60 31 34 60 34 Z',
      fill: LtColors.mint,
      stroke: _ink,
      strokeWidth: 5,
    ),
    Circle(53, 80, 6, fill: _ink),
    Circle(79, 80, 6, fill: _ink),
    PathShape('M58 94 Q66 101 74 94', stroke: _ink, strokeWidth: 4.5, round: true),
    Ellipse(88, 92, 7, 4.5, fill: LtColors.coral, opacity: .8),
  ]),
  PathShape('M76 68 H128 L121 54 H83 Z', fill: LtColors.mint, stroke: _ink, strokeWidth: 3, round: true),
  Circle(102, 30, 25, fill: LtColors.lavender, stroke: _ink, strokeWidth: 3),
  PathShape('M89 22 C91 16 95 12 101 10', stroke: LtColors.white, strokeWidth: 4, round: true),
  PathShape(
    'M134 4 L136 10 L142 12 L136 14 L134 20 L132 14 L126 12 L132 10 Z',
    fill: LtColors.coral,
    stroke: _ink,
    strokeWidth: 2,
    round: true,
  ),
];

/// Pip with the magic ball. Keeps its size when text is enlarged.
class MagicBallBadge extends StatelessWidget {
  const MagicBallBadge({super.key, this.width = 150, this.label = 'Pip beside the magic ball'});
  final double width;
  final String? label;

  @override
  Widget build(BuildContext context) => ShapeView(
    shapes: magicBallBadgeShapes,
    viewBox: const Size(150, 72),
    size: Size(width, width * 72 / 150),
    label: label,
  );
}
