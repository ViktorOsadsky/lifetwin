import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_button.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_segmented.dart';
import '../../widgets/lt_sheet.dart';
import '../../widgets/lt_stepper.dart';
import 'activity_format.dart';
import 'activity_models.dart';
import 'activity_providers.dart';

Future<void> showLogWorkoutSheet(BuildContext context) =>
    showLtSheet<void>(context, builder: (_) => const LogWorkoutSheet());

/// F13: type, duration, intensity, date, Save.
class LogWorkoutSheet extends ConsumerStatefulWidget {
  const LogWorkoutSheet({super.key});

  @override
  ConsumerState<LogWorkoutSheet> createState() => _LogWorkoutSheetState();
}

class _LogWorkoutSheetState extends ConsumerState<LogWorkoutSheet> {
  WorkoutType _type = WorkoutType.walk;
  Intensity _intensity = Intensity.moderate;
  int _minutes = 30;
  late DateTime _date = ref.read(clockProvider)();

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider)();
    var picked = _date;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return Container(
          height: 320,
          color: c.bgSurface,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: LtButton(
                    label: 'Done',
                    variant: LtButtonVariant.ghost,
                    expand: false,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: _date,
                    maximumDate: now,
                    minimumDate: DateTime(now.year - 1, now.month, now.day),
                    onDateTimeChanged: (d) => picked = d,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (mounted) setState(() => _date = picked);
  }

  void _save() {
    ref
        .read(workoutLogProvider.notifier)
        .add(
          type: _type,
          minutes: _minutes,
          intensity: _intensity,
          date: _date,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = ref.read(clockProvider)();
    return LtSheetScaffold(
      title: 'Log workout',
      footer: LtButton(label: 'Save', onPressed: _save),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Type', style: context.text.footnote),
          const SizedBox(height: LtSpace.s8),
          LtSegmented<WorkoutType>(
            segments: [
              for (final t in WorkoutType.values)
                LtSegment(value: t, label: t.label, icon: t.icon),
            ],
            value: _type,
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: LtSpace.s20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Duration', style: context.text.footnote),
                    Text(formatMinutes(_minutes), style: context.text.title2),
                  ],
                ),
              ),
              LtStepper(
                label: 'Duration',
                value: _minutes,
                min: 5,
                max: 300,
                step: 5,
                onChanged: (v) => setState(() => _minutes = v),
              ),
            ],
          ),
          const SizedBox(height: LtSpace.s20),
          Text('Intensity', style: context.text.footnote),
          const SizedBox(height: LtSpace.s8),
          LtSegmented<Intensity>(
            segments: [
              for (final i in Intensity.values)
                LtSegment(value: i, label: i.label),
            ],
            value: _intensity,
            onChanged: (v) => setState(() => _intensity = v),
          ),
          const SizedBox(height: LtSpace.s20),
          Semantics(
            button: true,
            label: 'Date, ${formatDay(_date, now)}',
            excludeSemantics: true,
            onTap: _pickDate,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickDate,
              child: Container(
                constraints: const BoxConstraints(minHeight: LtSpace.touch + 8),
                padding: const EdgeInsets.symmetric(horizontal: LtSpace.s16),
                decoration: BoxDecoration(
                  color: c.bgGround,
                  borderRadius: LtRadius.smallAll,
                ),
                child: Row(
                  children: [
                    LtIcon(LtIcons.calendar, color: c.actionPrimary),
                    const SizedBox(width: LtSpace.s12),
                    Expanded(child: Text('Date', style: context.text.body)),
                    Text(
                      formatDay(_date, now),
                      style: context.text.body.copyWith(color: c.actionPrimary),
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
}
