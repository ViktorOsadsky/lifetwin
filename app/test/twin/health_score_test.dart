import 'dart:convert';
import 'dart:io';

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

  test('the score is predict()\'s log_relative_hazard_score exactly, for every golden vector', () {
    for (var i = 0; i < golden.length; i++) {
      final a = model.assessModel(g(i));
      final predicted = model.engine.model.predict(g(i));
      expect(predicted['status'], 'available');
      expect(a.healthScore, predicted['log_relative_hazard_score']);
      expect(a.healthScore, closeTo((golden[i]['log_relative_hazard_score'] as num).toDouble(), 1e-12));
      expect(a.healthScoreStatus, HealthScoreStatus.available);
    }
  });

  test('missing inputs: no number, the status and the model\'s message, nothing filled in', () {
    final a = model.assessModel({...g(0)}..remove('bmi'));
    expect(a.healthScore, isNull);
    expect(a.healthScoreStatus, HealthScoreStatus.missingInputs);
    expect(a.message, isNotEmpty);
  });

  test('under 30 and over 85 are unsupported_age', () {
    for (final age in [29, 86]) {
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
      expect(a.healthScore, a.survival['log_relative_hazard_score']);
      expect(a.healthScore, isNotNull);
    }
    final anchor = model.assessModel({...g(0), 'age': 35}).healthScore!;
    final older = model.assessModel({...g(0), 'age': 34}).healthScore!;
    expect(older, lessThan(anchor)); // a year younger: lower modelled risk
    expect(model.assessModel({...g(0), 'age': 79}).healthScoreStatus, HealthScoreStatus.available);
  });

  group('repository', () {
    var now = DateTime(2026, 10, 26, 9);
    Future<TwinRepository> repoOn(StoreBackend b) async =>
        TwinRepository(model: model, store: await TwinStore.open(b), clock: () => now);

    test('healthScore, status and message follow the current assessment', () async {
      final repo = await repoOn(MemoryBackend());
      expect(repo.healthScore, isNull);
      expect(repo.healthScoreStatus, isNull);
      await repo.saveConversationProfile({...fullProfile, 'weight_kg': null, 'height_cm': null});
      expect(repo.healthScore, isNull);
      expect(repo.healthScoreStatus, HealthScoreStatus.missingInputs);
      expect(repo.healthScoreMessage, isNotEmpty);
      await repo.saveConversationProfile(fullProfile);
      expect(repo.healthScoreStatus, HealthScoreStatus.available);
      expect(repo.healthScore, repo.current!.survival['log_relative_hazard_score']);
    });

    test('history grows on a feeding check-in, not on a non-feeding one, and is append-only', () async {
      final repo = await repoOn(MemoryBackend());
      await repo.saveConversationProfile(fullProfile);
      final first = repo.healthScoreHistory();
      expect(first, hasLength(1));
      expect(first.single.score, repo.healthScore);
      expect(first.single.status, HealthScoreStatus.available);
      expect(first.single.modelVersion, model.modelVersion);
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
      await repo.saveConversationProfile({...fullProfile, 'age': 29});
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
