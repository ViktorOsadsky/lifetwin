/// "Answer N more questions": the one path back to the answers the estimate still needs.
///
/// Every "still needed" surface (Home's score card, Still learning, Ideas, the Room pill, the
/// check-in's outlook card, the forecast) opens the same Mochi conversation
/// (`AgenticRoutes.answerMissing`): the onboarding conversation started from the saved profile
/// with `state.ask_only` set to these fields, so only they are asked, in the usual order, and an
/// answered field is never asked again. "I don't know" is fine: Mochi says the estimate needs
/// it and moves on, and the action stays here for later. Never a loop.
library;

/// The conversation's profile fields (the server's `HealthProfile`), the only keys sent.
const conversationFields = [
  'age',
  'sex',
  'height_cm',
  'weight_kg',
  'sleep_hours',
  'exercise_minutes_weekly',
  'smoking_status',
  'alcohol_drinks_weekly',
  'diabetes',
  'systolic_bp',
  'diastolic_bp',
  'general_health',
  'hypertension_diagnosed',
  'sedentary_min_day',
  'moderate_recreation_min_week',
  'vigorous_recreation_min_week',
];

/// The questions that answer the model's [missingInputs] (package names): BMI is height and
/// weight (only the one without a value), the rest are one question each. In the server's order.
List<String> missingQuestions(List<String> missingInputs, Map<String, dynamic> profile) {
  final fields = <String>{
    for (final m in missingInputs)
      ...switch (m) {
        'bmi' => [
          if (profile['height_cm'] == null) 'height_cm',
          if (profile['weight_kg'] == null) 'weight_kg',
          if (profile['height_cm'] != null && profile['weight_kg'] != null) ...['height_cm', 'weight_kg'],
        ],
        'sex_nhanes' => ['sex'],
        'diabetes_diagnosed' => ['diabetes'],
        _ => [m],
      },
  };
  const order = [
    'age',
    'sex',
    'smoking_status',
    'height_cm',
    'weight_kg',
    'sleep_hours',
    'general_health',
    'hypertension_diagnosed',
    'diabetes',
    'sedentary_min_day',
    'moderate_recreation_min_week',
    'vigorous_recreation_min_week',
  ];
  return [
    for (final f in order)
      if (fields.contains(f)) f,
  ];
}

/// The label of the one primary action: "Answer 1 more question" / "Answer 3 more questions".
String answerMoreLabel(int n) => n == 1 ? 'Answer 1 more question' : 'Answer $n more questions';

/// The flag on a rough score or lifespan: "Rough guide: 1 answer missing".
String roughMissingLabel(int n) => n == 1 ? 'Rough guide: 1 answer missing' : 'Rough guide: $n answers missing';

/// The conversation state that starts "Answer N more questions": the saved [profile] as
/// confirmed, and only [fields] asked (`ask_only`). Values the server cannot read (an
/// answer saved under another shape) are left out, so the question is asked, never guessed.
Map<String, dynamic> askOnlyState(Map<String, dynamic> profile, List<String> fields, {bool? memoryConsent}) => {
  'phase': 'idle',
  'confirmed_profile': {
    for (final f in conversationFields)
      if (profile[f] != null && !fields.contains(f)) f: _wire(f, profile[f]),
  },
  'ask_only': fields,
  'memory_consent': ?memoryConsent,
};

const _health = {1: 'excellent', 2: 'very_good', 3: 'good', 4: 'fair', 5: 'poor'};

Object? _wire(String field, Object? value) =>
    field == 'general_health' && value is num ? _health[value.toInt()] ?? value : value;
