import 'dart:math' as math;

import 'model.dart';
import 'neural_hazard.dart';

/// An exploratory view of two different ways to chain short-horizon Cox curves.
class LifeTwinProjectionLab {
  LifeTwinProjectionLab(this.cox, this.neural);

  final LifeTwinModel cox;
  final NeuralHazardModel neural;

  Map<String, dynamic> assess(
    Map<String, dynamic> profile, {
    int maximumAge = 110,
    bool includeExtrapolation = true,
  }) {
    final current = cox.predict(profile);
    if (current['status'] != 'available') {
      return {
        'status': current['status'],
        'message': current['message'],
        'support_issues': current['support_issues'],
        'neural_hazard': null,
        'current_cox': current,
        'annual': null,
        'five_year': null,
      };
    }
    final age = (profile['age'] as num).toInt();
    if (age != profile['age']) {
      throw const FormatException('Projection requires age in completed years');
    }
    if (maximumAge <= age || maximumAge > 110) {
      throw const FormatException(
        'maximumAge must be above current age and at most 110',
      );
    }
    return {
      'status': 'available',
      'neural_hazard': neural.predict(profile),
      'current_cox': current,
      'annual': _project(profile, 1, maximumAge, includeExtrapolation),
      'five_year': _project(profile, 5, maximumAge, includeExtrapolation),
      'interpretation':
          'Both long-range curves are unvalidated mathematical experiments. The 50% crossing is a projected median threshold, not life expectancy or an individual death age.',
    };
  }

  Map<String, dynamic> _project(
    Map<String, dynamic> profile,
    int reestimateEveryYears,
    int maximumAge,
    bool includeExtrapolation,
  ) {
    final startingAge = (profile['age'] as num).toInt();
    var cumulative = 1.0;
    final points = <Map<String, dynamic>>[
      {'age': startingAge, 'survival_percent': 100.0, 'extrapolated': false},
    ];
    double? medianCrossingAge;
    for (var blockAge = startingAge;
        blockAge < maximumAge;
        blockAge += reestimateEveryYears) {
      if (blockAge > 79 && !includeExtrapolation) break;
      final future = {...profile, 'age': blockAge};
      final blockStart = cumulative;
      for (var years = 1;
          years <= math.min(reestimateEveryYears, maximumAge - blockAge);
          years++) {
        final conditional = cox.experimentalConditionalSurvival(future, years);
        final next = blockStart * conditional;
        final newAge = blockAge + years;
        if (medianCrossingAge == null && cumulative > 0.5 && next <= 0.5) {
          medianCrossingAge =
              newAge - 1 + (cumulative - 0.5) / (cumulative - next);
        }
        cumulative = next;
        points.add({
          'age': newAge,
          'survival_percent': 100 * cumulative,
          'extrapolated': blockAge > 79,
        });
      }
    }
    return {
      'reestimate_every_years': reestimateEveryYears,
      'points': points,
      'median_crossing_age': medianCrossingAge,
      'median_crossing_extrapolated': medianCrossingAge != null &&
          points.firstWhere(
                (point) => (point['age'] as int) >= medianCrossingAge!,
              )['extrapolated'] ==
              true,
      'last_age': points.last['age'],
      'last_survival_percent': points.last['survival_percent'],
      'label': reestimateEveryYears == 1
          ? 'Age updated every year'
          : 'Age updated every five years',
    };
  }
}
