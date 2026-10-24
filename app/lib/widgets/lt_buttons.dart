import 'package:flutter/material.dart';

import '../theme/lifetwin_theme.dart';
import 'lip_button.dart';
import 'lt_icons.dart';

/// Label row shared by the big buttons: optional icon, then text that wraps.
class _Label extends StatelessWidget {
  const _Label({required this.label, required this.style, required this.enabled, this.icon});
  final String label;
  final TextStyle style;
  final bool enabled;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: style.copyWith(color: enabled ? LtColors.ink : LipStyle.disabledOutline),
    );
    if (icon == null) return text;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ExcludeSemantics(child: Opacity(opacity: enabled ? 1 : .5, child: icon)),
        const SizedBox(width: LtSpace.lg),
        Flexible(child: text),
      ],
    );
  }
}

/// Main action: mint face, navy outline, darker-mint lip. 96 pt tall (Main/Question/Readback).
class LtPrimaryButton extends StatelessWidget {
  const LtPrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.minHeight});

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  /// Defaults to [LtSize.primaryButton]; never below [LtSize.minButton].
  final double? minHeight;

  static const style = LipStyle(
    face: LtColors.mint,
    lip: LtColors.mintDeep,
    radius: LtRadii.primary,
    lipDepth: LtLip.primary,
    minHeight: LtSize.primaryButton,
  );

  @override
  Widget build(BuildContext context) => LipButton(
    style: _withHeight(style, minHeight),
    onPressed: onPressed,
    child: _Label(label: label, style: LtText.primaryButton, enabled: onPressed != null, icon: icon),
  );
}

/// Other actions: white face, navy outline, lavender lip. 78 pt tall.
class LtSecondaryButton extends StatelessWidget {
  const LtSecondaryButton({super.key, required this.label, required this.onPressed, this.icon, this.minHeight});

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;

  /// Defaults to [LtSize.secondaryButton]; never below [LtSize.minButton].
  final double? minHeight;

  static const style = LipStyle(
    face: LtColors.white,
    lip: LtColors.lavenderLip,
    radius: LtRadii.secondary,
    lipDepth: LtLip.secondary,
    minHeight: LtSize.secondaryButton,
  );

  @override
  Widget build(BuildContext context) => LipButton(
    style: _withHeight(style, minHeight),
    onPressed: onPressed,
    child: _Label(label: label, style: LtText.secondaryButton, enabled: onPressed != null, icon: icon),
  );
}

LipStyle _withHeight(LipStyle s, double? h) => h == null
    ? s
    : LipStyle(
        face: s.face,
        lip: s.lip,
        radius: s.radius,
        lipDepth: s.lipDepth,
        minHeight: h < LtSize.minButton ? LtSize.minButton : h,
        outline: s.outline,
        padding: s.padding,
      );

/// The small "‹ Back" pill at the top of each screen. 56 pt: the design's floor for
/// small controls; it grows with text size.
class LtBackButton extends StatelessWidget {
  const LtBackButton({super.key, required this.onPressed, this.label = 'Back'});
  final VoidCallback? onPressed;
  final String label;

  static const style = LipStyle(
    face: LtColors.white,
    lip: LtColors.lavenderLip,
    radius: LtRadii.pill,
    lipDepth: LtLip.small,
    minHeight: LtSize.smallTap,
    padding: EdgeInsets.fromLTRB(12, 6, 22, 6),
  );

  @override
  Widget build(BuildContext context) => LipButton(
    style: style,
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LtIcon(LtIconKind.back, size: 26, strokeWidth: 2.8),
        const SizedBox(width: LtSpace.xs),
        Flexible(child: Text(label, style: LtText.pillButton)),
      ],
    ),
  );
}

/// A choice that stays chosen (the forecast's time-span tiles). Selected: mint, thicker
/// outline, darker lip and a check mark, so it is never shown by color alone.
class LtChoiceTile extends StatelessWidget {
  const LtChoiceTile({
    super.key,
    required this.selected,
    required this.onPressed,
    required this.child,
    this.semanticLabel,
  });

  final bool selected;
  final VoidCallback? onPressed;
  final Widget child;
  final String? semanticLabel;

  static LipStyle styleFor(bool selected) => LipStyle(
    face: selected ? LtColors.mint : LtColors.white,
    lip: selected ? LtColors.mintDeep : LtColors.lavenderLip,
    radius: LtRadii.tile,
    lipDepth: LtLip.small,
    minHeight: LtSize.tile,
    outline: selected ? LtOutline.selected : LtOutline.width,
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
  );

  @override
  Widget build(BuildContext context) => LipButton(
    style: styleFor(selected),
    selected: selected,
    semanticLabel: semanticLabel,
    onPressed: onPressed,
    child: child,
  );
}
