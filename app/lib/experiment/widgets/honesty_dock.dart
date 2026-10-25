import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../widgets/whole_word_text.dart';
import '../experiment_copy.dart';

/// The Experiment's honesty dock, pinned to the bottom and never hidden:
/// "Linked, not proven. What-if only." with a "Why?" link, and an optional [action] button.
/// "Why?" opens [HonestyDock.showWhy] (the sheet behind every "Why?").
class HonestyDock extends StatelessWidget {
  const HonestyDock({super.key, this.action, this.whyExtra});

  final Widget? action;

  /// Extra words for the Why? sheet (for example the engine's message for a state).
  final String? whyExtra;

  static void showWhy(BuildContext context, {String? extra}) => showModalBottomSheet<void>(
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
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, child: Text('Linked, not proven', style: LtText.display(26))),
                const SizedBox(height: 8),
                WholeWordText(ExperimentCopy.whySheet, style: LtText.body()),
                if (extra != null) ...[const SizedBox(height: 8), WholeWordText(extra, style: LtText.body())],
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Got it', style: LtText.body(weight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Semantics(
      container: true,
      label: 'Next step',
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: LtColors.paper,
          border: Border(
            top: BorderSide(color: LtColors.container, width: LtBorders.container),
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(LtRadii.panel)),
          boxShadow: [BoxShadow(color: Color(0x1F4A2F25), offset: Offset(0, -6), blurRadius: 16)],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 14 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(
                      child: WholeWordText.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${ExperimentCopy.linked} ',
                              style: LtText.body(weight: FontWeight.w700),
                            ),
                            TextSpan(
                              text: ExperimentCopy.whatIfOnly,
                              style: LtText.body(color: LtColors.secondary),
                            ),
                          ],
                        ),
                        semanticsLabel: 'Linked, not proven. What-if only.',
                      ),
                    ),
                    _WhyLink(onTap: () => showWhy(context, extra: whyExtra)),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(height: 8), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _WhyLink extends StatelessWidget {
  const _WhyLink({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Why? Linked, not proven, what-if only',
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded, size: 22, color: LtColors.ink),
              const SizedBox(width: 6),
              Text(
                ExperimentCopy.why,
                style: LtText.body(weight: FontWeight.w700)
                    .copyWith(decoration: TextDecoration.underline, decorationThickness: 2),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
