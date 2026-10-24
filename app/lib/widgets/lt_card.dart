import 'package:flutter/material.dart';

import '../theme/lt_space.dart';
import '../theme/lt_theme.dart';

/// Flat white surface, radius 24, no shadow or ledge (§7b: light, not
/// bubbly). Core screens use plain rows instead; this remains for the few
/// grouped forms on secondary screens.
class LtCard extends StatelessWidget {
  const LtCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LtSpace.s20),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: LtRadius.cardAll,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: box,
    );
  }
}
