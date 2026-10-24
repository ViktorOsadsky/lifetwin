import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'confirmed_baseline.dart';
import 'intake_answers.dart';

/// The two inputs an experiment can change.
@immutable
class ExperimentInputs {
  const ExperimentInputs({
    required this.activityMinutes,
    required this.sleepHours,
  });

  final int activityMinutes;
  final int sleepHours;

  ExperimentInputs copyWith({int? activityMinutes, int? sleepHours}) =>
      ExperimentInputs(
        activityMinutes: activityMinutes ?? this.activityMinutes,
        sleepHours: sleepHours ?? this.sleepHours,
      );

  @override
  bool operator ==(Object other) =>
      other is ExperimentInputs &&
      other.activityMinutes == activityMinutes &&
      other.sleepHours == sleepHours;

  @override
  int get hashCode => Object.hash(activityMinutes, sleepHours);
}

/// The baseline values an experiment starts from, read-only here. When the
/// user has not given real values yet, a clearly flagged sample is used.
@immutable
class BaselineInputs {
  const BaselineInputs({required this.inputs, required this.isSample});

  final ExperimentInputs inputs;
  final bool isSample;
}

enum ChangeKind { activity, sleep }

/// One bounded, single change a plan item asks the user to try on the twin.
@immutable
class AssumedChange {
  const AssumedChange({required this.kind, required this.delta});

  final ChangeKind kind;
  final int delta;

  String get inputLabel => switch (kind) {
    ChangeKind.activity => 'Active minutes',
    ChangeKind.sleep => 'Sleep',
  };

  String get unit => switch (kind) {
    ChangeKind.activity => 'min / week',
    ChangeKind.sleep => 'h / night',
  };

  int valueIn(ExperimentInputs i) => switch (kind) {
    ChangeKind.activity => i.activityMinutes,
    ChangeKind.sleep => i.sleepHours,
  };

  ExperimentInputs applyTo(ExperimentInputs i) => switch (kind) {
    ChangeKind.activity => i.copyWith(
      activityMinutes: i.activityMinutes + delta,
    ),
    ChangeKind.sleep => i.copyWith(sleepHours: i.sleepHours + delta),
  };
}

const sampleBaseline = ExperimentInputs(activityMinutes: 30, sleepHours: 7);

final baselineInputsProvider = Provider<BaselineInputs>((ref) {
  final confirmed = ref.watch(confirmedBaselineProvider);
  final answers = ref.watch(intakeAnswersProvider);
  final activity = confirmed.activityMinutesPerWeek ?? answers.activityMinutes;
  final sleep = answers.sleepHours?.round();
  return BaselineInputs(
    inputs: ExperimentInputs(
      activityMinutes: activity ?? sampleBaseline.activityMinutes,
      sleepHours: sleep ?? sampleBaseline.sleepHours,
    ),
    isSample: activity == null && sleep == null,
  );
});

/// Hypothetical inputs for the Experiment screen. `null` means "same as
/// baseline". This state never writes to the baseline; Reset only clears it.
class ExperimentNotifier extends Notifier<ExperimentInputs?> {
  @override
  ExperimentInputs? build() => null;

  ExperimentInputs get _current =>
      state ?? ref.read(baselineInputsProvider).inputs;

  void setActivity(int minutes) =>
      state = _current.copyWith(activityMinutes: minutes);

  void setSleep(int hours) => state = _current.copyWith(sleepHours: hours);

  /// Starts an experiment from the baseline with one assumed change.
  void apply(AssumedChange change) =>
      state = change.applyTo(ref.read(baselineInputsProvider).inputs);

  void reset() => state = null;
}

final experimentProvider =
    NotifierProvider<ExperimentNotifier, ExperimentInputs?>(
      ExperimentNotifier.new,
    );
