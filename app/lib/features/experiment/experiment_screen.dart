import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/experiment_state.dart';
import '../../state/twin_look.dart';
import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_list.dart';
import '../../widgets/lt_chips.dart';
import '../../widgets/lt_curve_chart.dart';
import '../../widgets/lt_scaffold.dart';
import '../../widgets/lt_stepper.dart';
import '../../widgets/lt_twin.dart';
import '../../widgets/lt_habitat.dart';
import '../activity/record_measurements_sheet.dart';

/// F8: baseline twin and experiment twin on their own tiers. The experiment
/// is hypothetical: Reset clears it and never touches the confirmed baseline.
/// Tiers and deltas are illustrative until the model is connected.
class ExperimentScreen extends ConsumerWidget {
  const ExperimentScreen({super.key});

  static const baselineTier = 2;
  static const experimentTier = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final baseline = ref.watch(baselineInputsProvider);
    final experiment = ref.watch(experimentProvider) ?? baseline.inputs;
    final changed = experiment != baseline.inputs;
    final look = ref.watch(twinLookProvider);
    final notifier = ref.read(experimentProvider.notifier);

    final dActivity =
        experiment.activityMinutes - baseline.inputs.activityMinutes;
    final dSleep = experiment.sleepHours - baseline.inputs.sleepHours;

