import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../widgets/whole_word_text.dart';
import 'dashed_border.dart';

/// The dashed "no number" box (Y-15): an icon, a short title, an optional line, and an optional
/// trailing tag. Where it appears there is no number.
class NoNumberBox extends StatelessWidget {
  const NoNumberBox({super.key, required this.icon, required this.title, this.body, this.trailing});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => DashedBox(
    color: LtColors.control,
    radius: 22,
    width: 2,
    fill: LtColors.paper,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 24, color: LtColors.ink),
            const SizedBox(width: 8),
            Expanded(child: WholeWordText(title, style: LtText.display(19))),
            ?trailing,
          ],
        ),
        if (body != null) ...[const SizedBox(height: 6), WholeWordText(body!, style: LtText.body())],
      ],
    ),
  );
}
