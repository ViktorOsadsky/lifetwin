import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_models.dart' show shiftDay;
import 'package:lifesim/demo/demo_seed.dart';
import 'package:lifesim/twin/profile_mapping.dart' show toModelProfile;
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(
    2026,
    10,
    24,
    18,
    30,
  ); // a Saturday; the seed is relative to it

  Future<TwinRepository> seeded([MemoryBackend? b]) =>
      openTwin(demo: true, backend: b ?? MemoryBackend(), now: () => now);

  test('flag off: nothing is seeded and the store is untouched', () async {
    expect(demoSeedEnabled, isFalse); // no --dart-define in tests
    final backend = MemoryBackend();
    final repo = await openTwin(demo: false, backend: backend, now: () => now);
    expect(repo.store.hasProfile, isFalse);
    expect(repo.history(), isEmpty);
    expect(repo.healthScoreHistory(), isEmpty);
    expect(backend.text, isNull);
  });

  test('flag on does not touch a store that already has a profile', () async {
    final backend = MemoryBackend();
    final real = await openTwin(demo: false, backend: backend, now: () => now);
    await real.saveConversationProfile({'age': 50, 'sex': 'male'});
    final again = await openTwin(demo: true, backend: backend, now: () => now);
    expect(again.profile['age'], 50);
    expect(again.history().length, real.history().length);
  });

  group('seeded', () {
    late TwinRepository repo;
    setUp(() async => repo = await seeded());

    test('Rosa has a supported profile and a score from the real model', () {
      expect(repo.profile['age'], 64);
      expect(repo.profile['smoking_status'], 'never');
      expect(repo.profile['hypertension_diagnosed'], false);
      final a = repo.current!;
      expect(a.available, isTrue);
      expect(a.healthScoreStatus, HealthScoreStatus.available);
      expect(repo.healthScore, isNotNull);
      expect(repo.ageGroupPercentile, isNotNull);
      expect(repo.outsideAiConsent, isFalse);
      expect(repo.checkinSettings.reminderHour, 10);
      expect(repo.checkinSettings.reminderMinute, 0);
      expect(repo.checkinSettings.remindersOn, isTrue);
      expect(repo.store.memoryConsent, isTrue);
      expect(repo.store.habitNotes.length, 2);
    });

    test('events: onboarding, check-ins with gaps, weekly, document, Mochi change, wristband', () {
      final h = repo.history();
      int count(String k) => h.where((e) => e.kind == k).length;
      expect(count(HistoryKind.onboarding), 1);
      expect(
        h.firstWhere((e) => e.kind == HistoryKind.onboarding).date,
        '2026-10-08',
      ); // 16 days ago
      expect(count(HistoryKind.weekly), 1);
      final quickDays = {
        for (final c in repo.store.checkins.where((c) => c.kind == 'quick'))
          c.date,
      };
      expect(
        quickDays.length,
        inInclusiveRange(10, 12),
      ); // 14 days minus 2-3 missed
      expect(repo.goodWeeks(), greaterThanOrEqualTo(1));

      final logs = repo.dayLogs(
        from: DateTime(2026, 10, 10),
        to: DateTime(2026, 10, 23),
      );
      expect(
        logs.any((d) => d.empty),
        isTrue,
      ); // missed days are unknown, never 0
      expect(logs.where((d) => d.sedentaryMin == 0), isEmpty);
      // One "I don't know": answered check-in whose sedentary time stayed unknown.
      expect(
        repo.store.checkins
            .where((c) => c.answers['sedentary_min_day'] == 'unknown')
            .length,
        1,
      );

      final readings = {
        for (final e in repo.readings())
          for (final i in e.items) i.field: i,
      };
      expect(readings['systolic_bp']!.value, 138);
      expect(readings['diastolic_bp']!.value, 86);
      expect(readings['hba1c']!.value, 5.8);
      expect(readings['hba1c']!.date, '2026-10-14'); // dated 10 days ago
      expect(readings['hba1c']!.source, HistorySource.document);

      expect(h.where((e) => e.kind == HistoryKind.mochiChange).length, 2);
      final band = repo.provenance('moderate_recreation_min_week')!;
      expect(band.source, HistorySource.wristband);
      expect(band.estimated, isTrue);
      expect(
        repo.outsideAiProfile().containsKey('moderate_recreation_min_week'),
        isFalse,
      );
      expect(
        repo.provenance('sedentary_min_day')!.source,
        HistorySource.mochiChange,
      );
    });

    test(
      'onboarding matches the approved design persona (persona_out.json)',
      () {
        final h = (rosaProfile['height_cm'] as double) / 100;
        expect(
          (rosaProfile['weight_kg'] as double) / (h * h),
          closeTo(25.14860539551897, 0.01),
        );
        final first = repo.model.assessModel(toModelProfile(rosaProfile));
        expect(first.available, isTrue);
        expect(first.percentByYear[5]!, closeTo(96.92, 0.01));
        expect(first.healthScore!, closeTo(-0.0375, 0.005));
        final seeded = repo.healthScoreHistory().first;
        expect(seeded.score!, closeTo(-0.0375, 0.005));
      },
    );

    test('the weekly check-in is the one that fed the forecast', () {
      final weekly = repo.history().firstWhere(
        (e) => e.kind == HistoryKind.weekly,
      );
      expect(weekly.fedForecast, 'weekly_summaries');
      expect(weekly.date, '2026-10-18');
    });

    test('score history follows the events and matches the model exactly', () {
      final points = repo.healthScoreHistory();
      expect(points.length, greaterThan(5));
      expect(
        points.every(
          (p) => p.status == HealthScoreStatus.available && p.score != null,
        ),
        isTrue,
      );
      for (var i = 1; i < points.length; i++) {
        expect(points[i].at.isBefore(points[i - 1].at), isFalse);
      }
      // The last point is what the model says now for the stored profile and windows.
      expect(points.last.score, repo.healthScore);
      expect(points.last.ageGroupPercentile, repo.ageGroupPercentile);
      // The first point is the onboarding profile, straight through the model.
      final first = repo.model.assessModel(toModelProfile(rosaProfile));
      expect(points.first.score, first.healthScore);
      expect(points.first.ageGroupPercentile, first.ageGroupPercentile);
      // A visible trend: the score moves between first and last.
      expect(
        points.last.score!,
        lessThan(points.first.score!),
      ); // lower hazard: healthier
      expect(
        points.last.ageGroupPercentile!,
        greaterThan(points.first.ageGroupPercentile!),
      );
    });

    test('reopening does not seed twice', () async {
      final backend = MemoryBackend();
      final a = await seeded(backend);
      final n = a.history().length, p = a.healthScoreHistory().length;
      final b = await seeded(backend);
      expect(b.history().length, n);
      expect(b.healthScoreHistory().length, p);
      expect(shiftDay('2026-10-24', -16), '2026-10-08');
    });
  });
}
