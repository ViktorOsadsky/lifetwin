import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_store.dart';
import 'package:lifesim/checkin/daily_logs.dart';
import 'package:lifetwin_on_device/lifetwin_on_device.dart';

/// The package's own model and validation, loaded from its files.
LifeTwinEngine engine() {
  const dir = '../model_handoff/lifetwin_on_device/assets';
  final model = LifeTwinModel.fromArtifacts(
    jsonDecode(File('$dir/model.json').readAsStringSync()) as Map<String, dynamic>,
    Uint8List.fromList(gzip.decode(File('$dir/support_reference.f64.gz').readAsBytesSync())),
  );
  return LifeTwinEngine(model);
}

const profile = {
  'age': 70,
  'sex_nhanes': 2,
  'height_cm': 162,
  'weight_kg': 66,
  'smoking_status': 1,
  'diabetes_diagnosed': 0,
  'hypertension_diagnosed': 1,
  'general_health': 3,
};

const assembler = DailyLogsAssembler();

/// [n] complete days ending the day before [asOf].
List<DayLog> days(String asOf, int n, {int sitting = 360}) => [
  for (var i = n; i >= 1; i--)
    DayLog(
      date: shiftDay(asOf, -i),
      sleepHours: 7 + (i % 3) * 0.5,
      vigorousMin: i.isEven ? 20 : 0,
      moderateMin: 30,
      sedentaryMin: sitting,
    ),
];

