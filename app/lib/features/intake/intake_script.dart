import '../../state/intake_answers.dart';

/// The scripted, local question sequence. No network and no model: Pip asks
/// one thing at a time and reads the reply with plain rules.
enum IntakeField {
  age(
    label: 'Age',
    question: 'First, how old are you?',
    hint: 'Your age in years',
    unit: 'years',
    min: 18,
    max: 110,
  ),
  sex(
    label: 'Sex',
    question: 'Thanks! Which sex should I use for your twin?',
    hint: 'Female, male or prefer not to say',
    quickReplies: ['Female', 'Male', 'Prefer not to say'],
  ),
  height(
    label: 'Height',
    question: 'How tall are you?',
    hint: 'For example 170 cm or 5 ft 10',
    unit: 'cm',
    min: 100,
    max: 230,
    units: ['cm', 'in'],
  ),
  weight(
    label: 'Weight',
    question: 'And your weight?',
    hint: 'For example 70 kg or 154 lb',
    unit: 'kg',
    min: 30,
    max: 300,
    units: ['kg', 'lb'],
  ),
  sleep(
    label: 'Sleep',
    question: 'On a usual night, how many hours do you sleep?',
    hint: 'Hours per night, like 7 or 7.5',
    unit: 'h / night',
    min: 2,
    max: 14,
  ),
  activity(
    label: 'Activity',
    question: 'How many minutes of exercise do you get in a usual week?',
    hint: 'Minutes per week, 0 is fine',
    unit: 'min / week',
    min: 0,
    max: 2000,
  ),
  smoking(
    label: 'Smoking',
    question: 'Do you smoke?',
    hint: 'Never, former or current',
    quickReplies: ['Never', 'Former', 'Current'],
  ),
  drinks(
    label: 'Drinks',
    question: 'Last one: how many alcoholic drinks in a usual week?',
    hint: 'Drinks per week, 0 is fine',
    unit: 'per week',
    min: 0,
    max: 100,
  );

  const IntakeField({
    required this.label,
    required this.question,
    required this.hint,
    this.unit = '',
    this.min = 0,
    this.max = 0,
    this.quickReplies = const [],
    this.units = const [],
  });

  final String label;
  final String question;
  final String hint;
  final String unit;
  final double min;
  final double max;
  final List<String> quickReplies;

  /// Non-empty when the reply may need a "which unit?" follow-up.
  final List<String> units;

  bool get isNumeric => quickReplies.isEmpty;
}

sealed class IntakeResult {
  const IntakeResult();
}

/// Reply understood; [answers] holds the new state.
class Accepted extends IntakeResult {
  const Accepted(this.answers);
  final IntakeAnswers answers;
}

/// A number without a unit; Pip asks "cm or inches?".
class NeedsUnit extends IntakeResult {
  const NeedsUnit(this.value);
  final double value;
}

/// Not understood; [message] is what Pip says before asking again.
class Retry extends IntakeResult {
  const Retry(this.message);
  final String message;
}

final _number = RegExp(r'\d+(?:\.\d+)?');

double? _firstNumber(String text) {
  final m = _number.firstMatch(text);
  return m == null ? null : double.parse(m.group(0)!);
}

String unitQuestion(IntakeField field) => switch (field) {
  IntakeField.height => 'Is that cm or inches?',
  IntakeField.weight => 'Is that kg or pounds?',
  _ => 'Which unit?',
};

String _outOfRange(IntakeField f) =>
    'Hmm, that looks outside the range I can use (${f.min.round()} to '
    '${f.max.round()} ${f.unit}). Could you say it again?';

