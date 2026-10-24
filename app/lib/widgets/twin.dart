import 'package:flutter/widgets.dart';

import '../theme/lifetwin_theme.dart';
import 'vector/shapes.dart';

const _ink = LtColors.ink;
const _w = 3.5;

/// The twin waving, from Main.dc.html (viewBox 160x260). Outfit and colors are fixed
/// for now; customization comes later.
const twinShapes = <Shape>[
  Ellipse(80, 252, 50, 6, fill: _ink, opacity: .12),
  RectShape(56, 200, 18, 42, rx: 8, fill: LtColors.skinDeep, stroke: _ink, strokeWidth: _w),
  RectShape(86, 200, 18, 42, rx: 8, fill: LtColors.skinDeep, stroke: _ink, strokeWidth: _w),
  Ellipse(62, 245, 16, 8, fill: _ink),
  Ellipse(98, 245, 16, 8, fill: _ink),
  PathShape('M46 172 H114 L118 214 H86 L80 198 L74 214 H42 Z', fill: LtColors.lavender, stroke: _ink, strokeWidth: _w, round: true),
  PathShape('M52 132 L36 170', stroke: _ink, strokeWidth: 20, round: true),
  PathShape('M52 132 L36 170', stroke: LtColors.mint, strokeWidth: 13, round: true),
  Circle(34, 176, 8.5, fill: LtColors.skinDeep, stroke: _ink, strokeWidth: _w),
  PathShape('M108 132 L130 100', stroke: _ink, strokeWidth: 20, round: true),
  PathShape('M108 132 L130 100', stroke: LtColors.mint, strokeWidth: 13, round: true),
  Circle(133, 94, 8.5, fill: LtColors.skinDeep, stroke: _ink, strokeWidth: _w),
  RectShape(72, 100, 16, 18, fill: LtColors.skinDeep, stroke: _ink, strokeWidth: _w),
  PathShape('M48 126 C48 112 112 112 112 126 L116 176 C116 182 44 182 44 176 Z', fill: LtColors.mint, stroke: _ink, strokeWidth: _w, round: true),
  Circle(80, 68, 42, fill: LtColors.skin, stroke: _ink, strokeWidth: _w),
  PathShape('M38.5 66 C38 36 58 24 80 24 C102 24 122 36 121.5 66 C112 54 98 48 80 48 C62 48 48 54 38.5 66 Z', fill: LtColors.hair, stroke: _ink, strokeWidth: _w, round: true),
  Circle(66, 74, 4.6, fill: _ink),
  Circle(94, 74, 4.6, fill: _ink),
  PathShape('M72 88 Q80 95 88 88', stroke: _ink, strokeWidth: 3.2, round: true),
  Ellipse(56, 85, 6.5, 4, fill: LtColors.coral, opacity: .75),
  Ellipse(104, 85, 6.5, 4, fill: LtColors.coral, opacity: .75),
];

/// The person's twin. Keeps its size when text is enlarged.
class Twin extends StatelessWidget {
  const Twin({super.key, this.height = 276, this.label = 'Your twin, waving'});
  final double height;
  final String label;

  @override
  Widget build(BuildContext context) => ShapeView(
    shapes: twinShapes,
    viewBox: const Size(160, 260),
    size: Size(height * 160 / 260, height),
    label: label,
  );
}
