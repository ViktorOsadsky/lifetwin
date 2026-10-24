import 'package:flutter/material.dart';

import '../theme/lt_space.dart';
import '../theme/lt_theme.dart';
import 'lt_icon.dart';

/// Base pill chip. Text is never smaller than 12.
class LtChip extends StatelessWidget {
  const LtChip({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    this.semanticsLabel,
  });

  final String label;
  final Color background;
  final Color foreground;
  final LtIcons? icon;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LtSpace.s12,
          vertical: LtSpace.s4 + 2,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: LtRadius.chipAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              LtIcon(icon!, color: foreground, size: 16),
              const SizedBox(width: LtSpace.s4 + 2),
            ],
            Flexible(
              child: Text(
                label,
                style: context.text.caption.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet inline note: small icon plus Footnote text in `ink-2`. Used for
/// provenance, tier names and the outlook caveats instead of bubble chips
/// (§7b.7: chips are only for selectable filters).
class LtNote extends StatelessWidget {
  const LtNote({
    super.key,
    required this.label,
    required this.icon,
    this.semanticsLabel,
    this.iconColor,
    this.color,
    this.strong = false,
  });

  final String label;
  final LtIcons icon;
  final String? semanticsLabel;
  final Color? iconColor;
  final Color? color;

  /// Medium weight, for labels that sit on a scene.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = strong
        ? context.text.footnote.copyWith(
            fontWeight: FontWeight.w600,
            fontVariations: const [FontVariation('wght', 600)],
          )
        : context.text.footnote;
    return Semantics(
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: LtIcon(icon, color: iconColor ?? c.textSecondary, size: 16),
          ),
          const SizedBox(width: LtSpace.s4 + 2),
          Flexible(
            child: Text(
              label,
              style: base.copyWith(color: color ?? c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Modeled association, not cause" - visible wherever outlook numbers appear.
class AssociationChip extends StatelessWidget {
  const AssociationChip({super.key});

  @override
  Widget build(BuildContext context) =>
      const LtNote(label: 'Modeled association, not cause', icon: LtIcons.info);
}

/// "Illustrative - model not connected" - on every placeholder figure.
class IllustrativeChip extends StatelessWidget {
  const IllustrativeChip({super.key});

  @override
  Widget build(BuildContext context) => const LtNote(
    label: 'Illustrative — model not connected',
    icon: LtIcons.sparkle,
  );
}

/// Both outlook caveats, once per section, as a quiet footnote.
class OutlookFootnote extends StatelessWidget {
  const OutlookFootnote({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      AssociationChip(),
      SizedBox(height: LtSpace.s4),
      IllustrativeChip(),
    ],
  );
}

/// Vitality tier name, as a small label with an icon on the scene (not a
/// bubble). The tier is never signalled by the habitat alone.
class TierChip extends StatelessWidget {
  const TierChip({super.key, required this.tier});

  final int tier;

  static String nameOf(int tier) => switch (tier) {
    4 => 'Thriving',
    3 => 'Good',
    2 => 'Steady',
    _ => 'Resting',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final high = tier >= 3;
    return LtNote(
      label: nameOf(tier),
      semanticsLabel: 'Vitality tier: ${nameOf(tier)}',
      icon: high ? LtIcons.sparkle : LtIcons.heart,
      iconColor: high ? c.textPositive : c.actionPrimary,
      color: c.textPrimary,
      strong: true,
    );
  }
}

enum DeltaDirection { up, down, flat }

/// A signed change as calm text: sign + number in `ink-2`, and a small arrow
/// icon that alone carries colour (green up, blue down, never red).
class DeltaChip extends StatelessWidget {
  const DeltaChip({
    super.key,
    required this.direction,
    required this.value,
    this.prefix = '',
  });

  final DeltaDirection direction;

  /// Magnitude text, e.g. `[x.x pts]`. The sign is added here.
  final String value;

  /// Optional softener such as `about `.
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (sign, icon, tint, word) = switch (direction) {
      DeltaDirection.up => ('+', LtIcons.arrowUp, c.textPositive, 'increase'),
      DeltaDirection.down => (
        '−',
        LtIcons.arrowDown,
        c.actionPrimary,
        'decrease',
      ),
      DeltaDirection.flat => ('±', LtIcons.equal, c.textSecondary, 'no change'),
    };
    return Semantics(
      label: '$word $value',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LtIcon(icon, color: tint, size: 16),
          const SizedBox(width: LtSpace.s4),
          if (prefix.isNotEmpty)
            Text(
              prefix,
              style: context.text.subhead.copyWith(color: c.textSecondary),
            ),
          Flexible(
            child: Text(
              '$sign$value',
              style: context.text.subhead.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Data provenance, e.g. "Manual" or "Apple Health": a quiet label.
class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.label, required this.icon});

  final String label;
  final LtIcons icon;

  @override
  Widget build(BuildContext context) =>
      LtNote(label: label, semanticsLabel: 'Source: $label', icon: icon);
}
