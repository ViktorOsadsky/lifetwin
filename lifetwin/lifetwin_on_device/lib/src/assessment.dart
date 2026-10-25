import 'model.dart';

const _activitySource =
    'https://www.cdc.gov/physical-activity-basics/guidelines/adults.html';
const _sleepSource = 'https://www.cdc.gov/sleep/about/index.html';
const _smokingSource = 'https://www.cdc.gov/tobacco/about/';
const _bmiSource = 'https://www.cdc.gov/bmi/about/';

double _number(Map<String, dynamic> row, String key, double low, double high) {
  final value = row[key];
  if (value is! num || !value.isFinite)
    throw FormatException('$key must be a finite number');
  if (value < low || value > high)
    throw FormatException('$key must be between $low and $high');
  return value.toDouble();
}

DateTime _date(dynamic value, String key) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw FormatException('$key must be an ISO date, YYYY-MM-DD');
  }
  final year = int.parse(value.substring(0, 4));
  final month = int.parse(value.substring(5, 7));
  final day = int.parse(value.substring(8, 10));
  final result = DateTime.utc(year, month, day);
  if (result.year != year || result.month != month || result.day != day) {
    throw FormatException('$key is not a valid date');
  }
  return result;
}

String _iso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

typedef _Aggregation = ({
  Map<String, double> behavior,
  Map<String, dynamic> context,
});

_Aggregation _daily(List<dynamic> logs, DateTime asOf) {
  if (![7, 14, 21, 28].contains(logs.length)) {
    throw const FormatException(
      'daily_logs must contain 7, 14, 21, or 28 complete days',
    );
  }
  final rows = logs.map((row) => Map<String, dynamic>.from(row as Map)).toList()
    ..sort((a, b) => a['date'].toString().compareTo(b['date'].toString()));
  final dates = rows.map((row) => _date(row['date'], 'date')).toList();
  if (dates.toSet().length != dates.length ||
      dates.last != asOf.subtract(const Duration(days: 1))) {
    throw const FormatException(
      'daily_logs must have unique dates and end yesterday',
    );
  }
  for (var i = 0; i < dates.length; i++) {
    if (dates[i] != dates.first.add(Duration(days: i))) {
      throw const FormatException('daily_logs must have no missing dates');
    }
  }
  var vigorous = 0.0, moderate = 0.0, sitting = 0.0;
  final workdaySleep = <double>[];
  final weekSitting = <double>[];
  for (var block = 0; block < rows.length ~/ 7; block++) {
    var blockSitting = 0.0;
    for (final row in rows.skip(block * 7).take(7)) {
      final sleep = _number(row, 'sleep_hours', 2, 12);
      final sit = _number(row, 'sedentary_min_day', 0, 1439);
      final vig = _number(row, 'vigorous_recreation_min', 0, 1440);
      final mod = _number(row, 'moderate_recreation_min', 0, 1440);
      if (row['workday'] is! bool) {
        throw const FormatException(
          'workday must be true or false for each daily log',
        );
      }
      if (sleep * 60 + sit + vig + mod > 1440) {
        throw const FormatException(
          'A daily log has more than 24 hours of sleep, sitting and recreation',
        );
      }
      if (row['workday'] == true) workdaySleep.add(sleep);
      vigorous += vig;
      moderate += mod;
      sitting += sit;
      blockSitting += sit / 7;
    }
    weekSitting.add(blockSitting);
  }
  final weeks = rows.length ~/ 7;
  if (workdaySleep.length < 3 * weeks) {
    throw const FormatException(
      'At least three workday sleep observations per week are required',
    );
  }
  double total(Iterable<double> values) =>
      values.fold(0.0, (sum, value) => sum + value);
  return (
    behavior: {
      'sleep_hours': total(workdaySleep) / workdaySleep.length,
      'vigorous_recreation_min_week': vigorous / weeks,
      'moderate_recreation_min_week': moderate / weeks,
      'sedentary_min_day': sitting / rows.length,
    },
    context: {
      'source': 'daily_logs',
      'window_start': _iso(dates.first),
      'window_end': _iso(dates.last),
      'complete_weeks': weeks,
      'workday_sleep_observations': workdaySleep.length,
      'sitting_first_week': weekSitting.first,
      'sitting_last_week': weekSitting.last,
    },
  );
}

