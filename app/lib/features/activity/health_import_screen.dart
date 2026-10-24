import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_button.dart';
import '../../widgets/lt_card.dart';
import '../../widgets/lt_chips.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_scaffold.dart';
import 'activity_providers.dart';
import 'log_workout_sheet.dart';
import 'record_measurements_sheet.dart';
import 'week_bar_chart.dart';

/// F14: pre-permission explainer, system permission, result card.
/// Denied or unavailable never blocks the manual log.
class HealthImportScreen extends ConsumerWidget {
  const HealthImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(healthImportProvider);
    return LtPage(
      title: 'Apple Health',
      child: ListView(
        padding: const EdgeInsets.all(LtSpace.gutter),
        children: switch (s.status) {
          ImportStatus.idle || ImportStatus.loading => [
            const _Explainer(),
            const SizedBox(height: LtSpace.s20),
            LtButton(
              label: 'Continue',
              loading: s.status == ImportStatus.loading,
              onPressed: () => ref.read(healthImportProvider.notifier).run(),
            ),
            const SizedBox(height: LtSpace.s8),
            Text(
              'iPhone will ask for your permission next.',
              style: context.text.footnote,
              textAlign: TextAlign.center,
            ),
            LtButton(
              label: 'Not now',
              variant: LtButtonVariant.ghost,
              onPressed: () => context.pop(),
            ),
          ],
          ImportStatus.imported => [_Result(state: s)],
          ImportStatus.noData => [
            _Message(
              icon: LtIcons.info,
              title: 'No workouts found',
              body:
                  'Apple Health has no workouts or exercise minutes from the '
                  'last 28 days that LifeTwin can read. Your manual log works '
                  'as normal.',
            ),
            const SizedBox(height: LtSpace.s20),
            ..._manualActions(context),
          ],
          ImportStatus.denied => [
            _Message(
              icon: LtIcons.lock,
              title: 'Apple Health is off for LifeTwin',
              body:
                  'That is fine. Your manual log stays fully usable. To change '
                  'this later, open Settings, then Health, then Data Access '
                  '& Devices, then LifeTwin.',
            ),
            const SizedBox(height: LtSpace.s20),
            ..._manualActions(context),
          ],
          ImportStatus.unavailable => [
            _Message(
              icon: LtIcons.info,
              title: 'Apple Health is not available here',
              body:
                  'This device cannot share Health data with LifeTwin right '
                  'now. Your manual log stays fully usable.',
            ),
            const SizedBox(height: LtSpace.s20),
            ..._manualActions(context),
          ],
        },
      ),
    );
  }

  List<Widget> _manualActions(BuildContext context) => [
    LtButton(
      label: 'Log a workout',
      onPressed: () => showLogWorkoutSheet(context),
    ),
    const SizedBox(height: LtSpace.s8),
    LtButton(
      label: 'Back to Activity',
      variant: LtButtonVariant.ghost,
      onPressed: () => context.pop(),
    ),
  ];
}

class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bring in your real activity', style: context.text.title1),
        const SizedBox(height: LtSpace.s8),
        Text(
          'Your watch and phone already track workouts. LifeTwin can turn '
          'them into a weekly average.',
          style: context.text.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: LtSpace.s20),
        const LtCard(
          child: Column(
            children: [
              _Fact(
                icon: LtIcons.heart,
                title: 'What is read',
                body:
                    'Workouts and exercise minutes from the last 28 days. '
                    'Read only; LifeTwin never writes to Apple Health.',
              ),
              SizedBox(height: LtSpace.s16),
              _Fact(
                icon: LtIcons.lock,
                title: 'What stays on your phone',
                body:
                    'Every workout and the weekly sums are worked out on this '
                    'device.',
              ),
              SizedBox(height: LtSpace.s16),
              _Fact(
                icon: LtIcons.send,
                title: 'What can leave it',
                body:
                    'Only the weekly average, never individual workouts. '
                    'Nothing is sent in this version.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.title, required this.body});

  final LtIcons icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.chipSelected,
            shape: BoxShape.circle,
          ),
          child: Center(child: LtIcon(icon, color: c.actionPrimary, size: 20)),
        ),
        const SizedBox(width: LtSpace.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.text.headline),
              const SizedBox(height: 2),
              Text(body, style: context.text.subhead),
            ],
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final LtIcons icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LtCard(
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.calmSurface,
              shape: BoxShape.circle,
            ),
            child: Center(child: LtIcon(icon, color: c.actionPrimary)),
          ),
          const SizedBox(height: LtSpace.s12),
          Text(title, style: context.text.title2, textAlign: TextAlign.center),
          const SizedBox(height: LtSpace.s8),
          Text(
            body,
            style: context.text.subhead.copyWith(color: c.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.state});

  final HealthImportState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LtCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SourceChip(label: 'Apple Health', icon: LtIcons.heart),
              const SizedBox(height: LtSpace.s12),
              Semantics(
                label:
                    'About ${state.average} minutes per week, Apple Health, '
                    'last 4 weeks',
                excludeSemantics: true,
                child: Text(
                  'About ${state.average} min/week',
                  style: context.text.title1,
                ),
              ),
              Text('(Apple Health, last 4 weeks)', style: context.text.subhead),
              const SizedBox(height: LtSpace.s20),
              WeekBarChart(weekly: state.weekly!),
              const SizedBox(height: LtSpace.s16),
              Text(
                'Measured by your devices; the model was built on '
                'self-reported activity.',
                style: context.text.footnote.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: LtSpace.s20),
        Consumer(
          builder: (context, ref, _) => LtButton(
            label: 'Use as my baseline…',
            onPressed: () => showRecordMeasurementsSheet(context),
          ),
        ),
        const SizedBox(height: LtSpace.s8),
        LtButton(
          label: 'Done',
          variant: LtButtonVariant.secondary,
          onPressed: () => context.pop(),
        ),
      ],
    );
  }
}
