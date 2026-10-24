import 'package:flutter/material.dart';

import '../theme.dart';

/// A full-width 52pt chip with a leading icon (e.g. "Use my Health app").
/// With [selected] set it behaves as a choice (radio-like) chip.
class LtChip extends StatelessWidget {
  const LtChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.trailing,
    this.selected,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? trailing;

  /// Null for an action chip; true/false for a choice chip.
  final bool? selected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final on = selected ?? false;
    return Semantics(
      button: selected == null,
      inMutuallyExclusiveGroup: selected != null,
      checked: selected,
      enabled: onTap != null,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: _ChipShell(
        onTap: onTap,
        selected: on,
        children: [
          if (icon != null) ...[Icon(icon, size: 26, color: LtColors.ink), const SizedBox(width: 12)],
          Expanded(child: Text(label, style: LtText.body(weight: FontWeight.w700))),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (on) ...[const SizedBox(width: 8), const Icon(Icons.check_circle, color: LtColors.ink, size: 24)],
        ],
      ),
    );
  }
}

/// A chip that is a switch: the label says the state in words ("AI helper:
/// Off") and the track shows it too, so it is never colour alone.
class LtToggleChip extends StatelessWidget {
  const LtToggleChip({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
    this.semanticLabel,
  });

  /// The visible text, which should include the state.
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;

  /// What the switch controls, without the state (e.g. "AI helper").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tap = onChanged == null ? null : () => onChanged!(!value);
    return Semantics(
      toggled: value,
      button: true,
      enabled: onChanged != null,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: tap,
      child: _ChipShell(
        onTap: tap,
        selected: false,
        children: [
          if (icon != null) ...[Icon(icon, size: 26, color: LtColors.ink), const SizedBox(width: 12)],
          Expanded(child: Text(label, style: LtText.body(weight: FontWeight.w700))),
          const SizedBox(width: 8),
          _Track(on: value),
        ],
      ),
    );
  }
}

class _Track extends StatelessWidget {
  const _Track({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Container(
      width: 50,
      height: 30,
      decoration: BoxDecoration(
        color: on ? LtColors.mint : LtColors.trackOff,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: LtColors.controlOnMint, width: LtBorders.control),
      ),
      child: AnimatedAlign(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: on ? LtColors.ink : LtColors.paper,
            shape: BoxShape.circle,
            border: Border.all(color: LtColors.controlOnMint, width: LtBorders.control),
          ),
        ),
      ),
    );
  }
}

class _ChipShell extends StatelessWidget {
  const _ChipShell({required this.onTap, required this.selected, required this.children});
  final VoidCallback? onTap;
  final bool selected;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? LtColors.mint : LtColors.paper,
          borderRadius: BorderRadius.circular(LtRadii.chip),
          border: Border.all(
            color: selected ? LtColors.controlOnMint : LtColors.control,
            width: LtBorders.control,
          ),
          boxShadow: LtShadows.small,
        ),
        child: Row(children: children),
      ),
    );
  }
}

/// A status pill (not a control), e.g. the Room's "Feeling cozy".
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.icon = Icons.sentiment_satisfied_alt_rounded});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: LtColors.container, width: LtBorders.container),
          boxShadow: LtShadows.soft,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: LtColors.ink),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: LtText.body(weight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }
}