_Aggregation _weekly(List<dynamic> logs, DateTime asOf) {
  if (logs.isEmpty || logs.length > 4) {
    throw const FormatException(
      'weekly_summaries must contain one to four complete weeks',
    );
  }
  final rows = logs.map((row) => Map<String, dynamic>.from(row as Map)).toList()
    ..sort(
      (a, b) =>
          a['week_start'].toString().compareTo(b['week_start'].toString()),
    );
  final starts = rows
      .map((row) => _date(row['week_start'], 'week_start'))
      .toList();
  final latestMonday = asOf.subtract(Duration(days: asOf.weekday + 6));
  if (starts.toSet().length != starts.length || starts.last != latestMonday) {
    throw const FormatException(
      'weekly_summaries must end with the latest completed Monday–Sunday week',
    );
  }
  for (var i = 0; i < starts.length; i++) {
    if (starts[i].weekday != DateTime.monday ||
        starts[i] != starts.first.add(Duration(days: i * 7))) {
      throw const FormatException(
        'weekly_summaries must be consecutive Monday–Sunday weeks',
      );
    }
  }
  final fields = <String>[
    'sleep_hours',
    'vigorous_recreation_min_week',
    'moderate_recreation_min_week',
    'sedentary_min_day',
  ];
  final values = {for (final field in fields) field: <double>[]};
  for (final row in rows) {
    values['sleep_hours']!.add(_number(row, 'sleep_hours', 2, 12));
    values['vigorous_recreation_min_week']!.add(
      _number(row, 'vigorous_recreation_min_week', 0, 10073),
    );
    values['moderate_recreation_min_week']!.add(
      _number(row, 'moderate_recreation_min_week', 0, 10073),
    );
    values['sedentary_min_day']!.add(
      _number(row, 'sedentary_min_day', 0, 1439),
    );
    if (values['sleep_hours']!.last * 60 +
            values['sedentary_min_day']!.last +
            (values['vigorous_recreation_min_week']!.last +
                    values['moderate_recreation_min_week']!.last) /
                7 >
        1440) {
      throw const FormatException(
        'A weekly summary exceeds the time available in a day',
      );
    }
  }
  final behavior = <String, double>{};
  for (final field in fields) {
    behavior[field] =
        values[field]!.fold(0.0, (double sum, double v) => sum + v) /
        rows.length;
  }
  return (
    behavior: behavior,
    context: {
      'source': 'weekly_summaries',
      'window_start': _iso(starts.first),
      'window_end': _iso(starts.last.add(const Duration(days: 6))),
      'complete_weeks': rows.length,
      'sitting_first_week': values['sedentary_min_day']!.first,
      'sitting_last_week': values['sedentary_min_day']!.last,
    },
  );
}

Map<String, dynamic> _card(
  String id,
  String level,
  String title,
  String message,
  String source,
) => {
  'id': id,
  'level': level,
  'title': title,
  'message': message,
  'source_url': source,
  'derived_from_survival_model': false,
};

