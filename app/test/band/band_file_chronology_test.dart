import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/band/band_data.dart';
import 'package:lifesim/band/band_file.dart';
import 'package:lifesim/band/band_file_intake.dart';
import 'package:lifesim/band/band_store.dart';

Map<String, dynamic> report({
  String date = '2026-10-24',
  int offset = -420,
  String? generated,
}) {
  final data = jsonDecode(
    File('test/fixtures/band/valid_day.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  data.remove('synthetic_demo');
  data['date'] = date;
  data['timezone_offset_minutes'] = offset;
  data['generated_at'] = generated ?? '${date}T23:59:00-07:00';
  return data;
}

Uint8List bytes(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

String day(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Synthetic consistent hourly totals, including the covered minute at each end.
Map<String, dynamic> coveredDay({
  required int first,
  required int last,
  required int count,
}) {
  String clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  final data = report();
  data['coverage'] = {
    'first_minute': clock(first),
    'last_minute': clock(last),
    'minutes_recorded': count,
    'wear_minutes': count,
    'valid_day': count >= 600,
  };
  data['minutes'] = {
    for (final key in (data['minutes'] as Map).keys)
      key: key == 'other_posture' ? count : 0,
  };
  data['moderate_vigorous_minutes'] = 0;
  data['steps'] = 0;
  data['sit_to_stand_transitions'] = 0;
  data['longest_sitting_minutes'] = 0;
  data['hourly'] = [
    for (var hour = 0; hour < 24; hour++)
      {
        'hour': hour,
        'sitting_lying_min': 0,
        'standing_min': 0,
        'walking_min': 0,
        'running_min': 0,
        'other_min': [
          for (var m = first; m < first + count; m++)
            if (m ~/ 60 == hour) m,
        ].length,
        'not_worn_min': 0,
        'steps': 0,
      },
  ];
  return data;
}

class NoFiles extends BandFilePicker {
  @override
  Stream<Uint8List> get incoming => const Stream.empty();
  @override
  Future<List<Uint8List>?> pick() async => null;
  @override
  Future<List<Uint8List>> recoverInbox() async => [];
  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('inclusive coverage and partial days', () {
    for (final (first, last, count) in [
      (0, 0, 0),
      (480, 480, 1),
      (480, 510, 31),
      (0, 1439, 1440),
    ]) {
      test('$first to $last accepts $count recorded minutes', () {
        final parsed = parseBandFile(
          bytes(coveredDay(first: first, last: last, count: count)),
        ).single;
        expect(parsed.recordedMinutes, count);
      });
    }
    test('gaps inside the covered window do not have to be filled', () {
      expect(
        parseBandFile(bytes(coveredDay(first: 480, last: 510, count: 1)))
            .single
            .recordedMinutes,
        1,
      );
    });
    test('one minute beyond the inclusive span is rejected', () {
      expect(
        () =>
            parseBandFile(bytes(coveredDay(first: 480, last: 510, count: 32))),
        throwsA(isA<BandFileFailure>()),
      );
    });
    test(
      'partial export can be generated exactly at its last covered minute',
      () {
        final parsed = parseBandFile(
          bytes(report(generated: '2026-10-24T19:59:00-07:00')),
        ).single;
        expect(parsed.lastMinute, '19:59');
      },
    );
  });

  group('export instants use both explicit offsets', () {
    for (final generated in [
      '2026-10-25T02:59:00Z',
      '2026-10-25T08:29:00+05:30',
    ]) {
      test('same coverage instant is accepted as $generated', () {
        expect(
          parseBandFile(bytes(report(generated: generated))),
          hasLength(1),
        );
      });
    }
    test('a second before coverage ends is refused across midnight', () {
      expect(
        () => parseBandFile(bytes(report(generated: '2026-10-25T02:58:59Z'))),
        throwsA(isA<BandFileFailure>()),
      );
    });
    test('an earlier written export date can still be a valid instant', () {
      expect(
        parseBandFile(
          bytes(report(offset: 840, generated: '2026-10-23T22:59:00-07:00')),
        ),
        hasLength(1),
      );
      expect(
        () => parseBandFile(
          bytes(report(offset: 840, generated: '2026-10-23T22:58:59-07:00')),
        ),
        throwsA(isA<BandFileFailure>()),
      );
    });
    test('an empty day still cannot be exported before its date begins', () {
      final data = coveredDay(first: 0, last: 0, count: 0)
        ..['generated_at'] = '2026-10-24T06:59:59Z';
      expect(() => parseBandFile(bytes(data)), throwsA(isA<BandFileFailure>()));
    });
  });

  group('phone-local acceptance and atomic delivery', () {
    for (final hour in [0, 23]) {
      test('today uses the phone local date at $hour:30 UTC', () {
        // Non-UTC TZ runs exercise dates both before and after the UTC day.
        final instant = DateTime.utc(2026, 10, 25, hour, 30);
        final local = instant.toLocal();
        final today = day(local);
        if (Platform.environment['TZ'] == 'America/Los_Angeles' ||
            Platform.environment['TZ'] == 'Pacific/Pago_Pago') {
          expect(today, hour == 0 ? '2026-10-24' : '2026-10-25');
        } else if (Platform.environment['TZ'] == 'Pacific/Kiritimati') {
          expect(today, hour == 0 ? '2026-10-25' : '2026-10-26');
        }
        final tomorrow = day(DateTime(local.year, local.month, local.day + 1));
        final store = BandStore(StubBandClient(), now: () => instant);
        addTearDown(store.dispose);
        final todayReports = parseBandFile(bytes(report(date: today)));
        expect(store.importReports(todayReports), isTrue);
        final futureReports = parseBandFile(bytes(report(date: tomorrow)));
        expect(
          () => store.importReports(futureReports),
          throwsA(isA<BandFileFailure>()),
        );
        expect(store.fileReports.single.day, today);
      });
    }

    test('record offset does not redefine the phone today cutoff', () {
      final store = BandStore(
        StubBandClient(),
        now: () => DateTime(2026, 10, 24, 23, 59),
      );
      addTearDown(store.dispose);
      final data = report(
        date: '2026-10-25',
        offset: 840,
        generated: '2026-10-25T19:59:00+14:00',
      );
      final parsed = parseBandFile(bytes(data));
      expect(
        () => store.importReports(parsed),
        throwsA(isA<BandFileFailure>()),
      );
      expect(store.fileReports, isEmpty);
    });

    test(
      'the clock is read once per delivery and refreshed for the next one',
      () {
        var phoneNow = DateTime(2026, 10, 23, 23, 59);
        var reads = 0;
        final store = BandStore(
          StubBandClient(),
          now: () {
            reads++;
            return phoneNow;
          },
        );
        addTearDown(store.dispose);
        final parsed = parseBandFile(bytes(report()));
        expect(
          () => store.importReports(parsed),
          throwsA(isA<BandFileFailure>()),
        );
        expect(reads, 1);
        phoneNow = DateTime(2026, 10, 24);
        expect(store.importReports(parsed), isTrue);
        expect(reads, 2);
      },
    );

    test('mixed future delivery preserves reports, live minutes, flags and sync time', () {
      final store = BandStore(
        StubBandClient(),
        now: () => DateTime(2026, 10, 24, 23, 59),
      );
      final intake = BandFileIntake(store: store, picker: NoFiles());
      addTearDown(intake.dispose);
      addTearDown(store.dispose);
      intake.importBytes([bytes(report())]);
      store.addMinute(BandMinute(at: DateTime(2026, 10, 23, 12), steps: 1));
      store.setConnectionLost(true);
      final oldReport = store.fileReports.single;
      final oldMinutes = store.minutes;
      final oldSync = store.lastSynced;
      final oldOutcome = intake.outcome;
      var notifications = 0;
      store.addListener(() => notifications++);
      final replacement = report()..['sit_to_stand_transitions'] = 99;
      final future = report(date: '2026-10-25');
      expect(
        () => intake.importBytes([
          bytes(replacement),
          bytes(future),
        ], replaceExisting: true),
        throwsA(isA<BandFileFailure>()),
      );
      expect(store.fileReports.single, same(oldReport));
      expect(store.minutes, oldMinutes);
      expect(store.lastSynced, oldSync);
      expect(store.connectionLost, isTrue);
      expect(store.demo, isFalse);
      expect(notifications, 0);
      expect(intake.outcome, same(oldOutcome));
    });

    test(
      'chronology errors do not echo dates, device strings or observations',
      () {
        final data = report(date: '2099-01-01');
        data['device']['firmware'] = 'private-device-marker';
        final store = BandStore(
          StubBandClient(),
          now: () => DateTime(2026, 10, 24),
        );
        addTearDown(store.dispose);
        try {
          store.importReports(parseBandFile(bytes(data)));
          fail('Expected a chronology failure');
        } on BandFileFailure catch (e) {
          expect(e.reason, isNot(contains('2099')));
          expect(e.reason, isNot(contains('private-device-marker')));
          expect(e.reason, isNot(contains('16500')));
        }
      },
    );
  });
}
