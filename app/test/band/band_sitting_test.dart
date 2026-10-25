import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/band/band_data.dart';
import 'package:lifesim/band/band_file.dart';
import 'package:lifesim/band/band_service.dart';
import 'package:lifesim/band/band_sitting.dart';
import 'package:lifesim/band/band_store.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';

import '../checkin/daily_checkin_test.dart' show profile;

final day = DateTime(2026, 10, 25);

// Explicit synthetic labels, not accelerometer calibration: 8 hours asleep,
// 8 sitting awake, 4 standing, 2 moving and 2 lying awake.
List<BandMinute> fixedDay() => [
  for (var i = 0; i < 1440; i++)
    BandMinute(
      at: day.add(Duration(minutes: i)),
      worn: i >= 480,
      wakeState: i < 480 ? BandWakeState.asleep : BandWakeState.awake,
      posture: i < 480 || i >= 1320
          ? BandPosture.lying
          : i < 960
          ? BandPosture.sitting
          : i < 1200
          ? BandPosture.standing
          : BandPosture.moving,
    ),
];

BandSittingRecording recording({
  List<BandMinute>? minutes,
  bool complete = true,
  bool demo = false,
}) => BandSittingRecording.fromMinutes(
  date: day,
  minutes: minutes ?? fixedDay(),
  completeWakingDay: complete,
  demo: demo,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('explicit awake sitting contract', () {
    test(
      'fixed full recording counts awake sitting, excluding sleep and lying',
      () {
        final result = recording();
        expect(result.recordedMinutes, 1440);
        expect(result.awakeMinutes, 960);
        expect(result.observedSittingMinutes, 480);
        expect(result.unknownMinutes, 0);
        expect(result.sittingMinutesPerDay, 480);
      },
    );

    test(
      'empty, incomplete or unknown coverage never becomes zero sitting',
      () {
        expect(recording(minutes: []).sittingMinutesPerDay, isNull);
        expect(recording(complete: false).sittingMinutesPerDay, isNull);
        for (final minute in [
          BandMinute(at: day),
          BandMinute(at: day, posture: BandPosture.sitting),
          BandMinute(at: day, wakeState: BandWakeState.awake),
          BandMinute(
            at: day,
            wakeState: BandWakeState.awake,
            posture: BandPosture.sittingOrLying,
          ),
          BandMinute(
            at: day,
            wakeState: BandWakeState.awake,
            posture: BandPosture.sitting,
            worn: false,
          ),
        ]) {
          expect(recording(minutes: [minute]).sittingMinutesPerDay, isNull);
        }
        expect(
          recording(
            minutes: [
              BandMinute(
                at: day,
                wakeState: BandWakeState.awake,
                posture: BandPosture.standing,
              ),
            ],
          ).sittingMinutesPerDay,
          0,
        );
      },
    );

    test('one unknown awake minute withholds the whole count without dropping known sitting', () {
      final minutes = fixedDay();
      minutes[1000] = BandMinute(
        at: minutes[1000].at,
        wakeState: BandWakeState.awake,
      );
      final result = recording(minutes: minutes);
      expect(result.observedSittingMinutes, 480);
      expect(result.awakeMinutes, 960);
      expect(result.unknownMinutes, 1);
      expect(result.sittingMinutesPerDay, isNull);
      minutes[1000] = BandMinute(
        at: minutes[1000].at,
        wakeState: BandWakeState.awake,
        posture: BandPosture.standing,
      );
      minutes[0] = BandMinute(
        at: minutes[0].at,
        wakeState: BandWakeState.asleep,
        posture: BandPosture.sitting,
      );
      expect(
        recording(minutes: minutes).sittingMinutesPerDay,
        480,
        reason:
            'Explicit sleep never counts, even when the posture is sitting.',
      );
    });

    test('duplicate, off-minute and multi-date recordings are rejected', () {
      for (final minutes in [
        [BandMinute(at: day), BandMinute(at: day)],
        [BandMinute(at: day.add(const Duration(seconds: 1)))],
        [BandMinute(at: day.add(const Duration(days: 1)))],
        List.filled(1441, BandMinute(at: day)),
      ]) {
        expect(
          () => recording(minutes: minutes),
          throwsA(isA<BandSittingFailure>()),
        );
      }
    });

    test(
      'actual daily v0 cannot turn combined sitting/lying into a suggestion',
      () {
        final bytes = Uint8List.fromList(
          File('test/fixtures/band/valid_day.json').readAsBytesSync(),
        );
        final measured = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        measured.remove('synthetic_demo');
        final report = BandDayReport.fromJson(measured);
        final store = BandStore(
          StubBandClient(),
          now: () =>
              DateTime(report.date.year, report.date.month, report.date.day),
        );
        addTearDown(store.dispose);
        store.importReports([report]);
        expect(store.live, isTrue);
        expect(
          store.today.report!.observedSittingOrLyingMinutes,
          greaterThan(0),
        );
        expect(
          store.sittingDay(completeWakingDay: true).sittingMinutesPerDay,
          isNull,
        );
        expect(store.minutes, isEmpty);
      },
    );
  });

  group('bounded transient raw processing seam', () {
    BandAccelerationSample sample(
      DateTime at, {
      double x = 0,
      double y = 0,
      double z = 1,
    }) => BandAccelerationSample(at: at, xG: x, yG: y, zG: z);

    test(
      'streams raw samples into features and only returns a classified minute',
      () {
        var consumed = 0, calls = 0;
        Iterable<BandAccelerationSample> raw() sync* {
          consumed++;
          yield sample(day, x: 1);
          consumed++;
          yield sample(day.add(const Duration(seconds: 30)), x: 3);
        }

        final minute = processBandAccelerationMinute(
          at: day,
          samples: raw(),
          wakeState: BandWakeState.awake,
          classifyPosture: (features) {
            calls++;
            expect(features.samples, 2);
            expect(features.meanXG, 2);
            expect(features.meanYG, 0);
            expect(features.meanZG, 1);
            expect(features.meanSquaredMagnitudeG2, 6);
            // Test stand-in only; the hardware classifier is not implemented.
            return BandPosture.sitting;
          },
        );
        expect(consumed, 2);
        expect(calls, 1);
        expect(minute.posture, BandPosture.sitting);
        expect(recording(minutes: [minute]).sittingMinutesPerDay, 1);
      },
    );

    test('no classifier, no samples or no wear gives unknown, never invented sitting', () {
      for (final minute in [
        processBandAccelerationMinute(
          at: day,
          samples: [sample(day)],
          wakeState: BandWakeState.awake,
        ),
        processBandAccelerationMinute(
          at: day,
          samples: [],
          wakeState: BandWakeState.awake,
          classifyPosture: (_) => fail('Empty input must not be classified'),
        ),
        processBandAccelerationMinute(
          at: day,
          samples: [sample(day)],
          worn: false,
          wakeState: BandWakeState.awake,
          classifyPosture: (_) => fail('Non-wear must not be classified'),
        ),
      ]) {
        expect(minute.posture, BandPosture.unknown);
        expect(recording(minutes: [minute]).sittingMinutesPerDay, isNull);
      }
      final noWake = processBandAccelerationMinute(
        at: day,
        samples: [sample(day)],
        classifyPosture: (_) => BandPosture.sitting,
      );
      expect(recording(minutes: [noWake]).sittingMinutesPerDay, isNull);
    });

    test(
      'rejects out-of-minute, nonfinite, overflowing and over-capacity input',
      () {
        for (final samples in [
          [sample(day.subtract(const Duration(microseconds: 1)))],
          [sample(day.add(const Duration(minutes: 1)))],
          [sample(day, x: double.nan)],
          [sample(day, z: double.infinity)],
          [sample(day, x: 1e308)],
          Iterable.generate(bandMaxSamplesPerMinute + 1, (_) => sample(day)),
        ]) {
          expect(
            () => processBandAccelerationMinute(at: day, samples: samples),
            throwsA(isA<BandSittingFailure>()),
          );
        }
      },
    );
  });

  group('separate confirm-only sitting service', () {
    late TwinRepository repo;
    late BandService service;
    setUp(() async {
      repo = TwinRepository(
        model: await TwinModelService.load(),
        store: await TwinStore.open(MemoryBackend()),
      );
      await repo.saveConversationProfile(profile);
      service = BandService(repository: repo, now: () => day);
    });
    tearDown(() => repo.dispose());

    test('showing/dismissing saves nothing; confirmation alone writes band provenance', () async {
      final before = repo.current;
      final offer = service.suggestSitting(recording(), live: true)!;
      expect(offer.estimate, 480);
      expect(offer.current, 360);
      expect(offer.question, contains('Is that typical for you?'));
      expect(repo.profile[bandSittingField], 360);
      expect(repo.current, same(before));
      expect(service.suggestSitting(recording(), live: false), isNull);
      await service.confirmSitting(offer);
      expect(repo.profile[bandSittingField], 480);
      expect(
        repo.provenance(bandSittingField)!.source,
        HistorySource.wristband,
      );
      expect(repo.provenance(bandSittingField)!.estimated, isTrue);
      expect(repo.outsideAiProfile(), isNot(contains(bandSittingField)));
      expect(repo.outsideAiProfile()['age'], profile['age']);
      expect(service.suggestSitting(recording(), live: true), isNull);
      expect(
        repo.profile[bandField],
        profile[bandField],
        reason: 'Activity field is independent.',
      );
    });

    test(
      'empty recording offers nothing; a known zero remains a real candidate',
      () {
        expect(
          service.suggestSitting(recording(minutes: []), live: true),
          isNull,
        );
        final zero = recording(
          minutes: [
            BandMinute(
              at: day,
              posture: BandPosture.standing,
              wakeState: BandWakeState.awake,
            ),
          ],
        );
        expect(service.suggestSitting(zero, live: true)!.estimate, 0);
      },
    );

    test(
      'not now/keep preserve profile and use independent seven-day cooldown',
      () {
        var now = day;
        final other = BandService(repository: repo, now: () => now);
        other.keepSitting();
        expect(repo.profile[bandSittingField], 360);
        expect(other.suggestSitting(recording(), live: true), isNull);
        now = now.add(const Duration(days: 8));
        expect(other.suggestSitting(recording(), live: true), isNotNull);
      },
    );

    for (final sittingFirst in [true, false]) {
      test(
        'accepting ${sittingFirst ? 'sitting' : 'activity'} does not silence the other offer',
        () async {
          final activityWeek = BandWeek.from([
            for (var back = 0; back < 4; back++)
              for (var minute = 0; minute < 600; minute++)
                BandMinute(
                  at: day
                      .subtract(Duration(days: back))
                      .add(Duration(minutes: minute)),
                  moderate: minute < 10,
                ),
          ], day);
          if (sittingFirst) {
            await service.confirmSitting(
              service.suggestSitting(recording(), live: true)!,
            );
            expect(service.suggest(activityWeek, live: true), isNotNull);
            expect(repo.profile[bandField], profile[bandField]);
          } else {
            await service.confirm(service.suggest(activityWeek, live: true)!);
            expect(service.suggestSitting(recording(), live: true), isNotNull);
            expect(repo.profile[bandSittingField], profile[bandSittingField]);
          }
        },
      );
    }

    test('personal correction has own-answer provenance, invalid/stale saves are rejected', () async {
      final offer = service.suggestSitting(recording(), live: true)!;
      await expectLater(
        service.confirmSitting(offer, minutes: 1440),
        throwsA(isA<BandSittingFailure>()),
      );
      expect(repo.profile[bandSittingField], 360);
      await service.confirmSitting(offer, minutes: 420);
      expect(repo.profile[bandSittingField], 420);
      expect(
        repo.provenance(bandSittingField)!.source,
        HistorySource.mochiChange,
      );
      expect(repo.outsideAiProfile()[bandSittingField], 420);
      await expectLater(
        service.confirmSitting(offer),
        throwsA(isA<BandSittingFailure>()),
      );
      expect(repo.profile[bandSittingField], 420);
    });

    test(
      'built-in demo has one explicit Demo data offer, requiring confirmation',
      () async {
        final store = BandStore(StubBandClient(), now: () => day)
          ..setDemo(true);
        addTearDown(store.dispose);
        final demo = store.sittingDay();
        final sitting = store.fileReports.last.observedSittingOrLyingMinutes;
        expect(sitting, inInclusiveRange(350, 540));
        expect(demo.sittingMinutesPerDay, sitting);
        expect(demo.demo, isTrue);
        expect(service.suggestSitting(demo, live: store.live), isNull);
        expect(service.suggestSitting(demo, live: true, demo: true), isNull);
        final offer = service.suggestSitting(
          demo,
          live: store.live,
          demo: store.demoOnly,
        )!;
        expect(offer.sourceLabel, 'Demo data');
        expect(offer.question, startsWith('Demo data.'));
        expect(repo.profile[bandSittingField], 360);
        await service.confirmSitting(offer);
        expect(repo.profile[bandSittingField], sitting);
        expect(
          repo.provenance(bandSittingField)!.source,
          HistorySource.wristband,
        );
        expect(repo.outsideAiProfile(), isNot(contains(bandSittingField)));
        expect(service.suggestSitting(demo, live: false, demo: true), isNull);
      },
    );
  });
}