List<Map<String, dynamic>> _guidance(
  Map<String, dynamic> profile,
  Map<String, dynamic> context,
) {
  final age = profile['age'];
  if (age is! num || age < 18) {
    return [
      _card(
        'adult_guidance_scope',
        'info',
        'Adult guidance unavailable',
        'The bundled wellness rules are for adults; use age-appropriate guidance instead.',
        _activitySource,
      ),
    ];
  }
  final cards = <Map<String, dynamic>>[];
  final smoking = profile['smoking_status'];
  if (smoking == 2) {
    cards.add(
      _card(
        'smoking',
        'opportunity',
        'Smoking',
        'Quitting cigarettes benefits health at any age. Consider evidence-based quit support.',
        _smokingSource,
      ),
    );
  } else if (smoking == 0 || smoking == 1) {
    cards.add(
      _card(
        'smoking',
        'strength',
        'Not currently smoking',
        'You report that you do not currently smoke cigarettes.',
        _smokingSource,
      ),
    );
  }
  final moderate = profile['moderate_recreation_min_week'];
  final vigorous = profile['vigorous_recreation_min_week'];
  if (moderate is num && vigorous is num) {
    final equivalent = moderate + 2 * vigorous;
    if (equivalent >= 150) {
      cards.add(
        _card(
          'activity',
          'strength',
          'Recreational activity',
          'Your logged moderate and vigorous recreation meets the adult aerobic activity minimum of 150 moderate-equivalent minutes per week. Other activity and strength training are not captured here.',
          _activitySource,
        ),
      );
    } else {
      cards.add(
        _card(
          'activity',
          'opportunity',
          'Recreational activity',
          'Your logged recreation is about ${equivalent.toStringAsFixed(0)} moderate-equivalent minutes per week. Adults are advised to aim for at least 150; work and transport activity are not captured here.',
          _activitySource,
        ),
      );
    }
  }
  final sleep = profile['sleep_hours'];
  if (sleep is num) {
    final maximum = age >= 65
        ? 8
        : age >= 61
        ? 9
        : null;
    if (sleep < 7) {
      cards.add(
        _card(
          'sleep',
          'opportunity',
          'Sleep',
          'Your usual workday sleep is ${sleep.toStringAsFixed(1)} hours. CDC recommends at least seven hours for adults.',
          _sleepSource,
        ),
      );
    } else if (maximum != null && sleep > maximum) {
      cards.add(
        _card(
          'sleep',
          'info',
          'Sleep pattern',
          'Your usual workday sleep is ${sleep.toStringAsFixed(1)} hours; CDC lists 7–$maximum hours for your age group. Persistent changes in sleep can be discussed with a clinician.',
          _sleepSource,
        ),
      );
    } else {
      cards.add(
        _card(
          'sleep',
          'strength',
          'Sleep duration',
          'Your usual workday sleep meets the CDC duration recommendation for your age group. Sleep quality is not measured here.',
          _sleepSource,
        ),
      );
    }
  }
  if ((context['complete_weeks'] ?? 0) >= 2) {
    final change =
        (context['sitting_last_week'] as num) -
        (context['sitting_first_week'] as num);
    if (change <= -60) {
      cards.add(
        _card(
          'sitting_trend',
          'strength',
          'Less sitting',
          'Your logged awake sitting time decreased by at least an hour per day from the first to the latest week.',
          _activitySource,
        ),
      );
    } else if (change >= 60) {
      cards.add(
        _card(
          'sitting_trend',
          'opportunity',
          'More sitting',
          'Your logged awake sitting time increased by at least an hour per day from the first to the latest week. Moving more and sitting less is generally recommended.',
          _activitySource,
        ),
      );
    }
  }
  if (!cards.any((card) => card['id'] == 'sitting_trend') &&
      profile['sedentary_min_day'] != null) {
    cards.add(
      _card(
        'sitting',
        'info',
        'Awake sitting',
        'Your reported sitting time is tracked. Current adult guidance is to move more and sit less; this package does not impose a single daily cutoff.',
        _activitySource,
      ),
    );
  }
  if (profile['bmi'] != null) {
    cards.add(
      _card(
        'bmi',
        'info',
        'BMI context',
        'BMI is a screening measure, not a diagnosis or an instruction to gain or lose weight. Consider it alongside other health information.',
        _bmiSource,
      ),
    );
  }
  return cards;
}

