/// The person's history on the phone: one entry per thing that happened (a finished
/// check-in, an onboarding or Mochi change, an Apple Health import, a day correction),
/// appended as it happens and never edited. Read it with `TwinRepository.history()`.
library;

/// Entry kinds.
abstract final class HistoryKind {
  static const quick = 'quick';
  static const daily = 'daily';
  static const weekly = 'weekly';
  static const onboarding = 'onboarding';
  static const mochiChange = 'mochi_change';
  static const healthImport = 'health_import';

  /// Reserved for document-upload confirmations (not built yet).
  static const document = 'document';

  /// A confirmed correction to a past day's answer, linked to the entry it corrects.
  static const correction = 'correction';

  /// A confirmed blood pressure reading (later also A1c or LDL from a document): dated
  /// information for the person and the coach, never a model input.
  static const reading = 'reading';

  static const checkins = {quick, daily, weekly};
}

/// Where the values came from.
abstract final class HistorySource {
  static const said = 'said';
  static const appleHealth = 'apple_health';
  static const document = 'document';
  static const mochiChange = 'mochi_change';

  static const all = {said, appleHealth, document, mochiChange};

  static String label(String source) => switch (source) {
    appleHealth => 'Apple Health',
    document => 'Document',
    mochiChange => 'Mochi change',
    _ => 'You said',
  };
}

/// Plain words and units for profile fields (a usual week or day).
const _profileWords = <String, (String, String)>{
  'age': ('age', 'years'),
  'sex': ('sex at birth', ''),
  'height_cm': ('height', 'cm'),
  'weight_kg': ('weight', 'kg'),
  'sleep_hours': ('sleep', 'hours a night'),
  'exercise_minutes_weekly': ('exercise', 'minutes a week'),
  'smoking_status': ('smoking', ''),
  'alcohol_drinks_weekly': ('alcohol', 'drinks a week'),
  'diabetes': ('diabetes', ''),
  'systolic_bp': ('blood pressure, top number', 'mmHg'),
  'diastolic_bp': ('blood pressure, bottom number', 'mmHg'),
  'general_health': ('how you rate your health', ''),
  'hypertension_diagnosed': ('told you have high blood pressure', ''),
  'sedentary_min_day': ('time sitting', 'minutes a day'),
  'moderate_recreation_min_week': ('easier activity', 'minutes a week'),
  'vigorous_recreation_min_week': ('activity that got you out of breath', 'minutes a week'),
  'wellbeing': ('how the week went', ''),
};

/// Plain words and units for one day's answers.
const _dayWords = <String, (String, String)>{
  'sleep_hours': ('sleep the night before', 'hours'),
  'sleep_hours_last_night': ('sleep last night', 'hours'),
  'sleep_hours_night_before': ('sleep the night before', 'hours'),
  'exercise_minutes_today': ('exercise', 'minutes'),
  'alcohol_drinks_yesterday': ('drinks the day before', 'drinks'),
  'vigorous_recreation_min': ('activity that got you out of breath', 'minutes'),
  'moderate_recreation_min': ('easier activity', 'minutes'),
  'sedentary_min_day': ('time sitting', 'minutes'),
  'wellbeing': ('how you felt', ''),
};

const _valueWords = {
  'never': 'never smoked',
  'former': 'used to smoke',
  'current': 'smokes now',
  'unknown': 'not sure',
  'excellent': 'excellent',
  'very_good': 'very good',
  'good': 'good',
  'fair': 'fair',
  'poor': 'poor',
  'okay': 'okay',
  'not_great': 'not great',
  'male': 'male',
  'female': 'female',
};
const _healthWords = ['excellent', 'very good', 'good', 'fair', 'poor'];

/// The value in plain words with its unit, e.g. "7.5 hours", "very good", "yes".
String valueText(String field, Object? value, {bool day = false}) {
  if (value == null) return '';
  final unit = ((day ? _dayWords[field] : null) ?? _profileWords[field] ?? _dayWords[field])?.$2 ?? '';
  if (field == 'general_health' && value is num && value >= 1 && value <= 5) return _healthWords[value.toInt() - 1];
  if (value is bool) return value ? 'yes' : 'no';
  if (value is num) {
    final n = value == value.roundToDouble()
        ? '${value.toInt()}'
        : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return unit.isEmpty ? n : '$n $unit';
  }
  return _valueWords['$value'] ?? '$value'.replaceAll('_', ' ');
}

