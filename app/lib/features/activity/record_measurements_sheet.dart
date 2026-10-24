import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/confirmed_baseline.dart';
import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_button.dart';
import '../../widgets/lt_chips.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_sheet.dart';
import 'activity_models.dart';
import 'activity_providers.dart';

Future<void> showRecordMeasurementsSheet(BuildContext context) =>
    showLtSheet<void>(
      context,
      builder: (ctx) => LtSheetScaffold(
        title: 'Record real measurements',
        child: RecordMeasurementsContent(
          onConfirmed: () => Navigator.of(ctx).pop(),
        ),
      ),
    );

/// F15: the only place the baseline can change. Activity offers the Apple
/// Health 4-week average or the manual log, then an explicit confirm.
class RecordMeasurementsContent extends ConsumerStatefulWidget {
  const RecordMeasurementsContent({super.key, this.onConfirmed});

  final VoidCallback? onConfirmed;

  @override
  ConsumerState<RecordMeasurementsContent> createState() =>
      _RecordMeasurementsContentState();
}

class _RecordMeasurementsContentState
    extends ConsumerState<RecordMeasurementsContent> {
  ActivitySource? _picked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final health = ref.watch(healthSummaryProvider);
    final manual = ref.watch(manualSummaryProvider);
    final baseline = ref.watch(confirmedBaselineProvider);

    final healthOk = health != null;
    final manualOk = !manual.isEmpty;
    final selected =
        _picked ??
        (healthOk
            ? ActivitySource.appleHealth
            : (manualOk ? ActivitySource.manual : null));
    final selectedAvg = switch (selected) {
      ActivitySource.appleHealth => health?.average,
      ActivitySource.manual => manual.average,
      null => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Only this changes your baseline. Logging workouts, experiments, '
          'looks and quiz answers never do.',
          style: context.text.subhead.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: LtSpace.s16),
        Text('Activity', style: context.text.headline),
        const SizedBox(height: LtSpace.s8),
        _Choice(
          title: 'Use 4-week average (Apple Health)',
          subtitle: healthOk
              ? 'About ${health.average} min/week, measured by your devices'
              : 'Not imported yet',
          enabled: healthOk,
          selected: selected == ActivitySource.appleHealth,
          onTap: () => setState(() => _picked = ActivitySource.appleHealth),
        ),
        const SizedBox(height: LtSpace.s8),
        _Choice(
          title: 'Use manual log',
          subtitle: manualOk
              ? 'About ${manual.average} min/week, from what you logged'
              : 'No workouts logged in the last 4 weeks',
          enabled: manualOk,
          selected: selected == ActivitySource.manual,
          onTap: () => setState(() => _picked = ActivitySource.manual),
        ),
        const SizedBox(height: LtSpace.s16),
        Container(
          padding: const EdgeInsets.all(LtSpace.s16),
          decoration: BoxDecoration(
            color: c.bgGround,
            borderRadius: LtRadius.smallAll,
          ),
          child: Text(
            'Age, sex, height, weight, sleep, smoking and drinks are set in '
            'your intake answers and are not changed here.',
            style: context.text.footnote,
          ),
        ),
        const SizedBox(height: LtSpace.s16),
        if (baseline.hasActivity) ...[
          Row(
            children: [
              // Flexible so the long label wraps instead of overflowing.
              Flexible(
                child: SourceChip(
                  label:
                      'Confirmed: ${baseline.activityMinutesPerWeek} min/week'
                      ' (${baseline.activitySource!.label})',
                  icon: LtIcons.check,
                ),
              ),
            ],
          ),
          const SizedBox(height: LtSpace.s12),
        ],
        LtButton(
          label: 'Confirm as my baseline',
          onPressed: selected == null || selectedAvg == null
              ? null
              : () {
                  ref
                      .read(confirmedBaselineProvider.notifier)
                      .confirmActivity(
                        minutesPerWeek: selectedAvg,
                        source: selected,
                      );
                  widget.onConfirmed?.call();
                },
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: '$title. $subtitle',
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(LtSpace.s16),
          decoration: BoxDecoration(
            color: selected ? c.chipSelected : c.bgSurface,
            borderRadius: LtRadius.smallAll,
            border: Border.all(
              color: selected ? c.actionPrimary : c.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.text.headline.copyWith(
                        color: enabled ? c.textPrimary : c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: context.text.footnote),
                  ],
                ),
              ),
              if (selected) LtIcon(LtIcons.check, color: c.actionPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
