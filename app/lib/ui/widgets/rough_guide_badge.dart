import 'package:flutter/material.dart';

import '../../widgets/whole_word_text.dart';
import '../theme.dart';
import 'lip_button.dart';
import 'mode_scaffold.dart';

/// "Rough guide": shown beside a number the model had to extrapolate (ages 30-34 and 80-85).
/// An icon and two words, a target of at least 48. Tapping it shows the engine's caveat word
/// for word: through [onTap] when the screen shows it inline (the Experiment, never covering
/// content), otherwise in a sheet (the Room).
class RoughGuideBadge extends StatelessWidget {
  const RoughGuideBadge({super.key, required this.caveat, this.onTap, this.expanded});

  final String caveat;
  final VoidCallback? onTap;

  /// For [onTap] users: whether the caveat is open now.
  final bool? expanded;

  static const label = 'Rough guide';

  void _sheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Sheet(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text(label, style: LtText.display(26))),
              const SizedBox(height: 8),
              WholeWordText(caveat, style: LtText.body()),
              const SizedBox(height: 16),
              LipButton(label: 'Got it', fontSize: 24, onTap: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    void tap() => onTap != null ? onTap!() : _sheet(context);
    return Semantics(
      container: true,
      button: true,
      expanded: expanded,
      label: '$label. Tap to read why.',
      excludeSemantics: true,
      onTap: tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Center(
            widthFactor: 1,
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF1D8),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: LtColors.control, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.help_outline_rounded, size: 22, color: LtColors.ink),
                  const SizedBox(width: 6),
                  Text(label, style: LtText.body(weight: FontWeight.w700), maxLines: 1, softWrap: false),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