String fieldLabel(String field, {bool day = false}) =>
    ((day ? _dayWords[field] : null) ?? _profileWords[field] ?? _dayWords[field])?.$1 ?? field.replaceAll('_', ' ');

/// One value in an entry: the field, its plain label, the value with units, and for a
/// change the old value too.
class HistoryItem {
  const HistoryItem({required this.field, required this.value, this.old, this.date, this.source});

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
    field: '${j['field']}',
    value: j['value'],
    old: j['old'],
    date: j['date'] as String?,
    source: j['source'] as String?,
  );

  /// The stored field name (profile or `daily_logs` name, or the check-in's answer name).
  final String field;
  final Object? value;

  /// The value before, when this replaced a known value; null otherwise.
  final Object? old;

  /// The day the value describes (a day-log value or a correction); null for a profile value.
  final String? date;

  /// Set when this value's source differs from its entry's (an Apple Health value in onboarding).
  final String? source;

  String get label => fieldLabel(field, day: date != null);
  String get unit => ((date != null ? _dayWords[field] : null) ?? _profileWords[field] ?? _dayWords[field])?.$2 ?? '';

  /// The value with units in plain words.
  String get text => valueText(field, value, day: date != null);
  String? get oldText => old == null ? null : valueText(field, old, day: date != null);

  /// A known value was replaced by a different one.
  bool get isChange => old != null && old != value;

  Map<String, dynamic> toJson() => {'field': field, 'value': value, 'old': ?old, 'date': ?date, 'source': ?source};
}

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.kind,
    required this.at,
    required this.source,
    required this.items,
    this.days = const [],
    this.weekStart,
    this.corrects,
    this.fedForecast,
    this.correctedBy,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    id: '${j['id']}',
    kind: '${j['kind']}',
    at: DateTime.parse('${j['at']}'),
    source: '${j['source']}',
    items: [
      for (final i in j['items'] as List? ?? const [])
        if (i is Map) HistoryItem.fromJson(Map<String, dynamic>.from(i)),
    ],
    days: [for (final d in j['days'] as List? ?? const []) '$d'],
    weekStart: j['week_start'] as String?,
    corrects: j['corrects'] as String?,
  );

  final String id;

  /// One of [HistoryKind].
  final String kind;

  /// The phone's local wall time when it happened (no time zone).
  final DateTime at;

  /// One of [HistorySource].
  final String source;
  final List<HistoryItem> items;

  /// Quick check-ins and day corrections: the days whose `daily_logs` row this wrote.
  final List<String> days;

  /// Weekly check-ins: the Monday of the week its summary describes, when its answers
  /// made a usable weekly summary.
  final String? weekStart;

  /// Corrections: the id of the entry corrected.
  final String? corrects;

  /// Worked out when read, not stored: `weekly_summaries` or `daily_logs` when this
  /// entry's values are in the window the current forecast used; null otherwise.
  final String? fedForecast;

  /// Worked out when read: the id of the latest correction of this entry, if any.
  final String? correctedBy;

  bool get corrected => correctedBy != null;

  /// The local date (YYYY-MM-DD) and time (HH:MM).
  String get date =>
      '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  String get time => '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  String get sourceLabel => HistorySource.label(source);

  HistoryEntry withStatus({String? fedForecast, String? correctedBy}) => HistoryEntry(
    id: id,
    kind: kind,
    at: at,
    source: source,
    items: items,
    days: days,
    weekStart: weekStart,
    corrects: corrects,
    fedForecast: fedForecast,
    correctedBy: correctedBy,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'at': at.toIso8601String(),
    'source': source,
    'items': [for (final i in items) i.toJson()],
    if (days.isNotEmpty) 'days': days,
    'week_start': ?weekStart,
    'corrects': ?corrects,
  };
}
