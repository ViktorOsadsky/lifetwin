import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../widgets/whole_word_text.dart';

/// A small bottom sheet with a title and words (the exact figure behind "(i)", a lever's
/// "Not counted" reason, the weight "Why not?").
Future<void> showInfoSheet(BuildContext context, {required String title, required String body, Widget? extra}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: LtColors.paper,
              borderRadius: BorderRadius.circular(LtRadii.panel),
              border: Border.all(color: LtColors.container, width: LtBorders.container),
              boxShadow: LtShadows.soft,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(header: true, child: Text(title, style: LtText.display(24))),
                  const SizedBox(height: 8),
                  WholeWordText(body, style: LtText.body()),
                  if (extra != null) ...[const SizedBox(height: 8), extra],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Close', style: LtText.body(weight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

/// The "(i)" button: a 48pt target that opens an info sheet.
class InfoButton extends StatelessWidget {
  const InfoButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox(
        width: 48,
        height: 48,
        child: Icon(Icons.info_outline_rounded, size: 26, color: LtColors.ink),
      ),
    ),
  );
}
