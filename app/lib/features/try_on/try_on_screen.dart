import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/experiment_state.dart';
import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_button.dart';
import '../../widgets/lt_card.dart';
import '../../widgets/lt_chips.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_scaffold.dart';
import '../../widgets/lt_sheet.dart';
import '../plan/plan_state.dart';

/// F7 as a sheet, opened from the plan.
Future<void> showTryOnSheet(BuildContext context, PlanItem item) {
  final router = GoRouter.of(context);
  return showLtSheet<void>(
    context,
    builder: (ctx) => LtSheetScaffold(
      title: 'Try on twin',
      child: TryOnContent(
        item: item,
        onConfirmed: () {
          Navigator.of(ctx).pop();
          router.push('/experiment');
        },
      ),
    ),
  );
}

/// Route fallback for F7: the same content as a page, for the first plan item.
class TryOnScreen extends StatelessWidget {
  const TryOnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LtPage(
      title: 'Try on twin',
      child: ListView(
        padding: const EdgeInsets.all(LtSpace.gutter),
        children: [
          TryOnContent(
            item: planItems.first,
            onConfirmed: () => context.push('/experiment'),
          ),
        ],
      ),
    );
  }
}

/// Shows the assumed input change. Confirming starts an experiment; it
/// never touches the confirmed baseline.
class TryOnContent extends ConsumerWidget {
  const TryOnContent({
    super.key,
    required this.item,
    required this.onConfirmed,
  });

  final PlanItem item;
  final VoidCallback onConfirmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final baseline = ref.watch(baselineInputsProvider);
    final change = item.assumed;
    final from = change.valueIn(baseline.inputs);
    final to = change.valueIn(change.applyTo(baseline.inputs));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(item.title, style: context.text.headline),
        const SizedBox(height: LtSpace.s12),
        LtCard(
          padding: const EdgeInsets.all(LtSpace.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assumed change', style: context.text.footnote),
              const SizedBox(height: LtSpace.s8),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label:
                          '${change.inputLabel}: $from to $to ${change.unit}',
                      excludeSemantics: true,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${change.inputLabel}: '),
                            TextSpan(text: '$from'),
                            const TextSpan(text: '  →  '),
                            TextSpan(
                              text: '$to',
                              style: TextStyle(color: c.actionPrimary),
                            ),
                            TextSpan(
                              text: ' ${change.unit}',
                              style: context.text.callout.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        style: context.text.title3,
                      ),
                    ),
                  ),
                  const SizedBox(width: LtSpace.s8),
                  DeltaChip(
                    direction: change.delta >= 0
                        ? DeltaDirection.up
                        : DeltaDirection.down,
                    value: '${change.delta.abs()}',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: LtSpace.s12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LtIcon(LtIcons.info, color: c.textSecondary, size: 20),
            const SizedBox(width: LtSpace.s8),
            Expanded(
              child: Text(
                baseline.isSample
                    ? 'Hypothetical, from a sample baseline because no real '
                          'values are saved yet. Your real baseline is not '
                          'changed.'
                    : 'Hypothetical. Your real baseline is not changed.',
                style: context.text.footnote,
              ),
            ),
          ],
        ),
        const SizedBox(height: LtSpace.s16),
        LtButton(
          label: 'Confirm and try it',
          onPressed: () {
            ref.read(experimentProvider.notifier).apply(change);
            ref
                .read(planStatusProvider.notifier)
                .set(item.id, PlanStatus.added);
            onConfirmed();
          },
        ),
      ],
    );
  }
}
