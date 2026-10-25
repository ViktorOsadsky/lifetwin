// Host Flutter test of the ACTUAL app adapter/package. No copied lifespan algorithm.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/twin/lifespan.dart';
import 'package:lifesim/twin/twin_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('36 synthetic cases through the pinned app lifespan engine', () async {
    final out = Platform.environment['LIFESPAN_SWEEP_OUT']!;
    final ssa = jsonDecode(
      File(Platform.environment['LIFESPAN_SSA_SOURCE']!).readAsStringSync(),
    ) as Map;
    final model = await TwinModelService.load();
    final neural = jsonDecode(
      await rootBundle.loadString(
        'packages/lifetwin_on_device/assets/neural_model.json',
      ),
    ) as Map;
    final reference = Map<String, dynamic>.from(
      neural['reference_profile'] as Map,
    );
    final templates = <String, Map<String, dynamic>>{
      'healthy': {
        ...reference,
        'bmi': 23.0,
        'sleep_hours': 7.5,
        'vigorous_recreation_min_week': 75,
        'moderate_recreation_min_week': 150,
        'sedentary_min_day': 300,
        'general_health': 2,
      },
      'typical_lab_reference': reference,
      'unhealthy': {
        ...reference,
        'bmi': 30.0,
        'sleep_hours': 6.0,
        'vigorous_recreation_min_week': 0,
        'moderate_recreation_min_week': 30,
        'sedentary_min_day': 600,
        'smoking_status': 2,
        'diabetes_diagnosed': 1,
        'hypertension_diagnosed': 1,
        'general_health': 5,
      },
    };
    final records = <Map<String, dynamic>>[];
    for (final age in [35, 45, 55, 64, 70, 80]) {
      final ssaRow = (ssa['rows'] as List).cast<Map>().singleWhere(
        (r) => r['age'] == age,
      );
      for (final (sex, code) in [('male', 1), ('female', 2)]) {
        final remaining = (ssaRow[sex]['remaining_years'] as num).toDouble();
        for (final entry in templates.entries) {
          final input = {...entry.value, 'age': age, 'sex_nhanes': code};
          final a = model.assessModel(input);
          // Match the production repository gate: never estimate unsupported input.
          final e = a.rawLogRelativeHazard == null
              ? null
              : LifespanEstimate.forProfile(
                  a.profileUsed,
                  currentYear: 2026,
                  lab: model.projection,
                );
          final table = a.available
              ? estimateLifespanForProfile(a.profileUsed)
              : null;
          final projection = a.available
              ? model.projection!.assess(
                  a.profileUsed,
                  includeExtrapolation: true,
                )
              : null;
          final annual = projection?['annual'] as Map?;
          final gap = e == null ? null : e.expectedAge - (age + remaining);
          records.add({
            'age': age,
            'sex': sex,
            'profile': entry.key,
            'input': input,
            'effective_profile_used': a.profileUsed,
            'input_provenance': a.inputProvenance,
            'assessment_status': a.status,
            'health_score_status': a.healthScoreStatus.name,
            'assessment_extrapolated': a.extrapolated,
            'support_issues': a.survival['support_issues'],
            'health_index': a.healthScore,
            'percentile': a.ageGroupPercentile,
            'raw_log_relative_hazard': a.rawLogRelativeHazard,
            'five_year_survival_percent': a.percentByYear[5],
            'ssa_remaining_mean_years': remaining,
            'ssa_attained_mean_age': age + remaining,
            'app_summary_age': e?.expectedAge,
            'app_p25_age': e?.p25Age,
            'app_p75_age': e?.p75Age,
            'app_expected_year': e?.expectedYear,
            'app_headline': e?.headline,
            'app_caveat': e?.caveat,
            'app_status': e?.status.name,
            'app_extrapolated': e?.extrapolated,
            'projection_weight': e?.projectionWeight,
            'scheduled_projection_weight': lifespanProjectionWeight(age),
            'summary_method': e == null
                ? null
                : (e.projectionWeight == 1
                      ? 'projection_median'
                      : (e.projectionWeight == 0
                            ? 'personalized_cdc_mean'
                            : 'blend_cdc_mean_projection_median')),
            'app_median_crossing_extrapolated': e?.medianCrossingExtrapolated,
            'app_p25_open_ended': e?.p25OpenEnded,
            'app_open_ended': e?.openEnded,
            'app_p75_open_ended': e?.p75OpenEnded,
            'app_curve_first_age': e?.annualCurve.first.age,
            'app_curve_last_age': e?.annualCurve.last.age,
            'app_curve_last_survival_percent':
                e?.annualCurve.last.survivalPercent,
            'pure_cdc_mean_age': table?.expectedAgeAtDeath,
            'pure_cdc_p25_age': table?.age25thPercentile,
            'pure_cdc_p75_age': table?.age75thPercentile,
            'pure_projection_status': projection?['status'],
            'pure_projection_median_age': annual?['median_crossing_age'],
            'pure_projection_median_extrapolated':
                annual?['median_crossing_extrapolated'],
            'pure_projection_last_survival_percent':
                annual?['last_survival_percent'],
            'app_minus_ssa_attained_years': gap,
            'gap_is_lower_bound': e == null ? null : e.openEnded,
            'app_above_ssa_by_over_8': gap == null ? null : gap > 8,
            'absolute_gap_over_8': gap == null ? null : gap.abs() > 8,
          });
          if (e != null) {
            expect(e.p25Age, lessThanOrEqualTo(e.expectedAge));
            expect(e.expectedAge, lessThanOrEqualTo(e.p75Age));
            expect(e.expectedAge.isFinite, isTrue);
            expect(e.projectionWeight, lifespanProjectionWeight(age));
            expect(e.openEnded, e.openEnded && e.expectedAge >= lifespanEndAge);
          } else {
            expect(
              a.rawLogRelativeHazard,
              isNull,
              reason: 'Do not mask a supported input unexpectedly',
            );
          }
        }
      }
    }
    expect(records.length, 36);
    expect(
      records
          .map((r) => '${r['age']}/${r['sex']}/${r['profile']}')
          .toSet()
          .length,
      36,
    );
    final result = {
      'schema': 'lifetwin.lifespan_sanity.v0',
      'synthetic_only': true,
      'engine_head': Platform.environment['LIFESPAN_ENGINE_HEAD'],
      'model_version': model.modelVersion,
      'reference_profile_source': 'app/packages/lifetwin_on_device/assets/neural_model.json#reference_profile',
      'exact_lab_reference': reference,
      'templates': templates,
      'ssa_source': ssa,
      'records': records,
    };
    File(out).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
    );
    print(
      '36 synthetic cases recorded; ${records.where((r) => r['app_summary_age'] != null).length} available.',
    );
  });
}