/// Reads [text] as the answer to [field].
IntakeResult interpret(IntakeField field, String text, IntakeAnswers a) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return const Retry('I did not catch that.');
  switch (field) {
    case IntakeField.age:
      final n = _firstNumber(t);
      if (n == null) return const Retry('I need a number for your age.');
      if (n < 18) {
        return const Retry(
          'LifeTwin outlooks are for adults aged 18 and over, so I cannot '
          'read an age under 18. Could you check it?',
        );
      }
      if (n > field.max) return Retry(_outOfRange(field));
      return Accepted(a.copyWith(age: n.round()));
    case IntakeField.sex:
      final s = t.contains('prefer') || t.contains('rather not')
          ? Sex.unspecified
          : (t.contains('female') || t.contains('woman') || t == 'f')
          ? Sex.female
          : (t.contains('male') || t.contains('man') || t == 'm')
          ? Sex.male
          : null;
      if (s == null) {
        return const Retry('Please pick female, male or prefer not to say.');
      }
      return Accepted(a.copyWith(sex: s));
    case IntakeField.height:
      final feet = RegExp(r"(\d+)\s*(?:'|ft|feet|foot)\s*(\d+)?").firstMatch(t);
      if (feet != null) {
        final cm =
            (int.parse(feet.group(1)!) * 12 + int.parse(feet.group(2) ?? '0')) *
            2.54;
        return _checked(field, cm, (v) => a.copyWith(heightCm: v));
      }
      final n = _firstNumber(t);
      if (n == null) return const Retry('I need a number for your height.');
      if (t.contains('cm') || t.contains('centi')) {
        return _checked(field, n, (v) => a.copyWith(heightCm: v));
      }
      if (t.contains('in') || t.contains('"')) {
        return _checked(field, n * 2.54, (v) => a.copyWith(heightCm: v));
      }
      return NeedsUnit(n);
    case IntakeField.weight:
      final n = _firstNumber(t);
      if (n == null) return const Retry('I need a number for your weight.');
      if (t.contains('kg') || t.contains('kilo')) {
        return _checked(field, n, (v) => a.copyWith(weightKg: v));
      }
      if (t.contains('lb') || t.contains('pound')) {
        return _checked(field, n * 0.45359237, (v) => a.copyWith(weightKg: v));
      }
      return NeedsUnit(n);
    case IntakeField.sleep:
      final n = _firstNumber(t);
      if (n == null) return const Retry('I need a number of hours.');
      return _checked(field, n, (v) => a.copyWith(sleepHours: v));
    case IntakeField.activity:
      final n = t.contains('none') || t.contains('zero')
          ? 0.0
          : _firstNumber(t);
      if (n == null) return const Retry('I need a number of minutes.');
      return _checked(field, n, (v) => a.copyWith(activityMinutes: v.round()));
    case IntakeField.smoking:
      final s =
          t.contains('never') ||
              t.contains("don't") ||
              t.contains('do not') ||
              t == 'no' ||
              t.startsWith('non')
          ? Smoking.never
          : (t.contains('former') ||
                t.contains('quit') ||
                t.contains('used to') ||
                t.startsWith('ex'))
          ? Smoking.former
          : (t.contains('current') ||
                t.contains('yes') ||
                t.contains('smoke') ||
                t.contains('daily'))
          ? Smoking.current
          : null;
      if (s == null) {
        return const Retry('Please pick never, former or current.');
      }
      return Accepted(a.copyWith(smoking: s));
    case IntakeField.drinks:
      final n = t.contains('none') || t.contains('zero')
          ? 0.0
          : _firstNumber(t);
      if (n == null) return const Retry('I need a number of drinks.');
      return _checked(field, n, (v) => a.copyWith(drinksPerWeek: v.round()));
  }
}

/// Reads the answer to "cm or inches?" / "kg or pounds?" for [value].
IntakeResult resolveUnit(
  IntakeField field,
  double value,
  String text,
  IntakeAnswers a,
) {
  final t = text.trim().toLowerCase();
  if (field == IntakeField.height) {
    if (t.contains('cm') || t.contains('centi')) {
      return _checked(field, value, (v) => a.copyWith(heightCm: v));
    }
    if (t.startsWith('in') || t.contains('inch')) {
      return _checked(field, value * 2.54, (v) => a.copyWith(heightCm: v));
    }
    return const Retry('Please say cm or inches.');
  }
  if (t.contains('kg') || t.contains('kilo')) {
    return _checked(field, value, (v) => a.copyWith(weightKg: v));
  }
  if (t.contains('lb') || t.contains('pound')) {
    return _checked(field, value * 0.45359237, (v) => a.copyWith(weightKg: v));
  }
  return const Retry('Please say kg or pounds.');
}

IntakeResult _checked(
  IntakeField field,
  double value,
  IntakeAnswers Function(double) build,
) {
  if (value < field.min || value > field.max) return Retry(_outOfRange(field));
  return Accepted(build(value));
}

/// Display text for a confirmed field, or null when unanswered.
String? formatField(IntakeField field, IntakeAnswers a) {
  String num(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
  return switch (field) {
    IntakeField.age => a.age == null ? null : '${a.age} years',
    IntakeField.sex => a.sex?.label,
    IntakeField.height => a.heightCm == null ? null : '${num(a.heightCm!)} cm',
    IntakeField.weight => a.weightKg == null ? null : '${num(a.weightKg!)} kg',
    IntakeField.sleep =>
      a.sleepHours == null ? null : '${num(a.sleepHours!)} h / night',
    IntakeField.activity =>
      a.activityMinutes == null ? null : '${a.activityMinutes} min / week',
    IntakeField.smoking => a.smoking?.label,
    IntakeField.drinks =>
      a.drinksPerWeek == null ? null : '${a.drinksPerWeek} per week',
  };
}
