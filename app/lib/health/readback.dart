import 'health_summary.dart';

/// Plain-language read-back. Every sentence ends by asking whether it is accurate.
///
/// Values are rounded only for speaking; the exact metric value is what gets
/// confirmed. US users hear feet, inches and pounds.
String readBack(HealthCandidate c, {required bool imperial, required DateTime now}) {
  final when = c.measuredAt != null ? ' That was measured on ${spokenDate(c.measuredAt!, now)}.' : '';
  final said = switch (c.field) {
    HealthField.heightCm => 'you are ${spokenHeight(c.value, imperial: imperial)} tall',
    HealthField.weightKg => 'you weigh about ${spokenWeight(c.value, imperial: imperial)}',
    HealthField.exerciseMinutesWeekly =>
      'you exercise about ${spokenDuration(c.value)} a week, on average over the last 4 weeks',
    HealthField.sleepHours => 'you sleep about ${spokenDuration(c.value * 60)} on a typical night',
    HealthField.systolicBp => 'the top number of your blood pressure is about ${c.value}',
    HealthField.diastolicBp => 'the bottom number of your blood pressure is about ${c.value}',
  };
  return "Your iPhone's Health app says $said.$when Is this accurate?";
}

const confirmLabel = "Yes, that's right";
const fixLabel = 'No, let me fix it';

/// Countries that use pounds and feet in everyday speech.
bool usesImperial(String? countryCode) => const {'US', 'LR', 'MM'}.contains(countryCode?.toUpperCase());

String spokenHeight(num cm, {required bool imperial}) {
  if (!imperial) return '${cm.round()} centimeters';
  final totalInches = (cm / 2.54).round();
  final feet = totalInches ~/ 12, inches = totalInches % 12;
  return inches == 0 ? '$feet feet' : '$feet feet $inches ${inches == 1 ? 'inch' : 'inches'}';
}

String spokenWeight(num kg, {required bool imperial}) =>
    imperial ? '${(kg * 2.20462).round()} pounds' : '${kg.round()} kilograms';

/// "45 minutes", "1 hour", "2 and a half hours".
String spokenDuration(num minutes) {
  if (minutes < 60) {
    final m = minutes < 10 ? minutes.round() : (minutes / 5).round() * 5;
    return '$m ${m == 1 ? 'minute' : 'minutes'}';
  }
  final halves = (minutes / 30).round();
  final whole = halves ~/ 2;
  final half = halves.isOdd;
  if (whole == 0) return 'half an hour';
  final unit = whole == 1 && !half ? 'hour' : 'hours';
  return half ? '$whole and a half hours' : '$whole $unit';
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "March 3", or "March 3, 2025" when it isn't this year.
String spokenDate(DateTime d, DateTime now) {
  final l = d.toLocal();
  final base = '${_months[l.month - 1]} ${l.day}';
  return l.year == now.toLocal().year ? base : '$base, ${l.year}';
}
