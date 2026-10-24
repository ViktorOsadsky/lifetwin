import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum Sex {
  female('Female'),
  male('Male'),
  unspecified('Prefer not to say');

  const Sex(this.label);
  final String label;
}

enum Smoking {
  never('Never'),
  former('Former'),
  current('Current');

  const Smoking(this.label);
  final String label;
}

/// What the user told Pip. Held on the device only, and kept separate from
/// the confirmed baseline, the workout log, experiments, cosmetics and quiz
/// health.
@immutable
class IntakeAnswers {
  const IntakeAnswers({
    this.age,
    this.sex,
    this.heightCm,
    this.weightKg,
    this.sleepHours,
    this.activityMinutes,
    this.smoking,
    this.drinksPerWeek,
  });

  final int? age;
  final Sex? sex;
  final double? heightCm;
  final double? weightKg;
  final double? sleepHours;
  final int? activityMinutes;
  final Smoking? smoking;
  final int? drinksPerWeek;

  bool get isComplete =>
      age != null &&
      sex != null &&
      heightCm != null &&
      weightKg != null &&
      sleepHours != null &&
      activityMinutes != null &&
      smoking != null &&
      drinksPerWeek != null;

  /// Returns a copy with only the given (non-null) fields replaced.
  IntakeAnswers copyWith({
    int? age,
    Sex? sex,
    double? heightCm,
    double? weightKg,
    double? sleepHours,
    int? activityMinutes,
    Smoking? smoking,
    int? drinksPerWeek,
  }) => IntakeAnswers(
    age: age ?? this.age,
    sex: sex ?? this.sex,
    heightCm: heightCm ?? this.heightCm,
    weightKg: weightKg ?? this.weightKg,
    sleepHours: sleepHours ?? this.sleepHours,
    activityMinutes: activityMinutes ?? this.activityMinutes,
    smoking: smoking ?? this.smoking,
    drinksPerWeek: drinksPerWeek ?? this.drinksPerWeek,
  );
}

class IntakeAnswersNotifier extends Notifier<IntakeAnswers> {
  @override
  IntakeAnswers build() => const IntakeAnswers();

  void set(IntakeAnswers answers) => state = answers;
}

final intakeAnswersProvider =
    NotifierProvider<IntakeAnswersNotifier, IntakeAnswers>(
      IntakeAnswersNotifier.new,
    );
