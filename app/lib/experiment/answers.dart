import '../twin/profile_mapping.dart';
import 'experiment_copy.dart';

/// Plain words for the model's inputs and the person's own answers, for "Still learning",
/// "What I know" and "Rare answers". Nothing here fills in a missing answer, and no BMI is shown.
abstract final class Answers {
  /// "Time spent sitting each day": the package input in plain words, capitalised.
  static String label(String modelInput) {
    final s = modelInputLabels[modelInput] ?? modelInput;
    return s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
  }

  /// The change conversation's `field` (a profile field name) for a model input.
  static String changeField(String modelInput) => switch (modelInput) {
    'sex_nhanes' => 'sex',
    'bmi' => 'weight_kg',
    'diabetes_diagnosed' => 'diabetes',
    _ => modelInput,
  };

  /// The person's answer in words, or null when there is nothing plain to say (height and
  /// weight are never echoed as a number).
  static String? text(String modelInput, Object? v) {
    if (v is! num) return null;
    return switch (modelInput) {
      'age' => '${v.round()} years',
      'sex_nhanes' => v == 1 ? 'Male' : 'Female',
      'sleep_hours' => '${ExperimentCopy.hours(v)} a night',
      'vigorous_recreation_min_week' || 'moderate_recreation_min_week' => '${ExperimentCopy.duration(v)} a week',
      'sedentary_min_day' => '${ExperimentCopy.duration(v)} a day',
      'smoking_status' => switch (v.round()) {
        0 => 'Never smoked',
        1 => 'Former smoker',
        _ => 'Smokes now',
      },
      'diabetes_diagnosed' || 'hypertension_diagnosed' => v == 1 ? 'Yes' : 'No',
      'general_health' => const ['', 'Excellent', 'Very good', 'Good', 'Fair', 'Poor'][v.round().clamp(1, 5)],
      _ => null,
    };
  }

  /// The model inputs a rare-answer message names: "vigorous_recreation_min_week is outside ...".
  static String? issueField(List<String> supportIssues) {
    for (final s in supportIssues) {
      final first = s.split(' ').first;
      if (modelInputLabels.containsKey(first)) return first;
    }
    return null;
  }
}
