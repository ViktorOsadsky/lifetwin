import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../widgets/whole_word_text.dart';
import 'dashed_border.dart';
import 'pills.dart';

/// The round icon of a lever: mint, 44, 2px control outline.
class LeverIcon extends StatelessWidget {
  const LeverIcon(this.icon, {super.key, this.size = 44});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: LtColors.mintTint,
      shape: BoxShape.circle,
      border: Border.all(color: LtColors.control, width: LtBorders.control),
    ),
    child: Icon(icon, size: size * 0.6, color: LtColors.ink),
  );
}

/// One lever on the hub: its name, today's value, and what is in the what-if (a lilac value,
/// or a dashed "Same"). The whole row is one button that opens the lever.
class LeverRow extends StatelessWidget {
  const LeverRow({
    super.key,
    required this.icon,
    required this.title,
    required this.today,
    required this.whatIf,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;

  /// "Today 30 min a week".
  final String today;

  /// The what-if value, or null when it is the same as today.
  final String? whatIf;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: semanticLabel,
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: LtColors.control, width: LtBorders.control),
          boxShadow: LtShadows.small,
        ),
        child: Row(
          children: [
            LeverIcon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  WholeWordText(title, style: LtText.body(size: 18, weight: FontWeight.w700)),
                  WholeWordText(today, style: LtText.body(color: LtColors.secondary)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            whatIf == null ? const SamePill() : _ValueChip(whatIf!),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 28, color: LtColors.ink),
          ],
        ),
      ),
    ),
  );
}

class _ValueChip extends StatelessWidget {
  const _ValueChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: 92,
    constraints: const BoxConstraints(minHeight: 40),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFE9E6FB),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: LtColors.control, width: 1.5),
    ),
    child: Text(text, style: LtText.display(17), textAlign: TextAlign.center),
  );
}

/// The lever stepper (Y-2): a bounded control with fixed steps, the value always visible.
/// Two 64pt buttons; at the end of its range a button turns into a dashed, disabled one.
class BigStepper extends StatelessWidget {
  const BigStepper({
    super.key,
    required this.value,
    required this.unit,
    required this.minusLabel,
    required this.plusLabel,
    required this.onMinus,
    required this.onPlus,
  });

  /// "6½ h", "2 h".
  final String value;

  /// "a night", "a week".
  final String unit;
  final String minusLabel;
  final String plusLabel;

  /// Null: the end of the range; the button turns dashed and cannot be tapped.
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(40),
      border: Border.all(color: LtColors.control, width: LtBorders.control),
    ),
    child: Row(
      children: [
        _BigButton(icon: Icons.remove_rounded, label: minusLabel, onTap: onMinus, primary: false),
        Expanded(
          child: Semantics(
            liveRegion: true,
            label: '$value $unit',
            excludeSemantics: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: LtText.display(38), maxLines: 1),
                ),
                Text(unit, style: LtText.body(color: LtColors.secondary)),
              ],
            ),
          ),
        ),
        _BigButton(icon: Icons.add_rounded, label: plusLabel, onTap: onPlus, primary: true),
      ],
    ),
  );
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.icon, required this.label, required this.onTap, required this.primary});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final off = onTap == null;
    final face = off
        ? DashedBox(
            color: LtColors.container,
            radius: 32,
            width: 2,
            fill: LtColors.paper,
            child: SizedBox(width: 64, height: 64, child: Icon(icon, size: 30, color: LtColors.secondary)),
          )
        : Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary ? LtColors.mint : LtColors.paper,
              border: Border.all(color: LtColors.control, width: LtBorders.control),
              boxShadow: LtShadows.small,
            ),
            child: Icon(icon, size: 34, color: LtColors.ink),
          );
    return Semantics(
      button: true,
      enabled: !off,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: face),
    );
  }
}

/// The two-option control for smoking (Y-7): "Smoke now / Today" and "Quit / What-if".
class TwoOptionControl extends StatelessWidget {
  const TwoOptionControl({
    super.key,
    required this.firstLabel,
    required this.firstCaption,
    required this.secondLabel,
    required this.secondCaption,
    required this.secondSelected,
    required this.onChanged,
    required this.semanticLabel,
  });

  final String firstLabel;
  final String firstCaption;
  final String secondLabel;
  final String secondCaption;
  final bool secondSelected;
  final ValueChanged<bool> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, String caption, bool on, bool second) => Expanded(
      child: Semantics(
        button: true,
        inMutuallyExclusiveGroup: true,
        checked: on,
        label: '$label, $caption',
        excludeSemantics: true,
        onTap: () => onChanged(second),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(second),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: on ? LtColors.mint : Colors.transparent,
              borderRadius: BorderRadius.circular(32),
              border: on ? Border.all(color: LtColors.controlOnMint, width: LtBorders.control) : null,
              boxShadow: on ? LtShadows.small : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (on) const Icon(Icons.check_rounded, size: 22, color: LtColors.ink),
                    if (on) const SizedBox(width: 4),
                    Flexible(
                      child: Text(label, style: LtText.display(20), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                Text(caption, style: LtText.body(color: on ? LtColors.ink : LtColors.secondary)),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: LtColors.control, width: LtBorders.control),
        ),
        child: Row(
          children: [
            seg(firstLabel, firstCaption, !secondSelected, false),
            seg(secondLabel, secondCaption, secondSelected, true),
          ],
        ),
      ),
    );
  }
}
