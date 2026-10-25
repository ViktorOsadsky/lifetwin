// EPHEMERAL QA only. Copy into the isolated validation app AFTER owner approval/merge.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/demo/demo_seed.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/lifespan.dart' show estimateLifespanForProfile;
import 'package:lifesim/twin/twin_repository.dart';

const qaNow = '2026-10-24T12:00:00';
const proposedHead = '614e37dfb1cdb390010f9f6f6b0edd35a5b5baf8';

Map<String, dynamic> snapshot(String id, TwinRepository repo) {
  final a = repo.current!;
  final e = repo.lifespanEstimate;
  final p = a.profileUsed;
  final age = p['age'] as num?;
  final projectionProfile = age != null && age >= 35 && age <= 79
      ? {...p, 'age': age.floor()}
      : p;
  final table = e == null ? null : estimateLifespanForProfile(p);
  final projection = e == null
      ? null
      : repo.model.projection?.assess(
          projectionProfile,
          includeExtrapolation: true,
        );
  return {
    'projection_profile_used': projectionProfile,
    'projection_component': projection?['annual'],
    'life_table_component': table == null
        ? null
        : {
            'expected_age': table.expectedAgeAtDeath,
            'p25_age': table.age25thPercentile,
            'p75_age': table.age75thPercentile,
            'points': [
              for (final (age, survival) in table.survivalCurve)
                if (age == age.roundToDouble())
                  {
                    'age': age.round(),
                    'survival_percent': survival * 100,
                    'extrapolated': true,
                  },
            ],
          },
    'id': id,
    'profile_used': a.profileUsed,
    'confirmed_profile': repo.profile,
    'input_provenance': a.inputProvenance,
    'status': a.status,
    'missing_inputs': a.missingInputs,
    'health_score_status': a.healthScoreStatus.name,
    'health_score': repo.healthScore,
    'percentile': repo.ageGroupPercentile,
    'group_band': repo.ageGroupBand,
    'group_size': repo.ageGroupSize,
    'group_label': repo.healthGroupLabel,
    'raw_log_hazard': repo.rawLogRelativeHazard,
    'five_year_probability': a.survivalByYear[5],
    'five_year_percent': a.percentByYear[5],
    'assessment_extrapolated': a.extrapolated,
    'lifespan': lifespanJson(e),
  };
}

Map<String, dynamic>? lifespanJson(LifespanEstimate? e) => e == null
    ? null
    : {
        'method': e.projectionWeight == 0
            ? 'life_table_mean'
            : (e.projectionWeight == 1
                  ? 'yearly_cox_median'
                  : 'blend_life_table_mean_yearly_cox_median'),
        'projection_weight': e.projectionWeight,
        'selected_curve_source': e.projectionWeight < 0.5
            ? 'life_table'
            : 'yearly_cox_projection',
        'expected_age': e.expectedAge,
        'p25_age': e.p25Age,
        'p75_age': e.p75Age,
        'expected_year': e.expectedYear,
        'status': e.status.name,
        'extrapolated': e.extrapolated,
        'median_crossing_extrapolated': e.medianCrossingExtrapolated,
        'p25_open_ended': e.p25OpenEnded,
        'open_ended': e.openEnded,
        'p75_open_ended': e.p75OpenEnded,
        'headline': e.headline,
        'caveat': e.caveat,
        'points': [
          for (final p in e.annualCurve)
            {
              'age': p.age,
              'survival_percent': p.survivalPercent,
              'extrapolated': p.extrapolated,
            },
        ],
      };

