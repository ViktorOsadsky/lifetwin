import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_chips.dart';
import '../../state/experiment_state.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_list.dart';
import '../../widgets/lt_scaffold.dart';
import '../try_on/try_on_screen.dart';
import 'plan_state.dart';

/// F6: three ranked items, each with a Model row and an Evidence row.
/// Both rows are placeholders until the model and research are connected.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  final _followUp = TextEditingController();
  String? _noted;

  @override
  void dispose() {
    _followUp.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _followUp.text.trim();
    if (t.isEmpty) return;
    setState(() => _noted = t);
    _followUp.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = ref.watch(planStatusProvider);
    return Scaffold(
      backgroundColor: c.bgGround,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: LtSpace.s32),
          children: [
            const LtLargeTitle(title: 'Plan'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LtSpace.gutter),
              child: Text(
                'Three small steps that may help. Tap one to try it on your '
                'twin first; nothing real changes.',
                style: context.text.subhead.copyWith(color: c.textSecondary),
              ),
            ),
            const LtSectionHeader('Most helpful first'),
            LtRowGroup(
              children: [
                for (final (i, item) in planItems.indexed)
                  _PlanRow(
                    rank: i + 1,
                    item: item,
                    status: status[item.id] ?? PlanStatus.open,
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                LtSpace.gutter,
                LtSpace.s12,
                LtSpace.gutter,
                0,
              ),
              child: OutlookFootnote(),
            ),
            const LtSectionHeader('Ask a follow-up'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LtSpace.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: LtSpace.s4),
                  _FollowUp(controller: _followUp, onSubmit: _submit),
                  if (_noted != null)
                    Padding(
                      padding: const EdgeInsets.only(top: LtSpace.s12),
                      child: Text(
                        'Thanks, noted: “$_noted”. Research isn’t connected '
                        'yet, so there’s no answer to show just now.',
                        style: context.text.footnote,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One plan item as a plain row: tap to open the try-on sheet (where "Try
/// on twin" lives); Skip / Undo is a small trailing text button.
class _PlanRow extends ConsumerWidget {
  const _PlanRow({
    required this.rank,
    required this.item,
    required this.status,
  });

  final int rank;
  final PlanItem item;
  final PlanStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final skipped = status == PlanStatus.skipped;
    final notifier = ref.read(planStatusProvider.notifier);
    final icon = switch (item.assumed.kind) {
      ChangeKind.sleep => LtIcons.moon,
      _ => LtIcons.sneaker,
    };
    return LtRow(
      semanticsLabel:
          'Step $rank. ${item.title}. Modeled change placeholder. '
          'Evidence placeholder.${switch (status) {
            PlanStatus.open => ' Opens try on twin.',
            PlanStatus.added => ' On your twin. Opens the experiment.',
            PlanStatus.skipped => ' Skipped.',
          }}',
      leading: LtRowIcon(icon, muted: skipped),
      title: item.title,
      dimmed: skipped,
      subtitle: switch (status) {
        PlanStatus.open => null,
        PlanStatus.added => 'Added',
        PlanStatus.skipped => 'Skipped',
      },
      below: Wrap(
        spacing: LtSpace.s8,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const DeltaChip(
            direction: DeltaDirection.flat,
            value: '[x.x pts] at 10 y',
          ),
          Text(
            '·',
            style: context.text.subhead.copyWith(color: c.textSecondary),
          ),
          Text(
            '[SOURCE]',
            style: context.text.subhead.copyWith(color: c.textSecondary),
          ),
        ],
      ),
      onTap: status == PlanStatus.added
          ? () => context.push('/experiment')
          : () => showTryOnSheet(context, item),
      trailing: switch (status) {
        PlanStatus.open => LtTextButton(
          quiet: true,
          label: 'Skip',
          onPressed: () => notifier.set(item.id, PlanStatus.skipped),
        ),
        PlanStatus.skipped => LtTextButton(
          quiet: true,
          label: 'Undo',
          onPressed: () => notifier.set(item.id, PlanStatus.open),
        ),
        PlanStatus.added => null,
      },
      chevron: status == PlanStatus.added,
    );
  }
}

class _FollowUp extends StatelessWidget {
  const _FollowUp({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: LtSpace.touch),
            padding: const EdgeInsets.symmetric(horizontal: LtSpace.s16),
            decoration: BoxDecoration(
              color: c.bgSurface,
              borderRadius: LtRadius.smallAll,
              border: Border.all(color: c.line),
            ),
            child: TextField(
              controller: controller,
              onSubmitted: (_) => onSubmit(),
              textInputAction: TextInputAction.send,
              style: context.text.body,
              cursorColor: c.actionPrimary,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'What else should I look into?',
                hintStyle: context.text.body.copyWith(color: c.textSecondary),
              ),
            ),
          ),
        ),
        const SizedBox(width: LtSpace.s8),
        Semantics(
          button: true,
          label: 'Send follow-up',
          excludeSemantics: true,
          onTap: onSubmit,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSubmit,
            child: Container(
              width: LtSpace.touch,
              height: LtSpace.touch,
              decoration: BoxDecoration(
                color: c.actionPrimary,
                shape: BoxShape.circle,
              ),
              child: Center(child: LtIcon(LtIcons.send, color: c.bgSurface)),
            ),
          ),
        ),
      ],
    );
  }
}
