import 'package:lifesim/forecast/forecast_client.dart';
import 'package:lifesim/twin/twin_model.dart';

const modelVersion = 'personal-cox-v2-20261024T182404Z';

/// A `LifeTwinEngine.assess()` result (the package's shape, see
/// packages/lifetwin_on_device/test/fixtures/snapshot_response.json) with these
/// yearly survival fractions.
Map<String, dynamic> availableAssessment(
  Map<int, double> survival, {
  List<String> strengths = const ['smoking'],
  List<String> opportunities = const [],
}) => {
  'as_of_date': '2026-10-24',
  'profile_used': <String, dynamic>{},
  'input_provenance': {'source': 'profile_snapshot'},
  'survival': {
    'model_version': modelVersion,
    'causal_interpretation': false,
    'horizons_years': [1, 2, 3, 4, 5],
    'survival_probabilities': {for (final e in survival.entries) '${e.key}': e.value},
    'survival_percent_by_year': {for (final e in survival.entries) '${e.key}': 100 * e.value},
    'death_date': null,
    'estimated_age_at_death': null,
    'status': 'available',
    'interpretation': 'Estimated cumulative survival among similar survey profiles, not an individual death date or medical prognosis.',
  },
  'wellness_cards': <Object>[],
  'avatar': {
    'survival_display': 'annual_curve',
    'wellness_state': opportunities.isEmpty ? 'steady' : 'explore_changes',
    'strengths': strengths,
    'opportunities': opportunities,
  },
};

/// A result with no number: [status] and the package's message.
Map<String, dynamic> unavailableAssessment({
  String status = 'unsupported_age',
  String message = 'Annual estimates support ages 35–79 only.',
  List<String> missing = const [],
}) => {
  ...availableAssessment(const {}),
  'survival': {
    'model_version': modelVersion,
    'causal_interpretation': false,
    'horizons_years': [1, 2, 3, 4, 5],
    'survival_probabilities': null,
    'survival_percent_by_year': null,
    'death_date': null,
    'estimated_age_at_death': null,
    'status': status,
    'message': message,
    if (missing.isNotEmpty) 'missing_inputs': missing,
  },
  'avatar': {
    'survival_display': 'unavailable',
    'wellness_state': status == 'missing_inputs' ? 'needs_input' : 'steady',
    'strengths': <String>[],
    'opportunities': <String>[],
  },
};

Forecast forecastFrom(Map<String, dynamic> assessment) => Forecast.fromAssessment(TwinAssessment(assessment));