Future<Map<String, dynamic>> medianProfile(
  TwinModelService model,
  TwinAssessment rosa,
) async {
  final spec = model.engine.model.spec;
  final coef = [
    for (final c in spec['coefficients'] as List) (c as num).toDouble(),
  ];
  final centre = [
    for (final c in spec['feature_center'] as List) (c as num).toDouble(),
  ];
  final data = await rootBundle.load(
    'packages/lifetwin_on_device/assets/support_reference.f64.gz',
  );
  final bytes = Uint8List.fromList(
    gzip.decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    ),
  );
  final view = ByteData.sublistView(bytes);
  final band = rosa.ageGroupBand!.split('–').map(num.parse).toList();
  final female = rosa.profileUsed['sex_nhanes'] == 2;
  final rows = <({double score, Map<String, dynamic> profile})>[];
  for (var r = 0; r < view.lengthInBytes ~/ (8 * coef.length); r++) {
    final x = [
      for (var i = 0; i < coef.length; i++)
        view.getFloat64((r * coef.length + i) * 8, Endian.little),
    ];
    final age = x[0] * 10 + 55;
    if ((x[8] == 1) != female || age < band[0] || age > band[1]) continue;
    var score = 0.0, health = 1;
    for (var i = 0; i < coef.length; i++) {
      if (i != 0 && i != 8) score += (x[i] - centre[i]) * coef[i];
    }
    for (var level = 2; level <= 5; level++) {
      if (x[11 + level] == 1) health = level;
    }
    rows.add((
      score: score,
      profile: {
        'age': rosa.profileUsed['age'],
        'sex_nhanes': female ? 2 : 1,
        'bmi': x[1] > 0 ? 23 - 5 * x[1] : (x[2] > 0 ? 27 + 5 * x[2] : 25.0),
        'sleep_hours': x[3] > 0 ? 7 - x[3] : (x[4] > 0 ? 8 + x[4] : 7.5),
        'vigorous_recreation_min_week': math.exp(x[5] * math.log(76)) - 1,
        'moderate_recreation_min_week': math.exp(x[6] * math.log(151)) - 1,
        'sedentary_min_day': 360 + 120 * x[7],
        'smoking_status': x[10] == 1 ? 2 : (x[9] == 1 ? 1 : 0),
        'diabetes_diagnosed': x[11].round(),
        'hypertension_diagnosed': x[12].round(),
        'general_health': health,
      },
    ));
  }
  rows.sort((a, b) => a.score.compareTo(b.score));
  expect(rows.length, rosa.ageGroupSize);
  return rows[(rows.length + 1) ~/ 2 - 1].profile;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'QA107 approved merged engine: synthetic repository and canonical capture',
    (tester) async {
      const approved = bool.fromEnvironment('QA107_ENGINE_APPROVED');
      const mergedSha = String.fromEnvironment('QA107_MERGED_SHA');
      expect(
        approved,
        isTrue,
        reason: 'Owner approval and merge are REQUIRED before execution.',
      );
      expect(mergedSha, matches(RegExp(r'^[0-9a-f]{40}$')));
      final report = <String, dynamic>{
        'schema': 'lifetwin.qa107.engine.v2',
        'synthetic_only': true,
        'score_scale': 'cox_centered_v1',
        'owner_approved_and_merged': approved,
        'merged_sha': mergedSha,
        'reviewed_proposed_head': proposedHead,
        'now': qaNow,
        'records': <Map<String, dynamic>>[],
        'guards': <Map<String, dynamic>>[],
      };
      binding.reportData = report;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Synthetic QA107 engine validation')),
        ),
      );
      final now = DateTime.parse(qaNow);
      final rosa = await openTwin(
        demo: true,
        backend: MemoryBackend(),
        now: () => now,
      );
      final repos = <TwinRepository>[rosa];
      try {
        final records = report['records'] as List<Map<String, dynamic>>;
        records.add(snapshot('rosa_seed_effective', rosa));
        final profiles = <String, Map<String, dynamic>>{
          'synthetic_45_male': {
            ...rosaProfile,
            'age': 45,
            'sex': 'male',
            'height_cm': 175.0,
            'weight_kg': 76.56,
            'sleep_hours': 7.0,
            'general_health': 2,
            'moderate_recreation_min_week': 150,
            'vigorous_recreation_min_week': 75,
            'sedentary_min_day': 420,
          },
          'synthetic_58_female': {
            ...rosaProfile,
            'age': 58,
            'height_cm': 165.0,
            'weight_kg': 78.95,
            'smoking_status': 'former',
            'hypertension_diagnosed': true,
            'sedentary_min_day': 540,
          },
          'synthetic_76_male': {
            ...rosaProfile,
            'age': 76,
            'sex': 'male',
            'height_cm': 175.0,
            'weight_kg': 82.69,
            'sleep_hours': 7.0,
            'smoking_status': 'former',
            'hypertension_diagnosed': true,
            'moderate_recreation_min_week': 120,
          },
        };
        for (final entry in profiles.entries) {
          final repo = TwinRepository(
            model: rosa.model,
            store: await TwinStore.open(MemoryBackend()),
            clock: () => now,
          );
          repos.add(repo);
          await repo.saveOnboarding({
            'confirmed_profile': entry.value,
            'memory_consent': false,
          });
          records.add(snapshot(entry.key, repo));
        }
        for (final repo in repos) {
          expect(repo.current!.available, isTrue);
          expect(repo.healthScore, isNotNull);
          expect(repo.healthScore!.isFinite, isTrue);
          expect(repo.ageGroupPercentile, inInclusiveRange(0, 100));
          expect(repo.lifespanEstimate, isNotNull);
          final before = jsonEncode(repo.profile);
          final p = repo.current!.profileUsed;
          final up = {...p, 'bmi': (p['bmi'] as num) + 1};
          final c = repo.model.compare({
            'current_profile': p,
            'alternative_profile': up,
          });
          expect(c['weight_guard'], isTrue);
          expect(
            (c['modeled_difference_percentage_points'] as Map).values,
            everyElement(0.0),
          );
          expect(c['health_score_delta'], 0.0);
          expect(c['health_score_alternative'], c['health_score_current']);
          expect(
            (c['alternative'] as Map)['survival_percent_by_year'],
            (c['current'] as Map)['survival_percent_by_year'],
          );
          expect(
            jsonEncode(repo.profile),
            before,
            reason: 'Hypothetical guard never mutates confirmed data.',
          );
          (report['guards'] as List).add({
            'profile_used': p,
            'alternative_profile': up,
            'result': c,
          });
        }
        final median = await medianProfile(rosa.model, rosa.current!);
        final reference = rosa.model.assessModel(median);
        expect(reference.available, isTrue);
        expect(reference.healthScore, closeTo(0.0, 1e-9));
        report['reference_person'] = {
          'profile_used': reference.profileUsed,
          'health_score': reference.healthScore,
          'percentile': reference.ageGroupPercentile,
          'group_band': reference.ageGroupBand,
        };
        // Record fallback status and known discontinuities without asserting continuity.
        final edges = <Map<String, dynamic>>[];
        for (final age in [
          18,
          34,
          35,
          39,
          40,
          44,
          45,
          70,
          74,
          75,
          78,
          79,
          80,
          85,
        ]) {
          final repo = TwinRepository(
            model: rosa.model,
            store: await TwinStore.open(MemoryBackend()),
            clock: () => now,
          );
          repos.add(repo);
          await repo.saveOnboarding({
            'confirmed_profile': {...rosaProfile, 'age': age},
          });
          final e = repo.lifespanEstimate;
          expect(e, isNotNull);
          final w = age <= 35 || age >= 79
              ? 0.0
              : (age < 45
                    ? (age - 35) / 10
                    : (age <= 70 ? 1.0 : (79 - age) / 9));
          expect(e!.projectionWeight, w);
          expect(e.extrapolated, w < 0.5);
          edges.add(snapshot('edge_$age', repo));
        }
        report['edge_records'] = edges;
        final masked = <Map<String, dynamic>>[];
        for (final age in [17, 86]) {
          final repo = TwinRepository(
            model: rosa.model,
            store: await TwinStore.open(MemoryBackend()),
            clock: () => now,
          );
          repos.add(repo);
          await repo.saveOnboarding({
            'confirmed_profile': {...rosaProfile, 'age': age},
          });
          expect(repo.healthScore, isNull);
          expect(repo.rawLogRelativeHazard, isNull);
          expect(repo.current!.survivalByYear, isEmpty);
          expect(repo.lifespanEstimate, isNull);
          masked.add(snapshot('masked_$age', repo));
        }
        report['masked_records'] = masked;
        final fractional = <Map<String, dynamic>>[];
        for (final age in [34.5, 35.5, 40.5, 74.5, 79.5]) {
          final repo = TwinRepository(
            model: rosa.model,
            store: await TwinStore.open(MemoryBackend()),
            clock: () => now,
          );
          repos.add(repo);
          await repo.saveOnboarding({
            'confirmed_profile': {...rosa.profile, 'age': age},
          });
          expect(repo.current!.missingInputs, contains('age'));
          expect(repo.healthScore, isNull);
          expect(repo.lifespanEstimate, isNull);
          final p = {...rosa.current!.profileUsed, 'age': age};
          final e = LifespanEstimate.forProfile(
            p,
            currentYear: now.year,
            lab: rosa.model.projection,
          );
          expect(
            e,
            isNotNull,
            reason: 'Direct wrapper floors projection age; repository correctly rejects fractional confirmed age.',
          );
          final pp = age >= 35 && age <= 79 ? {...p, 'age': age.floor()} : p;
          final table = estimateLifespanForProfile(p);
          fractional.add({
            'id': 'direct_fractional_$age',
            'profile_used': p,
            'boundary': 'direct_wrapper_only_not_confirmed_profile',
            'repository_gate': snapshot('fractional_repo_$age', repo),
            'projection_profile_used': pp,
            'projection_component': rosa.model.projection!.assess(
              pp,
              includeExtrapolation: true,
            )['annual'],
            'life_table_component': {
              'expected_age': table.expectedAgeAtDeath,
              'p25_age': table.age25thPercentile,
              'p75_age': table.age75thPercentile,
              'points': [
                for (final (a, s) in table.survivalCurve)
                  if (a == a.roundToDouble())
                    {
                      'age': a.round(),
                      'survival_percent': 100 * s,
                      'extrapolated': true,
                    },
              ],
            },
            'lifespan': lifespanJson(e),
            'lifespan_available': e != null,
            'expected_age': e?.expectedAge,
            'projection_weight': e?.projectionWeight,
          });
        }
        report['fractional_records'] = fractional;
        final missing = {...rosa.current!.profileUsed}..remove('sleep_hours');
        final incomplete = rosa.model.assessModel(missing);
        expect(incomplete.healthScore, isNull);
        expect(incomplete.rawLogRelativeHazard, isNull);
        expect(incomplete.survivalByYear, isEmpty);
        expect(
          LifespanEstimate.forProfile(
            missing,
            currentYear: now.year,
            lab: rosa.model.projection,
          ),
          isNull,
        );
        report['missing_input'] = {
          'profile_used': missing,
          'status': incomplete.status,
          'health_score': incomplete.healthScore,
          'five_year_probability': incomplete.survivalByYear[5],
          'lifespan': null,
        };
        report['device_assertions_passed'] = true;
      } finally {
        for (final repo in repos) {
          repo.dispose();
        }
      }
    },
  );
}
