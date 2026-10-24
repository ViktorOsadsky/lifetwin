import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_button.dart';
import '../../widgets/lt_chips.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_list.dart';
import '../../widgets/lt_scaffold.dart';
import '../../widgets/lt_segmented.dart';
import 'activity_format.dart';
import 'activity_models.dart';
import 'activity_providers.dart';
import 'log_workout_sheet.dart';
import 'record_measurements_sheet.dart';
import 'week_bar_chart.dart';

/// F12: weekly summary, week bars, workout list, log and import entry points.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final summary = ref.watch(activitySummaryProvider);
    final health = ref.watch(healthSummaryProvider);
    final workouts = ref.watch(workoutLogProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      backgroundColor: c.bgGround,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: LtSpace.s32),
          children: [
            const LtLargeTitle(title: 'Activity'),
            // The next useful action leads the screen.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LtSpace.gutter,
                0,
                LtSpace.gutter,
                LtSpace.s16,
              ),
              child: LtButton(
                label: workouts.isEmpty
                    ? 'Add your first workout'
                    : 'Log a workout',
                icon: LtIcons.plus,
                onPressed: () => showLogWorkoutSheet(context),
              ),
            ),
            _Summary(summary: summary, hasHealth: health != null),
            const LtSectionHeader('Add from elsewhere'),
            LtRowGroup(
              children: [
                LtRow(
                  leading: const LtRowIcon(LtIcons.heart),
                  title: 'Import from Apple Health',
                  subtitle: 'Read workouts from the last 4 weeks',
                  onTap: () => context.push('/health-import'),
                ),
                LtRow(
                  leading: const LtRowIcon(LtIcons.check),
                  title: 'Record real measurements',
                  subtitle: 'Choose what becomes your baseline',
                  onTap: () => showRecordMeasurementsSheet(context),
                ),
              ],
            ),
            const LtSectionHeader('Workouts'),
            if (workouts.isEmpty)
              const LtRow(
                leading: LtRowIcon(LtIcons.sneaker, muted: true),
                title: 'No workouts yet',
                subtitle:
                    'Log one with the button above, or import from Apple '
                    'Health. Either way works.',
              )
            else
              LtRowGroup(
                children: [
                  for (final w in workouts) _WorkoutRow(workout: w, now: now),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The weekly summary, straight on the page: no card, just type and the
/// week bars.
class _Summary extends ConsumerWidget {
  const _Summary({required this.summary, required this.hasHealth});

  final ActivitySummary summary;
  final bool hasHealth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LtSpace.gutter,
        LtSpace.s8,
        LtSpace.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: LtSpace.s12,
            runSpacing: LtSpace.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Your 4-week average', style: context.text.headline),
              SourceChip(
                label: summary.source.label,
                icon: summary.source.icon,
              ),
            ],
          ),
          const SizedBox(height: LtSpace.s4),
          // No placeholder stat or empty chart: just say what will appear.
          if (summary.isEmpty)
            Text(
              'No average yet. It appears after your first workout or an '
              'Apple Health import.',
              style: context.text.subhead.copyWith(color: c.textSecondary),
            )
          else
            Semantics(
              label: '${summary.average} active minutes per week',
              excludeSemantics: true,
              child: Wrap(
                spacing: LtSpace.s8,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text('${summary.average}', style: context.text.statXl),
                  Padding(
                    padding: const EdgeInsets.only(bottom: LtSpace.s8),
                    child: Text(
                      'active min/week',
                      style: context.text.subhead.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (hasHealth) ...[
            const SizedBox(height: LtSpace.s16),
            LtSegmented<ActivitySource>(
              segments: [
                for (final s in ActivitySource.values)
                  LtSegment(value: s, label: s.label),
              ],
              value: summary.source,
              onChanged: (s) =>
                  ref.read(summarySourceProvider.notifier).choose(s),
            ),
          ],
          if (!summary.isEmpty) ...[
            const SizedBox(height: LtSpace.s20),
            WeekBarChart(weekly: summary.weekly),
            const SizedBox(height: LtSpace.s8),
            Text(
              'Weekly totals for the last four weeks.',
              style: context.text.caption,
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkoutRow extends ConsumerWidget {
  const _WorkoutRow({required this.workout, required this.now});

  final Workout workout;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    void remove() => ref.read(workoutLogProvider.notifier).remove(workout.id);
    return Dismissible(
      key: ValueKey('workout-${workout.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => remove(),
      background: Container(
        color: c.chipSelected,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: LtSpace.s20),
        child: Text(
          'Remove',
          style: context.text.headline.copyWith(color: c.actionPrimary),
        ),
      ),
      child: Semantics(
        label:
            '${workout.type.label}, ${formatMinutes(workout.minutes)}, '
            '${workout.intensity.label}, ${formatDay(workout.date, now)}',
        onDismiss: remove,
        excludeSemantics: true,
        child: LtRow(
          leading: LtRowIcon(workout.type.icon),
          title: workout.type.label,
          subtitle:
              '${formatMinutes(workout.minutes)} · ${workout.intensity.label}',
          trailing: Text(
            formatDay(workout.date, now),
            style: context.text.subhead.copyWith(color: c.textSecondary),
          ),
        ),
      ),
    );
  }
}
