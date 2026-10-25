import 'dart:convert';
import 'dart:typed_data';

/// A safe reason for rejecting a file. Never includes file contents or identifiers.
class BandFileFailure implements Exception {
  const BandFileFailure(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

const bandFileMaxBytes = 5 * 1024 * 1024;
const _postures = [
  'sitting_or_lying',
  'standing',
  'walking_light',
  'walking_moderate',
  'running_vigorous',
  'other_posture',
  'not_worn',
  'positions_not_saved',
];
const _hourFields = [
  'sitting_lying_min',
  'standing_min',
  'walking_min',
  'running_min',
  'other_min',
  'not_worn_min',
];

/// The gadget's actual end-of-day format. These are observed estimates, not
/// questionnaire answers. In particular lying time is not awake sitting time.
class BandDayReport {
  BandDayReport._({
    required this.date,
    required this.offsetMinutes,
    required this.generatedAt,
    required this.mount,
    required this.firmware,
    required this.recordFormat,
    required this.recordedMinutes,
    required this.wearMinutes,
    required this.firstMinute,
    required this.lastMinute,
    required this.postures,
    required this.steps,
    required this.transitions,
    required this.longestSittingMinutes,
    required this.hourly,
    required this.notes,
    this.synthetic = false,
  });

  final DateTime date;
  final int offsetMinutes;
  final DateTime generatedAt;
  final String mount;
  final String firmware;
  final int recordFormat;
  final int recordedMinutes;
  final int wearMinutes;
  final String firstMinute;
  final String lastMinute;
  final Map<String, int> postures;
  final int steps;
  final int transitions;
  final int longestSittingMinutes;
  final List<Map<String, int>> hourly;

  /// Untrusted descriptive metadata; never executed or sent to a provider.
  final List<String> notes;
  final bool synthetic;
  String get day => date.toIso8601String().substring(0, 10);
  bool get validDay => wearMinutes >= 600;
  int get classifiedWearMinutes =>
      wearMinutes - postures['positions_not_saved']!;
  int get observedModerateMinutes => postures['walking_moderate']!;
  int get observedVigorousMinutes => postures['running_vigorous']!;
  int get observedSittingOrLyingMinutes => postures['sitting_or_lying']!;
  int get observedMvpaMinutes =>
      observedModerateMinutes + observedVigorousMinutes;
  int? get moderateMinutes => validDay ? observedModerateMinutes : null;
  int? get vigorousMinutes => validDay ? observedVigorousMinutes : null;

  /// This is the sensor's combined sitting/lying category, not model sitting.
  int? get sittingOrLyingMinutes =>
      validDay ? observedSittingOrLyingMinutes : null;

  /// Normalized comparison for idempotent import. It stays only in phone memory.
  String get contentKey => jsonEncode([
    day,
    offsetMinutes,
    mount,
    firmware,
    recordFormat,
    recordedMinutes,
    wearMinutes,
    firstMinute,
    lastMinute,
    [for (final key in _postures) postures[key]],
    steps,
    transitions,
    longestSittingMinutes,
    [
      for (final h in hourly)
        [h['hour'], for (final key in _hourFields) h[key], h['steps']],
    ],
    synthetic,
  ]);

  static BandDayReport fromJson(Object? value) {
    final root = _object(value, 'The band file must contain an object.');
    if (root['schema'] != 'lifetwin.band_day.v0') {
      throw const BandFileFailure('This band file version is not supported.');
    }
    final dayText = _text(root['date'], 'date', 10);
    final date = _date(dayText);
    final offset = _integer(
      root['timezone_offset_minutes'],
      'time-zone offset',
      -840,
      840,
    );
    final generated = _text(root['generated_at'], 'export time', 40);
    if (!RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
        ).hasMatch(generated) ||
        DateTime.tryParse(generated) == null) {
      throw const BandFileFailure(
        'The export time needs a valid date and UTC offset.',
      );
    }
    // DateTime.parse normalizes invalid dates. Validate the written calendar too.
    _date(generated.substring(0, 10));
    if (!generated.endsWith('Z')) {
      final zone = generated.substring(generated.length - 6);
      final hours = int.parse(zone.substring(1, 3));
      final minutes = int.parse(zone.substring(4, 6));
      if (hours > 14 ||
          minutes > 59 ||
          hours == 14 && minutes != 0 ||
          zone == '-00:00') {
        throw const BandFileFailure('The export UTC offset is not valid.');
      }
    }
    final dayStartUtc = date.subtract(Duration(minutes: offset));
    if (DateTime.parse(generated).isBefore(dayStartUtc)) {
      throw const BandFileFailure(
        'The export time is earlier than the day it reports on.',
      );
    }
    final clockPart = generated.substring(11, 19);
    if (int.parse(clockPart.substring(0, 2)) > 23 ||
        int.parse(clockPart.substring(3, 5)) > 59 ||
        int.parse(clockPart.substring(6, 8)) > 59) {
      throw const BandFileFailure('The export time is not valid.');
    }
    final device = _object(
      root['device'],
      'The band device information is missing.',
    );
    final coverage = _object(
      root['coverage'],
      'The band coverage information is missing.',
    );
    final recorded = _integer(
      coverage['minutes_recorded'],
      'recorded minutes',
      0,
      1440,
    );
    final worn = _integer(
      coverage['wear_minutes'],
      'wear minutes',
      0,
      recorded,
    );
    if (coverage['valid_day'] is! bool ||
        coverage['valid_day'] != (worn >= 600)) {
      throw const BandFileFailure(
        'The valid-day flag does not match wear time.',
      );
    }
    final first = _clock(coverage['first_minute']);
    final last = _clock(coverage['last_minute']);
    if (first.compareTo(last) > 0) {
      throw const BandFileFailure(
        'A daily report cannot cross midnight; export separate dated days.',
      );
    }
    final windowMinutes =
        (int.parse(last.substring(0, 2)) * 60 + int.parse(last.substring(3))) -
        (int.parse(first.substring(0, 2)) * 60 +
            int.parse(first.substring(3))) +
        1;
    if (recorded > windowMinutes) {
      throw const BandFileFailure(
        'The recorded minutes are more than the first-to-last coverage window.',
      );
    }
    final minutes = _object(
      root['minutes'],
      'The daily minute totals are missing.',
    );
    final postures = {
      for (final key in _postures) key: _integer(minutes[key], key, 0, 1440),
    };
    if (postures.values.fold<int>(0, (a, b) => a + b) != recorded ||
        recorded - postures['not_worn']! != worn) {
      throw const BandFileFailure(
        'Daily categories do not match recorded and wear time.',
      );
    }
    if (_integer(
          root['moderate_vigorous_minutes'],
          'active minutes',
          0,
          1440,
        ) !=
        postures['walking_moderate']! + postures['running_vigorous']!) {
      throw const BandFileFailure(
        'The active-minute total does not match its categories.',
      );
    }
    final rawHours = root['hourly'];
    if (rawHours is! List || rawHours.length != 24) {
      throw const BandFileFailure(
        'A daily report needs exactly 24 different hourly bins.',
      );
    }
    final hours = <Map<String, int>>[];
    final seen = <int>{};
    for (final raw in rawHours) {
      final hour = _object(raw, 'An hourly bin is malformed.');
      final index = _integer(hour['hour'], 'hour', 0, 23);
      if (!seen.add(index)) {
        throw const BandFileFailure('The file repeats an hour.');
      }
      final row = {
        'hour': index,
        for (final key in _hourFields) key: _integer(hour[key], key, 0, 60),
        'steps': _integer(hour['steps'], 'hourly steps', 0, 24000),
      };
      if (_hourFields.fold<int>(0, (a, k) => a + row[k]!) > 60) {
        throw const BandFileFailure(
          'An hourly bin contains more than 60 minutes.',
        );
      }
      hours.add(Map.unmodifiable(row));
    }
    hours.sort((a, b) => a['hour']!.compareTo(b['hour']!));
    int total(String key) => hours.fold<int>(0, (a, h) => a + h[key]!);
    for (final entry in {
      'sitting_or_lying': 'sitting_lying_min',
      'standing': 'standing_min',
      'running_vigorous': 'running_min',
      'other_posture': 'other_min',
      'not_worn': 'not_worn_min',
    }.entries) {
      if (postures[entry.key] != total(entry.value)) {
        throw const BandFileFailure('Hourly and daily categories disagree.');
      }
    }
    if (postures['walking_light']! + postures['walking_moderate']! !=
        total('walking_min')) {
      throw const BandFileFailure('Hourly and daily walking totals disagree.');
    }
    final steps = _integer(root['steps'], 'steps', 0, 576000);
    if (steps != total('steps')) {
      throw const BandFileFailure('Hourly and daily step totals disagree.');
    }
    final notes = root['notes'];
    if (notes is! List ||
        notes.length > 20 ||
        notes.any((n) => n is! String || n.length > 500)) {
      throw const BandFileFailure('The report notes are malformed.');
    }
    if (root['synthetic_demo'] != null && root['synthetic_demo'] is! bool) {
      throw const BandFileFailure('The demo flag is malformed.');
    }
    return BandDayReport._(
      date: date,
      offsetMinutes: offset,
      generatedAt: DateTime.parse(generated),
      mount: _text(device['mount'], 'sensor placement', 80),
      firmware: _text(device['firmware'], 'firmware version', 80),
      recordFormat: _integer(
        device['record_format'],
        'firmware record format',
        1,
        1000,
      ),
      recordedMinutes: recorded,
      wearMinutes: worn,
      firstMinute: first,
      lastMinute: last,
      postures: Map.unmodifiable(postures),
      steps: steps,
      transitions: _integer(
        root['sit_to_stand_transitions'],
        'posture transitions',
        0,
        1440,
      ),
      longestSittingMinutes: _integer(
        root['longest_sitting_minutes'],
        'longest sitting interval',
        0,
        postures['sitting_or_lying']!,
      ),
      hourly: List.unmodifiable(hours),
      notes: List.unmodifiable(notes.cast<String>()),
      synthetic: root['synthetic_demo'] == true,
    );
  }
}

/// One native delivery can contain a day or an explicit bundle of whole days.
/// No minute-level records are reconstructed from hourly aggregates.
List<BandDayReport> parseBandFile(Uint8List bytes) {
  if (bytes.length > bandFileMaxBytes) {
    throw const BandFileFailure('Choose a band file smaller than 5 MB.');
  }
  try {
    final value = jsonDecode(utf8.decode(bytes));
    final Object? rawDays =
        value is Map && value['schema'] == 'lifetwin.band_days.v0'
        ? value['days']
        : [value];
    if (rawDays is! List || rawDays.isEmpty || rawDays.length > 14) {
      throw const BandFileFailure(
        'Import between 1 and 14 dated band reports.',
      );
    }
    final reports = rawDays.map(BandDayReport.fromJson).toList();
    final dates = <String>{};
    for (final report in reports) {
      if (!dates.add(report.day)) {
        throw const BandFileFailure('The file repeats a date.');
      }
    }
    reports.sort((a, b) => a.date.compareTo(b.date));
    return List.unmodifiable(reports);
  } on BandFileFailure {
    rethrow;
  } on FormatException {
    throw const BandFileFailure('This is not a readable JSON band file.');
  }
}

Map<String, dynamic> _object(Object? value, String error) {
  if (value is! Map<String, dynamic>) throw BandFileFailure(error);
  return value;
}

int _integer(Object? value, String field, int min, int max) {
  if (value is! int || value < min || value > max) {
    throw BandFileFailure('The $field value is missing or out of range.');
  }
  return value;
}

String _text(Object? value, String field, int max) {
  if (value is! String ||
      value.isEmpty ||
      value.length > max ||
      value.contains(RegExp(r'[\x00-\x1f]'))) {
    throw BandFileFailure('The $field value is missing or malformed.');
  }
  return value;
}

DateTime _date(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const BandFileFailure('The report date is malformed.');
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
    throw const BandFileFailure('The report date is not a real calendar day.');
  }
  return parsed;
}

String _clock(Object? value) {
  final s = _text(value, 'coverage time', 5);
  if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(s)) {
    throw const BandFileFailure('Coverage times must use HH:MM.');
  }
  return s;
}