    return LtPage(
      title: 'Experiment',
      sheetToBottom: true,
      child: LayoutBuilder(
        builder: (context, box) {
          final stageH = (box.maxHeight * 0.36).clamp(176.0, 300.0);
          // The meadow runs 64 pt under the sheet, so its 120 pt feather
          // ends beneath the sheet edge instead of at a seam.
          const tuck = 64.0;
          return Stack(
            children: [
              // State: one continuous meadow, today on the left and the
              // experiment on the right, joined by a soft vertical fade.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: stageH + tuck,
                child: _CompareStage(
                  look: look,
                  changed: changed,
                  tuck: tuck,
                  baselineTier: baselineTier,
                  experimentTier: changed ? experimentTier : baselineTier,
                ),
              ),
              Positioned.fill(
                top: stageH,
                child: LtSheetPanel(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: LtSpace.s24),
                    children: [
                      // Choice: the inputs sit right under the twins they
                      // change.
                      const LtSectionHeader('Try a change on your twin'),
                      LtRowGroup(
                        children: [
                          _InputRow(
                            icon: LtIcons.sneaker,
                            label: 'Active minutes',
                            unit: 'min a week',
                            baseline: baseline.inputs.activityMinutes,
                            delta: _inputDelta(dActivity, 'min/wk'),
                            stepper: LtStepper(
                              label: 'Active minutes per week',
                              value: experiment.activityMinutes,
                              min: 0,
                              max: 1000,
                              step: 15,
                              onChanged: notifier.setActivity,
                            ),
                            value: experiment.activityMinutes,
                          ),
                          _InputRow(
                            icon: LtIcons.moon,
                            label: 'Sleep',
                            unit: 'h a night',
                            baseline: baseline.inputs.sleepHours,
                            delta: _inputDelta(dSleep, 'h'),
                            stepper: LtStepper(
                              label: 'Sleep hours per night',
                              value: experiment.sleepHours,
                              min: 4,
                              max: 12,
                              onChanged: notifier.setSleep,
                            ),
                            value: experiment.sleepHours,
                          ),
                        ],
                      ),
                      if (baseline.isSample)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(
                            LtSpace.gutter,
                            LtSpace.s4,
                            LtSpace.gutter,
                            0,
                          ),
                          child: LtNote(
                            label:
                                'This starts from a sample. Chat with Pip or '
                                'record real measurements to start from yours.',
                            icon: LtIcons.info,
                          ),
                        ),
                      // Consequence: the modeled change, placeholder until
                      // the model is connected.
                      const LtSectionHeader('What your twin’s outlook does'),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: LtSpace.gutter,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: LtSpace.s12,
                              runSpacing: LtSpace.s4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Modeled outlook',
                                  style: context.text.headline,
                                ),
                                const DeltaChip(
                                  direction: DeltaDirection.flat,
                                  value: '[x.x pts]',
                                  prefix: 'about ',
                                ),
                              ],
                            ),
                            const SizedBox(height: LtSpace.s12),
                            LtCurveChart(showExperiment: changed),
                            const SizedBox(height: LtSpace.s12),
                            const OutlookFootnote(),
                            const SizedBox(height: LtSpace.s16),
                            Container(height: 0.5, color: c.line),
                            const SizedBox(height: LtSpace.s8),
                            Wrap(
                              spacing: LtSpace.s16,
                              children: [
                                LtTextButton(
                                  label: 'Reset experiment',
                                  onPressed: changed ? notifier.reset : null,
                                ),
                                LtTextButton(
                                  label: 'Record real measurements',
                                  onPressed: () =>
                                      showRecordMeasurementsSheet(context),
                                ),
                              ],
                            ),
                            Text(
                              'Reset only clears this experiment. Your '
                              'baseline changes only when you record real '
                              'measurements.',
                              style: context.text.footnote,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _inputDelta(int delta, String unit) {
    final dir = delta > 0
        ? DeltaDirection.up
        : delta < 0
        ? DeltaDirection.down
        : DeltaDirection.flat;
    return DeltaChip(direction: dir, value: '${delta.abs()} $unit');
  }
}

/// Today and the experiment in one meadow. The baseline twin is muted by a
/// single colour filter (never Opacity, which would show its layers).
class _CompareStage extends StatelessWidget {
  const _CompareStage({
    required this.look,
    required this.changed,
    required this.tuck,
    required this.baselineTier,
    required this.experimentTier,
  });

  final TwinLook look;
  final bool changed;

  /// How far the stage runs under the sheet.
  final double tuck;
  final int baselineTier;
  final int experimentTier;

  /// 60 % saturation (Rec. 709 luma weights), alpha untouched.
  static const _muted = ColorFilter.matrix([
    0.68504, 0.28608, 0.02888, 0, 0, //
    0.08504, 0.88608, 0.02888, 0, 0, //
    0.08504, 0.28608, 0.62888, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        final w = box.maxWidth;
        const fadeBottom = 120.0;
        // Feet rest just above the sheet edge.
        final contact = (h - tuck - 18) / h;
        final labelH = MediaQuery.textScalerOf(context).scale(18) * 2 + 16;
        final twinW = ((h * contact - 48 - labelH) / Twin.aspect).clamp(
          48.0,
          w * 0.3,
        );
        Widget label(String title, int tier, CrossAxisAlignment align) =>
            Column(
              crossAxisAlignment: align,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: context.text.footnote.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontVariations: const [FontVariation('wght', 600)],
                  ),
                ),
                TierChip(tier: tier),
              ],
            );
        return Habitat(
          tier: baselineTier,
          splitTier: experimentTier,
          contactLine: contact,
          fadeTop: 48,
          fadeBottom: fadeBottom,
          actors: [
            HabitatActor(
              x: 0.27,
              footprint: twinW * 0.8,
              child: ColorFiltered(
                colorFilter: _muted,
                child: Twin(
                  width: twinW,
                  look: look,
                  mood: TwinMood.calm,
                  pose: TwinPose.rest,
                ),
              ),
            ),
            HabitatActor(
              x: 0.73,
              footprint: twinW * 0.8,
              child: Twin(
                width: twinW,
                look: look,
                mood: changed ? TwinMood.happy : TwinMood.calm,
                pose: changed ? TwinPose.cheer : TwinPose.rest,
              ),
            ),
          ],
          overlay: Padding(
            padding: const EdgeInsets.fromLTRB(
              LtSpace.gutter,
              LtSpace.s4,
              LtSpace.gutter,
              0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: label(
                    'Baseline',
                    baselineTier,
                    CrossAxisAlignment.start,
                  ),
                ),
                Expanded(
                  child: label(
                    'Trying',
                    experimentTier,
                    CrossAxisAlignment.end,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One adjustable input as a plain list row: illustrated icon, title, the
/// value with its usual baseline, a calm signed delta, and the stepper.
class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.icon,
    required this.label,
    required this.unit,
    required this.baseline,
    required this.value,
    required this.delta,
    required this.stepper,
  });

  final LtIcons icon;
  final String label;
  final String unit;
  final int baseline;
  final int value;
  final Widget delta;
  final Widget stepper;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.text.headline),
        const SizedBox(height: 2),
        Text(
          '$value $unit',
          style: context.text.subhead.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: LtSpace.s4),
        Wrap(
          spacing: LtSpace.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            delta,
            Text('from your usual $baseline', style: context.text.footnote),
          ],
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LtSpace.gutter,
        vertical: LtSpace.s12,
      ),
      // Beside the text when there is room; below it at large text sizes,
      // rather than squeezing the label.
      child: LayoutBuilder(
        builder: (context, box) {
          final roomy = box.maxWidth - 117 - 58 >= 130;
          return Row(
            crossAxisAlignment: roomy
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              LtRowIcon(icon),
              const SizedBox(width: 14),
              Expanded(
                child: roomy
                    ? text
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          text,
                          const SizedBox(height: LtSpace.s8),
                          stepper,
                        ],
                      ),
              ),
              if (roomy) ...[const SizedBox(width: LtSpace.s12), stepper],
            ],
          );
        },
      ),
    );
  }
}
