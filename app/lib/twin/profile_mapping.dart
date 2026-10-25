/// Maps the app's confirmed profile (the field names of `server/lifetwin/core/models.py`,
/// plus the new inputs the conversation is gaining) to the on-device model's 11 inputs.
///
/// Nothing is filled in: an answer the person has not given, or gave as "not sure", is
/// left out, and the model then reports it in `survival.missing_inputs` by the package's
/// own input name. See lib/README-model.md for the table.
library;

/// The model's inputs, spelled as the package spells them (assets/model.json).
const modelInputs = [
  'age',
  'bmi',
  'sleep_hours',
  'vigorous_recreation_min_week',
  'moderate_recreation_min_week',
  'sedentary_min_day',
  'sex_nhanes',
  'smoking_status',
  'diabetes_diagnosed',
  'hypertension_diagnosed',
  'general_health',
];

/// NHANES RIAGENDR: 1 male, 2 female.
const sexCodes = {'male': 1, 'female': 2};

/// The package's smoking codes: 0 never, 1 former, 2 current. "unknown" is not an answer.
const smokingCodes = {'never': 0, 'former': 1, 'current': 2};

/// NHANES HSD010 self-rated health: 1 excellent … 5 poor.
const generalHealthCodes = {'excellent': 1, 'very_good': 2, 'good': 3, 'fair': 4, 'poor': 5};

/// Plain words for each model input, for "still needed" lists.
const modelInputLabels = {
  'age': 'age',
  'bmi': 'height and weight',
  'sleep_hours': 'hours of sleep',
  'vigorous_recreation_min_week': 'hard exercise each week',
  'moderate_recreation_min_week': 'moderate exercise each week',
  'sedentary_min_day': 'time spent sitting each day',
  'sex_nhanes': 'sex at birth',
  'smoking_status': 'smoking',
  'diabetes_diagnosed': 'diabetes',
  'hypertension_diagnosed': 'being told you have high blood pressure',
  'general_health': 'how you rate your health',
};

/// The app profile keys the model reads (the rest, such as alcohol or blood pressure
/// readings, are kept in the profile but are not model inputs).
const modelProfileKeys = {
  'age',
  'sex',
  'height_cm',
  'weight_kg',
  'sleep_hours',
  'smoking_status',
  'diabetes',
  'hypertension_diagnosed',
  'hypertension',
  'general_health',
  'sedentary_min_day',
  'vigorous_recreation_min_week',
  'moderate_recreation_min_week',
};

/// The `profile` for `LifeTwinEngine.assess()` / `compare()`. Only keys with a usable
/// answer are present; height and weight go in as a pair, so the package derives BMI.
Map<String, dynamic> toModelProfile(Map<String, dynamic> app) {
  final out = <String, dynamic>{};
  void put(String key, Object? value) {
    if (value != null) out[key] = value;
  }

  put('age', _number(app['age']));
  put('sex_nhanes', sexCodes[app['sex']]);
  final height = _number(app['height_cm']), weight = _number(app['weight_kg']);
  if (height != null && weight != null) {
    out['height_cm'] = height;
    out['weight_kg'] = weight;
  }
  put('sleep_hours', _number(app['sleep_hours']));
  put('smoking_status', smokingCodes[app['smoking_status']]);
  put('diabetes_diagnosed', _flag(app['diabetes']));
  put('hypertension_diagnosed', _flag(app['hypertension_diagnosed'] ?? app['hypertension']));
  put('general_health', _generalHealth(app['general_health']));
  // The intake's single "exercise_minutes_weekly" is not split into hard and moderate
  // minutes here: guessing the split would invent an answer.
  for (final key in ['sedentary_min_day', 'vigorous_recreation_min_week', 'moderate_recreation_min_week']) {
    put(key, _number(app[key]));
  }
  return out;
}

num? _number(Object? v) => v is num && v.isFinite ? v : null;

int? _flag(Object? v) => switch (v) {
  true || 1 => 1,
  false || 0 => 0,
  _ => null,
};

int? _generalHealth(Object? v) {
  if (v is int && v >= 1 && v <= 5) return v;
  if (v is num && v == v.roundToDouble() && v >= 1 && v <= 5) return v.toInt();
  if (v is String) return generalHealthCodes[v.trim().toLowerCase().replaceAll(' ', '_')];
  return null;
}

/// "a, b and c".
String joinPlain(List<String> items) => items.isEmpty
    ? ''
    : items.length == 1
    ? items.single
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
