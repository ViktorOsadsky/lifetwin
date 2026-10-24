import 'package:flutter/material.dart';

import '../theme/lt_space.dart';
import '../theme/lt_theme.dart';
import 'lt_icon.dart';

class LtSegment<T> {
  const LtSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final LtIcons? icon;
}

/// iOS-style segmented control: a rounded track with a white sliding thumb.
/// Segments with icons stack the icon above the label.
class LtSegmented<T> extends StatelessWidget {
  const LtSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<LtSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = segments.indexWhere((s) => s.value == value);
    final hasIcons = segments.any((s) => s.icon != null);
    final height = hasIcons ? 60.0 : LtSpace.touch;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Semantics(
      container: true,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.line,
          borderRadius: BorderRadius.circular(LtRadius.small),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth / segments.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: w * (selected < 0 ? 0 : selected),
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.bgSurface,
                      borderRadius: BorderRadius.circular(LtRadius.small - 3),
                      boxShadow: [
                        BoxShadow(
                          color: c.textPrimary.withValues(alpha: 0.12),
                          offset: const Offset(0, 2),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final s in segments)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: s.value == value,
                          label: s.label,
                          excludeSemantics: true,
                          onTap: () => onChanged(s.value),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onChanged(s.value),
                            child: _Cell(
                              segment: s,
                              selected: s.value == value,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Cell<T> extends StatelessWidget {
  const _Cell({required this.segment, required this.selected});

  final LtSegment<T> segment;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = selected ? c.textPrimary : c.textSecondary;
    final style = context.text.caption.copyWith(
      color: color,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: segment.icon == null
              ? Text(
                  segment.label,
                  style: context.text.footnote.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LtIcon(segment.icon!, color: color, size: 22),
                    const SizedBox(height: 2),
                    Text(segment.label, style: style),
                  ],
                ),
        ),
      ),
    );
  }
}
