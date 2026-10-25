import 'package:flutter/material.dart';

import '../experiment/widgets/source_link.dart';
import '../ui/theme.dart';
import '../widgets/whole_word_text.dart';

/// The calm emergency pause (Z-19, Z-20, Z-32), shared by check-ins and the change chat.
///
/// Mochi says it once: "I'm sorry you're going through that. If you need help right now, please
/// call 911. We can carry on whenever you're ready." "Call 911" opens the phone app as a `tel:`
/// link the person taps; the app never dials by itself. "Continue" (and the pinned close) send
/// `resume`, and Mochi repeats the same question. No red, no alarm icons, no countdown, and
/// nothing is saved during this moment.
class EmergencyCard extends StatelessWidget {
  const EmergencyCard({super.key, required this.onContinue, this.picksUpAt, this.open = defaultOpenUrl});

  /// Sends `resume`.
  final VoidCallback onContinue;

  /// What Mochi was asking: "Picks up at: ...".
  final String? picksUpAt;
  final OpenUrl open;

  static const apology = 'I’m sorry you’re going through that.';
  static const help = 'If you need help right now, please call 911.';
  static const carryOn = 'We can carry on whenever you’re ready.';

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$apology $help $carryOn',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(apology, style: LtText.display(22)),
        const SizedBox(height: 8),
        Semantics(header: true, child: Text(help, style: LtText.display(28))),
        const SizedBox(height: 14),
        _Call911(onTap: () => open(Uri.parse('tel:911'))),
        const SizedBox(height: 4),
        Center(
          child: Text('Opens your phone app', style: LtText.body(color: LtColors.secondary)),
        ),
        const SizedBox(height: 12),
        WholeWordText(carryOn, style: LtText.body()),
        const SizedBox(height: 10),
        Semantics(
          button: true,
          label: 'Continue.${picksUpAt == null ? '' : ' Picks up at: $picksUpAt'}',
          excludeSemantics: true,
          onTap: onContinue,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onContinue,
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: LtColors.paper,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: LtColors.control, width: LtBorders.control),
                boxShadow: LtShadows.small,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.replay_rounded, size: 24, color: LtColors.ink),
                      const SizedBox(width: 8),
                      Text('Continue', style: LtText.display(22)),
                    ],
                  ),
                  if (picksUpAt != null)
                    Text(
                      'Picks up at: “$picksUpAt”',
                      style: LtText.body(color: LtColors.secondary),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A deep teal button, not red: calm, and big enough to find in a hurry.
class _Call911 extends StatelessWidget {
  const _Call911({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Call 911. Opens the phone app.',
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF17594A),
          borderRadius: BorderRadius.circular(36),
          boxShadow: LtShadows.soft,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phone_rounded, size: 28, color: LtColors.paper),
            const SizedBox(width: 10),
            Text('Call 911', style: LtText.display(26, color: LtColors.paper)),
          ],
        ),
      ),
    ),
  );
}
