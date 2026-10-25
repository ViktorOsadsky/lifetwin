import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';

import 'store_and_checkin_test.dart' show fullProfile;

/// Owner ruling (2026-10-24): with 1 or 2 of the 11 inputs missing, a ROUGH, flagged estimate,
/// marginalised over the reference people of the same sex and age band; 3+ missing, none.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async => model = await TwinModelService.load());

  Map<String, dynamic> without(List<String> keys) => {...fullProfile}..removeWhere((k, _) => keys.contains(k));

  test('1 and 2 missing give a non-null score, flagged rough, with the missing list kept', () {
    for (final gone in [
      ['vigorous_recreation_min_week'],
      ['vigorous_recreation_min_week', 'smoking_status'],
      ['height_cm', 'weight_kg'], // one model input (bmi)
    ]) {
      final a = model.assess(without(gone));
      expect(a.healthScoreStatus, HealthScoreStatus.roughMissing, reason: '$gone');
      expect(a.roughMissing, isTrue);
      expect(a.healthScore, isNotNull);
      expect(a.ageGroupPercentile, isNotNull);
      expect(a.survivalByYear.length, 5);
      expect(a.missingCount, gone.first == 'height_cm' ? 1 : gone.length);
      // The placeholder never shows as an answer.
      for (final m in a.missingInputs) {
        expect(a.profileUsed[m], isNull);
      }
    }
  });

  test('3 missing: no estimate, as before', () {
    final a = model.assess(without(['vigorous_recreation_min_week', 'smoking_status', 'sleep_hours']));
    expect(a.healthScore, isNull);
    expect(a.healthScoreStatus, HealthScoreStatus.missingInputs);
    expect(a.missingCount, 3);
  });

  test('under 18 stays null', () {
    final a = model.assess({
      ...without(['smoking_status']),
      'age': 16,
    });
    expect(a.healthScore, isNull);
    // The package reports the missing answer first, as before; never a rough number.
    expect(a.healthScoreStatus, HealthScoreStatus.missingInputs);
    expect(a.roughMissing, isFalse);
  });

  test('the score is the mean of the band\'s hazards: a missing smoking answer is not "never smoked"', () {
    final rough = model.assess(without(['smoking_status']));
    final never = model.assess({...fullProfile, 'smoking_status': 'never'});
    final former = model.assess({...fullProfile, 'smoking_status': 'former'});
    final current = model.assess({...fullProfile, 'smoking_status': 'current'});
    final s = rough.rawLogRelativeHazard!;
    // Men 40–50 in the survey include smokers, so the average hazard is above a never smoker's.
    expect(s, greaterThan(never.rawLogRelativeHazard! + 0.01));
    expect(s, lessThan(current.rawLogRelativeHazard!));
    // log of the mean of exp(score) over the three groups, weighted by the band's shares.
    final base = never.rawLogRelativeHazard!;
    final f = former.rawLogRelativeHazard! - base, c = current.rawLogRelativeHazard! - base;
    final shift = s - base;
    expect(math.exp(shift), inInclusiveRange(1.0, math.exp(math.max(f, c))));
    expect(rough.healthScore, lessThan(never.healthScore!));
  });

  test('answering the missing field replaces the rough score with the exact one; the history flags it', () async {
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
    await repo.saveConversationProfile(without(['vigorous_recreation_min_week']));
    expect(repo.healthScoreStatus, HealthScoreStatus.roughMissing);
    expect(repo.missingCount, 1);
    expect(repo.missingInputs, ['vigorous_recreation_min_week']);
    expect(repo.healthScore, isNotNull);
    expect(repo.lifespanEstimate, isNotNull);
    final rough = repo.healthScore;
    await repo.saveConversationProfile({'vigorous_recreation_min_week': 60});
    expect(repo.healthScoreStatus, HealthScoreStatus.available);
    expect(repo.missingCount, 0);
    expect(repo.healthScore, model.assess(fullProfile).healthScore);
    expect(repo.healthScore, isNot(rough));
    final points = repo.healthScoreHistory();
    expect(points.first.roughMissing, isTrue);
    expect(points.first.toJson()['rough_missing'], isTrue);
    expect(points.last.roughMissing, isFalse);
    expect(points.last.toJson().containsKey('rough_missing'), isFalse);
    expect(HealthScorePoint.fromJson(points.first.toJson()).roughMissing, isTrue);
  });

  test('the Experiment: other levers move the rough score; a missing lever cannot be set', () {
    final base = model.assess(without(['vigorous_recreation_min_week'])).profileUsed;
    final c = model.compare({
      'current_profile': base,
      'alternative_profile': {...base, 'sleep_hours': 8},
    });
    expect(c['health_score_current'], isNotNull);
    expect(c['health_score_alternative'], isNotNull);
    expect(c['modeled_difference_percentage_points'], isNotNull);
    final moved = model.compare({
      'current_profile': base,
      'alternative_profile': {...base, 'vigorous_recreation_min_week': 150},
    });
    expect(moved['health_score_alternative'], isNull);
    expect((moved['alternative'] as Map)['status'], 'missing_inputs');
  });
}
