import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';

import 'store_and_checkin_test.dart' show fullProfile, responseFor, weeklyWithBehaviour;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  late List<Map<String, dynamic>> golden;
  setUpAll(() async {
    model = await TwinModelService.load();
    golden = (jsonDecode(File('packages/lifetwin_on_device/test/golden_vectors.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
  });

  Map<String, dynamic> g(int i) => Map<String, dynamic>.from(golden[i]['profile'] as Map);

  test('the raw score is predict()\'s log_relative_hazard_score exactly; the score is the centred score', () {
    for (var i = 0; i < golden.length; i++) {
      final a = model.assessModel(g(i));
      final predicted = model.engine.model.predict(g(i));
      expect(predicted['status'], 'available');
      expect(a.rawLogRelativeHazard, predicted['log_relative_hazard_score']);
      expect(a.rawLogRelativeHazard, closeTo((golden[i]['log_relative_hazard_score'] as num).toDouble(), 1e-12));
      // The centred score: positive = healthier, above 0 exactly when the percentile is above 50.
      expect(a.healthScore!.isFinite, isTrue);
      if (a.healthScore != 0) expect(a.healthScore! > 0, a.ageGroupPercentile! > 50);
      expect(a.healthScoreStatus, HealthScoreStatus.available);
    }
  });

  test('missing inputs: no number, the status and the model\'s message, nothing filled in', () {
    final a = model.assessModel({...g(0)}..remove('bmi')..remove('sleep_hours')..remove('sedentary_min_day'));
    expect(a.healthScore, isNull);
    expect(a.healthScoreStatus, HealthScoreStatus.missingInputs);
    expect(a.message, isNotEmpty);
  });

  test('over 85 is unsupported_age', () {
    for (final age in [86]) {
      final a = model.assessModel({...g(0), 'age': age});
      expect(a.healthScore, isNull);
      expect(a.healthScoreStatus, HealthScoreStatus.unsupportedAge);
      expect(a.message, unsupportedAgeMessage);
    }
  });

  test('an unsupported profile has no number', () {
    final a = model.assessModel({...g(0), 'bmi': 60, 'sedentary_min_day': 1200, 'sleep_hours': 2});
    expect(a.healthScoreStatus, HealthScoreStatus.unsupportedProfile);
    expect(a.healthScore, isNull);
    expect(a.message, isNotEmpty);
  });

  test('ages 30-34 and 80-85 are extrapolated and use the forecast\'s own score', () {
    for (final age in [30, 34, 80, 85]) {
      final a = model.assessModel({...g(0), 'age': age});
      expect(a.healthScoreStatus, HealthScoreStatus.extrapolated, reason: 'age $age');
      expect(a.rawLogRelativeHazard, a.survival['log_relative_hazard_score']);
      expect(a.healthScore, isNotNull);
      expect(a.ageGroupNearestBand, isTrue);
    }
    final anchor = model.assessModel({...g(0), 'age': 35}).rawLogRelativeHazard!;
    final younger = model.assessModel({...g(0), 'age': 34}).rawLogRelativeHazard!;
    expect(younger, lessThan(anchor)); // a year younger: lower modelled risk
    expect(model.assessModel({...g(0), 'age': 79}).healthScoreStatus, HealthScoreStatus.available);
  });

  test('under 18 is under_age with no number; 18-29 are extrapolated', () {
    final young = model.assessModel({...g(0), 'age': 17});
    expect(young.healthScore, isNull);
    expect(young.healthScoreStatus, HealthScoreStatus.underAge);
    expect(young.message, underAgeMessage);
    expect(young.ageGroupPercentile, isNull);
    for (final age in [18, 22, 29]) {
      final a = model.assessModel({...g(0), 'age': age});
      expect(a.healthScoreStatus, HealthScoreStatus.extrapolated, reason: 'age $age');
      expect(a.healthScore, isNotNull);
    }
  });

  test('the extrapolated score is the 35-year-old score plus the model\'s linear age term', () {
    final coef = ((model.engine.model.spec['coefficients'] as List).first as num).toDouble();
    final at35 = model.assessModel({...g(0), 'age': 35}).rawLogRelativeHazard!;
    expect(model.assessModel({...g(0), 'age': 18}).rawLogRelativeHazard, closeTo(at35 + coef * (18 - 35) / 10, 1e-12));
    // age_decade = (age - 55) / 10 is what the package encodes inside 35-79
    expect(model.assessModel({...g(0), 'age': 45}).rawLogRelativeHazard! - at35, closeTo(coef * 1.0, 1e-12));
  });

  group('age-group percentile', () {
    final spec = <String, dynamic>{};
    late List<double> coef, centre;
    setUpAll(() {
      spec.addAll(model.engine.model.spec);
      coef = [for (final c in spec['coefficients'] as List) (c as num).toDouble()];
      centre = [for (final c in spec['feature_center'] as List) (c as num).toDouble()];
    });

    /// Rows sit at the centre except the sedentary feature (column 7) = [sed]; age and sex per row.
    AgeGroupReference reference(List<({double age, bool female, double sed})> rows) {
      final data = Float64List(rows.length * 17);
      for (var r = 0; r < rows.length; r++) {
        for (var i = 0; i < 17; i++) {
          data[r * 17 + i] = centre[i];
        }
        data[r * 17] = (rows[r].age - 55) / 10;
        data[r * 17 + 8] = rows[r].female ? 1 : 0;
        data[r * 17 + 7] = rows[r].sed;
      }
      return AgeGroupReference(data, coef, centre);
    }

    /// The model score of a person with sedentary feature [sed] (all else at the centre).
    double scoreOf(double sed, num age, bool female) =>
        (sed - centre[7]) * coef[7] +
        ((age - 55) / 10 - centre[0]) * coef[0] +
        ((female ? 1 : 0) - centre[8]) * coef[8];

    final rows = [
      for (var k = 0; k < 60; k++) (age: 45.0, female: false, sed: k / 10), // the band: 60 men aged 45
      for (var k = 0; k < 40; k++) (age: 45.0, female: true, sed: k / 10 - 9), // women: never compared with men
      for (var k = 0; k < 40; k++) (age: 70.0, female: false, sed: k / 10 - 9), // men aged 70: outside 40-50
    ];
    late AgeGroupReference ref;
    setUp(() => ref = reference(rows));

    test('hand-computed band: 29 of the 60 men aged 40-50 score higher', () {
      // The person's sedentary feature is 3.05; rows k = 31..59 (3.1 .. 5.9) are higher (worse).
      final r = ref.compare(score: scoreOf(3.05, 45, false), age: 45, female: false);
      expect(r.size, 60);
      expect(r.percentile, closeTo(100 * 29 / 60, 1e-9));
      expect((r.bandLow, r.bandHigh, r.width, r.nearestBand), (40, 50, 5, false));
    });

    test('only the same sex is compared', () {
      expect(ref.count(female: false, low: 40, high: 50), 60);
      expect(ref.count(female: true, low: 40, high: 50), 40);
      final f = ref.compare(score: scoreOf(-7.05, 45, true), age: 45, female: true);
      expect(f.size, 40);
      expect(f.percentile, closeTo(100 * 20 / 40, 1e-9)); // women k = 20..39 are higher than -7.05
    });

    test('hand-computed centred score: lower median − own, 0 at the median', () {
      // 60 men: sedentary k/10, k = 0..59; the 30th smallest (k = 29) is the lower median.
      final median = (2.9 - centre[7]) * coef[7];
      final r = ref.compare(score: scoreOf(3.05, 45, false), age: 45, female: false);
      expect(r.medianScore, closeTo(median, 1e-12));
      expect(r.healthScore, closeTo(median - (3.05 - centre[7]) * coef[7], 1e-12));
      expect(r.healthScore, lessThan(0)); // percentile 48.3 < 50
      final at = ref.compare(score: scoreOf(2.9, 45, false), age: 45, female: false);
      expect(at.healthScore, closeTo(0, 1e-12));
      expect(at.percentile, 50); // k = 30..59 are higher
      final just = ref.compare(score: scoreOf(2.85, 45, false), age: 45, female: false);
      expect(just.healthScore, greaterThan(0));
      expect(just.percentile, greaterThan(50));
      expect(r.label, 'men 40–50');
    });

    test('edges: nobody worse is 100, nobody better is 0; monotonic in between', () {
      expect(ref.compare(score: scoreOf(-5, 45, false), age: 45, female: false).percentile, 100);
      expect(ref.compare(score: scoreOf(99, 45, false), age: 45, female: false).percentile, 0);
      var last = 101.0;
      for (final sed in [-1.0, 0.0, 1.0, 2.5, 4.0, 6.0]) {
        final p = ref.compare(score: scoreOf(sed, 45, false), age: 45, female: false).percentile;
        expect(p, lessThanOrEqualTo(last));
        last = p;
      }
    });

    test('once age is excluded, the person\'s age inside the band does not matter', () {
      final a = ref.compare(score: scoreOf(3.05, 41, false), age: 41, female: false);
      final b = ref.compare(score: scoreOf(3.05, 49, false), age: 49, female: false);
      expect(scoreOf(3.05, 41, false), isNot(scoreOf(3.05, 49, false)));
      expect(a.percentile, b.percentile);
      expect(a.size, b.size);
    });

    test('fewer than 50 people widens the band to 7, then 10, and reports the width', () {
      final few = reference([
        for (var k = 0; k < 20; k++) (age: 45.0, female: false, sed: k / 10),
        for (var k = 0; k < 20; k++) (age: 51.5, female: false, sed: k / 10), // only inside +-7
        for (var k = 0; k < 20; k++) (age: 54.0, female: false, sed: k / 10), // only inside +-10
      ]);
      final r5 = few.compare(score: scoreOf(1, 45, false), age: 45, female: false);
      expect(r5.width, 10); // 20 at +-5, 40 at +-7, 60 at +-10
      expect(r5.size, 60);
      expect((r5.bandLow, r5.bandHigh), (35, 55));
      final r7 = reference([
        for (var k = 0; k < 20; k++) (age: 45.0, female: false, sed: k / 10),
        for (var k = 0; k < 40; k++) (age: 51.5, female: false, sed: k / 10),
      ]).compare(score: scoreOf(1, 45, false), age: 45, female: false);
      expect((r7.width, r7.size), (7, 60));
    });

    test('outside 35-79 the nearest band inside it is used and marked', () {
      final young = ref.compare(score: scoreOf(3.05, 20, false), age: 20, female: false);
      expect(young.nearestBand, isTrue);
      expect((young.bandLow, young.bandHigh), (35, 45));
      final old = ref.compare(score: scoreOf(3.05, 83, false), age: 83, female: false);
      expect(old.nearestBand, isTrue);
      // Too few people near 79 in this set, so it widens to +-10, still inside 35-79.
      expect((old.bandLow, old.bandHigh, old.width), (59, 79, 10));
      expect(ref.compare(score: 0, age: 79, female: false).nearestBand, isFalse);
    });

    test('with the real reference: better profile, higher percentile; marked and null correctly', () {
      final good = model.assessModel({...g(0), 'sedentary_min_day': 120, 'vigorous_recreation_min_week': 300});
      final base = model.assessModel(g(0));
      final bad = model.assessModel({...g(0), 'smoking_status': 2, 'diabetes_diagnosed': 1, 'general_health': 5});
      expect(good.ageGroupPercentile!, greaterThan(base.ageGroupPercentile!));
      expect(base.ageGroupPercentile!, greaterThan(bad.ageGroupPercentile!));
      expect(base.ageGroupPercentile, inInclusiveRange(0, 100));
      expect(base.ageGroupBand, '40–50');
      expect(base.ageGroupSize, greaterThanOrEqualTo(50));
      expect(base.ageGroupNearestBand, isFalse);
      // The score itself is untouched, and agrees in direction: healthier is higher.
      expect(base.rawLogRelativeHazard, model.engine.model.predict(g(0))['log_relative_hazard_score']);
      expect(base.healthScore!, greaterThan(bad.healthScore!));
      final young = model.assessModel({...g(0), 'age': 25});
      expect(young.ageGroupNearestBand, isTrue);
      expect(young.ageGroupBand, '35–45');
      expect(model.assessModel({...g(0), 'age': 17}).ageGroupPercentile, isNull);
      expect(model.assessModel({...g(0)}..remove('bmi')..remove('sleep_hours')..remove('sedentary_min_day')).ageGroupPercentile, isNull);
      expect(model.assessModel({...g(0), 'age': 90}).ageGroupSize, isNull);
    });

    test('band sizes per sex and decade (reported)', () {
      final out = <String>[];
      for (final female in [false, true]) {
        for (final age in [20, 35, 45, 55, 65, 75, 79, 85]) {
          final a = model.assessModel({...g(0), 'age': age, 'sex_nhanes': female ? 2 : 1});
          out.add('${female ? 'F' : 'M'}$age:${a.ageGroupSize}(±${a.ageGroupWidth})');
        }
      }
      // ignore: avoid_print
      print(out.join(' '));
    });
  });

  group('repository', () {
    var now = DateTime(2026, 10, 26, 9);
    Future<TwinRepository> repoOn(StoreBackend b) async =>
        TwinRepository(model: model, store: await TwinStore.open(b), clock: () => now);

    test('healthScore, status and message follow the current assessment', () async {
      final repo = await repoOn(MemoryBackend());
      expect(repo.healthScore, isNull);
      expect(repo.healthScoreStatus, isNull);
      await repo.saveConversationProfile({
        ...fullProfile,
        'weight_kg': null,
        'height_cm': null,
        'sleep_hours': null,
        'sedentary_min_day': null,
      });
      expect(repo.healthScore, isNull);
      expect(repo.healthScoreStatus, HealthScoreStatus.missingInputs);
      expect(repo.healthScoreMessage, isNotEmpty);
      await repo.saveConversationProfile(fullProfile);
      expect(repo.healthScoreStatus, HealthScoreStatus.available);
      expect(repo.rawLogRelativeHazard, repo.current!.survival['log_relative_hazard_score']);
      expect(repo.healthScore, repo.current!.healthScore);
      expect(repo.healthScore, isNotNull);
    });

    test('lifespanEstimate comes from the current profile; none before a profile or under 18', () async {
      final repo = await repoOn(MemoryBackend());
      expect(repo.lifespanEstimate, isNull);
      // The yearly projection of this healthy 45-year-old stays above 25% at 110: the
      // 75th-percentile age is open-ended (110), and there is still an estimate.
      await repo.saveConversationProfile(fullProfile);
      expect(repo.lifespanEstimate!.p75OpenEnded, isTrue);
      expect(repo.lifespanEstimate!.p75Age, 110);
      await repo.saveConversationProfile({...fullProfile, 'age': 64, 'smoking_status': 'current'});
      final e = repo.lifespanEstimate!;
      final age = repo.current!.profileUsed['age'] as num;
      expect(e.expectedAge, greaterThan(age));
      expect(e.expectedYear, now.year + (e.expectedAge - age + 0.5).floor());
      expect(e.caveat, contains('Proof of concept'));
      await repo.saveConversationProfile({...fullProfile, 'age': 17});
      expect(repo.lifespanEstimate, isNull);
    });

    test('the lifespan reveal flag persists and Delete my data clears it', () async {
      final backend = MemoryBackend();
      final repo = await repoOn(backend);
      await repo.saveConversationProfile(fullProfile);
      expect(repo.lifespanRevealSeen, isFalse);
      await repo.markLifespanRevealSeen();
      expect(repo.lifespanRevealSeen, isTrue);
      expect((await repoOn(backend)).lifespanRevealSeen, isTrue); // reopened from the file
      await repo.deleteMyData();
      expect(repo.lifespanRevealSeen, isFalse);
      expect((await repoOn(backend)).lifespanRevealSeen, isFalse);
    });

    test('stored history keeps the raw value and the centred score; old-scale points are left out', () async {
      final backend = MemoryBackend();
      final repo = await repoOn(backend);
      await repo.saveConversationProfile(fullProfile);
      final stored = (jsonDecode(backend.text!) as Map)['health_score'] as List;
      expect((stored.single as Map)['score'], repo.rawLogRelativeHazard);
      final point = repo.healthScoreHistory().single;
      expect(point.rawLogRelativeHazard, repo.rawLogRelativeHazard);
      expect(point.score, repo.healthScore);
      expect((stored.single as Map)['centered_score'], repo.healthScore);
      // A point written before the engine tag (the old −log-hazard scale) has no index and a
      // legacy engine, so the history readers leave it out.
      final old = HealthScorePoint.fromJson({'at': '2026-10-01T09:00:00.000', 'score': 0.5, 'status': 'available'});
      expect(old.score, isNull);
      expect(old.rawLogRelativeHazard, 0.5);
      expect(old.engine, legacyHealthScoreEngine);
      expect(old.toJson()['score'], 0.5);
    });

    test('history grows on a feeding check-in, not on a non-feeding one, and is append-only', () async {
      final repo = await repoOn(MemoryBackend());
      await repo.saveConversationProfile(fullProfile);
      final first = repo.healthScoreHistory();
      expect(first, hasLength(1));
      expect(first.single.score, repo.healthScore);
      expect(first.single.status, HealthScoreStatus.available);
      expect(first.single.modelVersion, model.modelVersion);
      expect(first.single.ageGroupPercentile, repo.ageGroupPercentile);
      expect(first.single.ageGroupPercentile, isNotNull);
      expect(first.single.ageGroupSize, repo.ageGroupSize);
      expect(first.single.date, '2026-10-26');

      // A daily check-in is history only: it feeds nothing.
      await repo.applyCheckin({
        ...responseFor('checkin-daily-start'),
        'complete': true,
        'state': {
          'kind': 'daily',
          'phase': 'ready',
          'questions': ['wellbeing'],
          'current_field': null,
          'confirmed': {'wellbeing': 'okay'},
        },
      }, localDate: '2026-10-26');
      expect(repo.healthScoreHistory(), hasLength(1));

      now = DateTime(2026, 10, 27, 9);
      await repo.applyCheckin(responseFor('checkin-weekly-profile-update'));
      final after = repo.healthScoreHistory();
      expect(after, hasLength(2));
      expect(after.first.score, first.single.score); // the earlier point is untouched
      expect(after.last.score, repo.healthScore);
      expect(after.last.score, isNot(after.first.score)); // short sleep moved it
      expect(repo.healthScoreHistory(from: DateTime(2026, 10, 27)), hasLength(1));

      await repo.applyCheckin(weeklyWithBehaviour(sleep: 7));
      expect(repo.healthScoreHistory(), hasLength(3));
    });

    test('an import records a point, an unsupported age records its status with no number', () async {
      final repo = await repoOn(MemoryBackend());
      await repo.saveConversationProfile({...fullProfile, 'age': 86});
      expect(repo.healthScoreHistory().single.score, isNull);
      expect(repo.healthScoreHistory().single.status, HealthScoreStatus.unsupportedAge);
      await repo.recordHealthImport({'sleep_hours': 7});
      expect(repo.healthScoreHistory(), hasLength(2));
    });

    test('the history survives a restart and Delete my data clears it', () async {
      final backend = MemoryBackend();
      final repo = await repoOn(backend);
      await repo.saveConversationProfile({...fullProfile, 'age': 82});
      expect(repo.healthScoreStatus, HealthScoreStatus.extrapolated);
      expect((await repoOn(backend)).healthScoreHistory().single.status, HealthScoreStatus.extrapolated);
      await repo.deleteMyData();
      expect(repo.healthScore, isNull);
      expect(repo.healthScoreHistory(), isEmpty);
      expect((await repoOn(backend)).healthScoreHistory(), isEmpty);
      expect(backend.text, isNull);
    });
  });
}