/// Local equivalent of the Python /v1/twin/assess and /v1/twin/compare API.
class LifeTwinEngine {
  LifeTwinEngine(this.model);

  final LifeTwinModel model;

  Map<String, dynamic> _profile(Map<String, dynamic> raw) {
    final profile = Map<String, dynamic>.from(raw);
    final height = profile.remove('height_cm');
    final weight = profile.remove('weight_kg');
    if (height != null || weight != null) {
      if (height is! num ||
          weight is! num ||
          !height.isFinite ||
          !weight.isFinite ||
          height < 100 ||
          height > 230 ||
          weight < 25 ||
          weight > 350) {
        throw const FormatException(
          'height_cm and weight_kg must be valid numbers',
        );
      }
      final derived = weight / ((height / 100) * (height / 100));
      if (profile['bmi'] != null &&
          (profile['bmi'] is! num ||
              !(profile['bmi'] as num).isFinite ||
              ((profile['bmi'] as num) - derived).abs() > .5)) {
        throw const FormatException(
          'Supplied BMI disagrees with height and weight',
        );
      }
      profile['bmi'] = derived;
    }
    return profile;
  }

  Map<String, dynamic> assess(Map<String, dynamic> request) {
    if (request['daily_logs'] != null && request['weekly_summaries'] != null) {
      throw const FormatException(
        'Supply daily_logs or weekly_summaries, not both',
      );
    }
    final now = DateTime.now();
    final asOf = request['as_of_date'] == null
        ? DateTime.utc(now.year, now.month, now.day)
        : _date(request['as_of_date'], 'as_of_date');
    final raw = request['profile'];
    if (raw is! Map) throw const FormatException('profile must be an object');
    final profile = _profile(Map<String, dynamic>.from(raw));
    Map<String, dynamic> context = {'source': 'profile_snapshot'};
    if (request['daily_logs'] != null) {
      final logs = request['daily_logs'];
      if (logs is! List)
        throw const FormatException('daily_logs must be a list');
      final result = _daily(logs, asOf);
      profile.addAll(result.behavior);
      context = result.context;
    } else if (request['weekly_summaries'] != null) {
      final logs = request['weekly_summaries'];
      if (logs is! List)
        throw const FormatException('weekly_summaries must be a list');
      final result = _weekly(logs, asOf);
      profile.addAll(result.behavior);
      context = result.context;
    }
    final survival = model.predict(profile);
    final cards = _guidance(profile, context);
    final strengths = cards
        .where((card) => card['level'] == 'strength')
        .map((card) => card['id'])
        .toList();
    final opportunities = cards
        .where((card) => card['level'] == 'opportunity')
        .map((card) => card['id'])
        .toList();
    final state = survival['status'] == 'missing_inputs'
        ? 'needs_input'
        : opportunities.isNotEmpty
        ? 'explore_changes'
        : 'steady';
    return {
      'as_of_date': _iso(asOf),
      'profile_used': profile,
      'input_provenance': context,
      'survival': survival,
      'wellness_cards': cards,
      'avatar': {
        'survival_display': survival['status'] == 'available'
            ? 'annual_curve'
            : 'unavailable',
        'wellness_state': state,
        'strengths': strengths,
        'opportunities': opportunities,
      },
      'display_rules': {
        'survival_title': 'Modeled survival of similar people',
        'scenario_title': 'Modeled difference between profiles',
        'never_display': [
          'date of death',
          'years of life gained',
          'guaranteed benefit',
        ],
      },
    };
  }

  Map<String, dynamic> compare(Map<String, dynamic> request) {
    final current = request['current_profile'];
    final alternative = request['alternative_profile'];
    if (current is! Map || alternative is! Map) {
      throw const FormatException('Both comparison profiles must be objects');
    }
    return model.compare(
      _profile(Map<String, dynamic>.from(current)),
      _profile(Map<String, dynamic>.from(alternative)),
    );
  }
}