void main() {
  final twin = engine();
  const asOf = '2026-10-24';

  test('a complete week becomes daily_logs the package accepts', () {
    final window = assembler.dailyWindow(days(asOf, 7), asOf)!;
    expect(window, hasLength(7));
    expect(window.first.keys.toSet(), {
      'date',
      'workday',
      'sleep_hours',
      'vigorous_recreation_min',
      'moderate_recreation_min',
      'sedentary_min_day',
    });
    expect(window.last['date'], '2026-10-23');
    final result = twin.assess({'profile': profile, 'as_of_date': asOf, 'daily_logs': window});
    final provenance = result['input_provenance'] as Map;
    expect(provenance['source'], 'daily_logs');
    expect(provenance['complete_weeks'], 1);
    expect((result['profile_used'] as Map)['sedentary_min_day'], 360);
  });

  test('the longest supported window is used: 28, 21, 14 or 7 days', () {
    for (final (have, want) in [(30, 28), (27, 21), (20, 14), (13, 7)]) {
      final window = assembler.dailyWindow(days(asOf, have), asOf)!;
      expect(window, hasLength(want));
      final result = twin.assess({'profile': profile, 'as_of_date': asOf, 'daily_logs': window});
      expect((result['input_provenance'] as Map)['complete_weeks'], want ~/ 7);
    }
  });

  test('a missed day is unknown: it is never filled in, so the run stops there', () {
    final logs = days(asOf, 14)..removeAt(10); // 2026-10-20 missing
    final window = assembler.dailyWindow(logs, asOf);
    expect(window, isNull); // only 3 complete days end yesterday
    expect(assembler.completeRun(logs, asOf), hasLength(3));
  });

  test('a partial day does not count, and fewer than 7 days means no window', () {
    final logs = days(asOf, 7);
    logs[3] = DayLog(date: logs[3].date, sleepHours: 7, vigorousMin: 0, moderateMin: 30);
    expect(assembler.dailyWindow(logs, asOf), isNull);
    expect(assembler.dailyWindow(days(asOf, 6), asOf), isNull);
  });

  test('a day the package would refuse is left out, not patched', () {
    final short = days(asOf, 7);
    short[6] = DayLog(date: short[6].date, sleepHours: 1.5, vigorousMin: 0, moderateMin: 0, sedentaryMin: 300);
    expect(assembler.dailyWindow(short, asOf), isNull);
    final long = days(asOf, 7, sitting: 1000); // 7 h sleep + 1000 min sitting > a day
    expect(assembler.row(long.first), isNull);
  });

  test('the window must end yesterday', () {
    expect(assembler.dailyWindow(days('2026-10-22', 7), asOf), isNull);
  });

  test('workday means the night before a weekday', () {
    expect(weekdayNight('2026-10-19'), isTrue); // Monday: Sunday night, before work
    expect(weekdayNight('2026-10-23'), isTrue); // Friday
    expect(weekdayNight('2026-10-24'), isFalse); // Saturday
    final custom = DailyLogsAssembler(workday: (date) => parseDay(date).weekday >= DateTime.wednesday);
    expect(custom.row(days(asOf, 1).single)!['workday'], isTrue);
  });

  test('the server\'s quick daily_logs parts merge into rows the package accepts', () {
    final fixtures = jsonDecode(File('../contracts/fixtures/cases.json').readAsStringSync()) as List;
    final finished = fixtures.firstWhere((c) => c['name'] == 'checkin-quick-complete-daily-logs') as Map;
    final response = {
      'complete': true,
      'state': {'kind': 'quick', 'confirmed': <String, dynamic>{}},
      'daily_logs': (finished['response_subset'] as Map)['daily_logs'],
    };
    final parts = readFinishedCheckin(response, localDate: asOf)!.parts;
    expect(parts.map((p) => p.date), ['2026-10-23', '2026-10-24']);
    // Six earlier complete days, then the 23rd's activity from the server, with its
    // sleep from the day before's check-in.
    final earlier = days('2026-10-23', 6);
    final rows = mergeDayLogs([...earlier, const DayLog(date: '2026-10-23', sleepHours: 6.5)], parts);
    final window = assembler.dailyWindow(rows, asOf)!;
    expect(window.last, {
      'date': '2026-10-23',
      'workday': true,
      'sleep_hours': 6.5,
      'vigorous_recreation_min': 20,
      'moderate_recreation_min': 30,
      'sedentary_min_day': 360,
    });
    twin.assess({'profile': profile, 'as_of_date': asOf, 'daily_logs': window});
  });

  group('weekly summaries', () {
    CheckinEntry weekly(String date, {int vig = 60}) => CheckinEntry(
      kind: 'weekly',
      date: date,
      answers: {
        'sleep_hours': 7,
        'vigorous_recreation_min_week': vig,
        'moderate_recreation_min_week': 150,
        'sedentary_min_day': 400,
        'wellbeing': 'good',
      },
    );

    test('weekly check-ins with all four fields become summaries the package accepts', () {
      // Sunday check-ins describe the week ending that day.
      final checkins = [weekly('2026-10-11'), weekly('2026-10-18')];
      final window = assembler.weeklyWindow(checkins, asOf)!;
      expect(window.map((w) => w['week_start']), ['2026-10-05', '2026-10-12']);
      expect(window.last.keys.toSet(), {'week_start', ...weeklySummaryFields});
      final result = twin.assess({'profile': profile, 'as_of_date': asOf, 'weekly_summaries': window});
      expect((result['input_provenance'] as Map)['source'], 'weekly_summaries');
    });

    test('a week with an answer missing is no summary', () {
      final partial = CheckinEntry(kind: 'weekly', date: '2026-10-18', answers: {'sleep_hours': 7});
      expect(assembler.weeklyWindow([partial], asOf), isNull);
    });

    test('the latest completed week must be there', () {
      expect(assembler.weeklyWindow([weekly('2026-10-11')], asOf), isNull);
    });

    test('a later check-in for the same week wins', () {
      final window = assembler.weeklyWindow([weekly('2026-10-18', vig: 10), weekly('2026-10-18', vig: 90)], asOf)!;
      expect(window.single['vigorous_recreation_min_week'], 90);
    });
  });

  test('the forecast request prefers weekly, then daily, then the profile alone', () {
    final daily = assembler.assessRequest(modelProfile: profile, asOf: asOf, days: days(asOf, 7), checkins: []);
    expect(daily.keys.toSet(), {'profile', 'as_of_date', 'daily_logs'});
    twin.assess(daily);
    final none = assembler.assessRequest(modelProfile: profile, asOf: asOf, days: days(asOf, 3), checkins: []);
    expect(none.keys.toSet(), {'profile', 'as_of_date'});
    twin.assess(none);
  });

  test('good weeks count check-in days, never streaks', () {
    final checkins = [
      for (final d in ['2026-10-05', '2026-10-07', '2026-10-09', '2026-10-11'])
        CheckinEntry(kind: 'quick', date: d, answers: const {}),
      for (final d in ['2026-10-12', '2026-10-18']) CheckinEntry(kind: 'quick', date: d, answers: const {}),
      for (final d in ['2026-10-20', '2026-10-22']) CheckinEntry(kind: 'quick', date: d, answers: const {}),
    ];
    final progress = weekProgress(checkins, asOf);
    expect(progress.goodWeeks, 1);
    expect(progress.daysThisWeek, 2);
  });
}
