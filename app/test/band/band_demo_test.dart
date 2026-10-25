import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/band/band_data.dart';
import 'package:lifesim/band/band_demo_data.dart';
import 'package:lifesim/band/band_file.dart';
import 'package:lifesim/band/band_store.dart';

const _bundlePath = '../demo/band/band-two-weeks-demo.json';

String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

void main() {
  final bundle = parseBandFile(
    Uint8List.fromList(File(_bundlePath).readAsBytesSync()),
  );

  group('the generated bundle demo/band/band-two-weeks-demo.json', () {
    test('has 14 consecutive synthetic days that parse', () {
      expect(bundle, hasLength(14));
      expect(bundle.every((r) => r.synthetic), isTrue);
      for (var i = 1; i < bundle.length; i++) {
        expect(bundle[i].date.difference(bundle[i - 1].date).inDays, 1);
      }
    });

    test(
      'every day imports into a store clocked the day after the last day',
      () {
        final last = bundle.last.date;
        final store = BandStore(
          StubBandClient(),
          now: () => DateTime(last.year, last.month, last.day + 1, 9),
        );
        expect(store.importReports(bundle), isTrue);
        expect(store.fileReports, hasLength(14));
        expect(store.demo, isTrue);
      },
    );

    test('is the same data the app ships (templates match the bundle)', () {
      final last = bundle.last.date;
      final app = bandDemoReports(
        DateTime(last.year, last.month, last.day + 1),
      );
      expect(
        [for (final r in app) r.contentKey],
        [for (final r in bundle) r.contentKey],
      );
    });
  });

  group('realism and variety', () {
    test('steps, sitting and activity vary plausibly', () {
      expect(bundle.map((r) => r.contentKey).toSet(), hasLength(14));
      expect(
        bundle.map((r) => r.steps).toSet().length,
        greaterThanOrEqualTo(12),
      );
      for (final r in bundle) {
        expect(r.steps, inInclusiveRange(3500, 9500), reason: r.day);
        expect(
          r.longestSittingMinutes,
          inInclusiveRange(30, 140),
          reason: r.day,
        );
        expect(r.transitions, inInclusiveRange(8, 40), reason: r.day);
      }
      final sits = bundle
          .map((r) => r.observedSittingOrLyingMinutes)
          .where((m) => m >= 360 && m <= 560);
      expect(sits.length, greaterThanOrEqualTo(12));
      // at least three distinct activity levels (low / moderate / lively)
      final levels = bundle
          .map(
            (r) => r.observedMvpaMinutes < 10
                ? 0
                : r.observedMvpaMinutes < 20
                ? 1
                : 2,
          )
          .toSet();
      expect(levels.length, 3);
      final partial = bundle.where((r) => !r.validDay).toList();
      expect(partial, hasLength(1));
      expect(partial.single.wearMinutes, 540);
    });

    test('hourly rows add up to the daily totals', () {
      for (final r in bundle) {
        int sum(String k) => r.hourly.fold(0, (a, h) => a + h[k]!);
        expect(sum('steps'), r.steps, reason: r.day);
        expect(
          sum('sitting_lying_min'),
          r.postures['sitting_or_lying'],
          reason: r.day,
        );
        expect(sum('standing_min'), r.postures['standing'], reason: r.day);
        expect(
          sum('walking_min'),
          r.postures['walking_light']! + r.postures['walking_moderate']!,
          reason: r.day,
        );
        expect(sum('not_worn_min'), r.postures['not_worn'], reason: r.day);
      }
    });
  });

  group('the built-in recorded demo', () {
    test(
      'its estimate stays sensible and it is the one demo suggestion source',
      () {
        final store = BandStore(
          StubBandClient(),
          now: () => DateTime(2026, 10, 25, 15),
        )..setDemo(true);
        expect(store.demoOnly, isTrue);
        expect(store.live, isFalse);
        final week = store.week();
        expect(week.days.map((d) => d.date.day), [18, 19, 20, 21, 22, 23, 24]);
        expect(week.hasEstimate, isTrue);
        expect(week.validCount, 6);
        expect(week.estimateMinutesPerWeek, inInclusiveRange(100, 200));
        expect(store.today.steps, greaterThan(3000));
      },
    );

    test(
      'dates are relative: the last day is yesterday, never in the future',
      () {
        for (final now in [
          DateTime(2026, 10, 25, 0, 0, 1),
          DateTime(2026, 10, 25, 23, 59, 59),
          DateTime(2026, 3, 1, 12),
          DateTime(2028, 3, 1, 12), // after a leap day
          DateTime(2026, 11, 2, 0, 30), // just after the US clock change
          DateTime(2027, 1, 1, 8),
          DateTime(2030, 6, 15, 17),
        ]) {
          final reports = bandDemoReports(now);
          final yesterday = DateTime(now.year, now.month, now.day - 1);
          expect(reports.last.day, _iso(yesterday), reason: '$now');
          expect(reports.map((r) => r.day).toSet(), hasLength(14));
          final store = BandStore(StubBandClient(), now: () => now)
            ..setDemo(true);
          expect(
            store.fileReports.every((r) => r.day.compareTo(_iso(now)) < 0),
            isTrue,
            reason: '$now',
          );
          expect(
            BandStore(StubBandClient(), now: () => now).importReports(reports),
            isTrue,
            reason: 'no future-date, coverage or export-time error at $now',
          );
        }
      },
    );

    test('weekday shapes: a lively weekend beats the rest day; partial wear is not a valid day', () {
      final byDay = {
        for (final r in bandDemoReports(DateTime(2026, 10, 25))) r.day: r,
      };
      expect(
        byDay['2026-10-18']!.observedMvpaMinutes,
        greaterThan(byDay['2026-10-11']!.observedMvpaMinutes),
      );
      expect(BandDay.fromReport(byDay['2026-10-21']!).isValid, isFalse);
    });
  });
}
