import 'band_data.dart';
import 'band_demo_templates.dart';
import 'band_file.dart';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The recorded demo: 14 made-up days for a retired woman wearing a thigh band, the last one being
/// YESTERDAY relative to [today] (never a future date). Dates are applied here, so the data never goes
/// stale; each day's shape depends on its weekday and which of the two weeks it falls in.
/// Built from `tools/build_demo_band_days.py`; every report passes [BandDayReport.fromJson].
List<BandDayReport> bandDemoReports(DateTime today) {
  return [
    for (var back = 14; back >= 1; back--)
      _report(
        DateTime(today.year, today.month, today.day - back),
        back > 7 ? 0 : 1,
      ),
  ];
}

BandDayReport _report(DateTime date, int week) {
  final t = bandDemoTemplates.firstWhere(
    (t) => t.week == week && t.weekday == date.weekday,
  );
  final day = _iso(date);
  const keys = [
    'sitting_or_lying',
    'standing',
    'walking_light',
    'walking_moderate',
    'running_vigorous',
    'other_posture',
    'not_worn',
  ];
  final wear = t.recorded - t.minutes[6];
  return BandDayReport.fromJson({
    'schema': 'lifetwin.band_day.v0',
    'date': day,
    'timezone_offset_minutes': 0,
    'generated_at': '${day}T23:59:00Z',
    'device': {
      'mount': 'thigh_pocket',
      'firmware': 'synthetic-demo',
      'record_format': 2,
    },
    'coverage': {
      'minutes_recorded': t.recorded,
      'wear_minutes': wear,
      'valid_day': wear >= 600,
      'first_minute': t.first,
      'last_minute': t.last,
    },
    'minutes': {
      for (var i = 0; i < keys.length; i++) keys[i]: t.minutes[i],
      'positions_not_saved': 0,
    },
    'moderate_vigorous_minutes': t.minutes[3] + t.minutes[4],
    'steps': t.steps,
    'sit_to_stand_transitions': t.transitions,
    'longest_sitting_minutes': t.longest,
    'hourly': [
      for (var h = 0; h < 24; h++)
        {
          'hour': h,
          'sitting_lying_min': t.hours[h]?[0] ?? 0,
          'standing_min': t.hours[h]?[1] ?? 0,
          'walking_min': t.hours[h]?[2] ?? 0,
          'running_min': t.hours[h]?[3] ?? 0,
          'other_min': t.hours[h]?[4] ?? 0,
          'not_worn_min': t.hours[h]?[5] ?? 0,
          'steps': t.hours[h]?[6] ?? 0,
        },
    ],
    'notes': ['Synthetic demo data, not a hardware recording.', t.note],
    'synthetic_demo': true,
  });
}

/// Minute labels for the demo's last day, so the one labelled sitting offer still works: worn minutes
/// only, all awake, postures from the hourly rows (authored, not a sensor classifier).
List<BandMinute> bandDemoMinutes(BandDayReport r) {
  final out = <BandMinute>[];
  final base = DateTime(r.date.year, r.date.month, r.date.day);
  for (final hour in r.hourly) {
    var m = 0;
    void add(int count, BandPosture posture) {
      for (var i = 0; i < count; i++, m++) {
        out.add(
          BandMinute(
            at: base.add(Duration(hours: hour['hour']!, minutes: m)),
            posture: posture,
            wakeState: BandWakeState.awake,
          ),
        );
      }
    }

    add(hour['sitting_lying_min']!, BandPosture.sitting);
    add(hour['standing_min']!, BandPosture.standing);
    add(hour['walking_min']! + hour['running_min']!, BandPosture.moving);
  }
  return out;
}
