/// Short, plain labels for confirmed answers, for the read-back value card
/// (V-3) and "Built from your answers" (V-9). They only restate the value.
/// Returns (profile key, label) pairs in profile order.
List<(String, String)> profileLabels(Map<String, dynamic> profile, {required bool imperial}) {
  final out = <(String, String)>[];
  final sys = profile['systolic_bp'], dia = profile['diastolic_bp'];
  for (final e in profile.entries) {
    final v = e.value;
    if (v == null) continue;
    if (e.key == 'diastolic_bp' && sys is num) continue; // shown with the top number
    final label = switch (e.key) {
      'age' => 'Age $v',
      'sex' => v == 'female' ? 'Female' : (v == 'male' ? 'Male' : '$v'),
      'height_cm' when v is num => _height(v, imperial),
      'weight_kg' when v is num => imperial ? '${(v * 2.20462).round()} lb' : '${_num(v)} kg',
      'sleep_hours' when v is num => 'Sleep ${_num(v)} h',
      'exercise_minutes_weekly' => 'Exercise $v min/week',
      'smoking_status' => switch (v) {
        'never' => 'Never smoked',
        'former' => 'Former smoker',
        'current' => 'Smokes now',
        _ => 'Smoking: not sure',
      },
      'alcohol_drinks_weekly' when v is num => '${_num(v)} ${v == 1 ? 'drink' : 'drinks'} a week',
      'diabetes' => v == true ? 'Diabetes: yes' : 'Diabetes: no',
      'systolic_bp' => dia is num ? 'Blood pressure $v/$dia' : 'Blood pressure top number $v',
      'diastolic_bp' => 'Blood pressure bottom number $v',
      'general_health' => switch (v) {
        'excellent' || 'very_good' || 'good' || 'fair' || 'poor' => 'Health: ${'$v'.replaceAll('_', ' ')}',
        _ => 'Health: not sure',
      },
      'hypertension_diagnosed' => switch (v) {
        true => 'Told you have high blood pressure: yes',
        false => 'Told you have high blood pressure: no',
        _ => 'Told you have high blood pressure: not sure',
      },
      'sedentary_min_day' => v is num ? 'Sitting: ${_duration(v, 'a day')}' : 'Sitting: not sure',
      'moderate_recreation_min_week' =>
        v is num ? 'Easier activity: ${_minutes(v)}' : 'Easier activity: not sure',
      'vigorous_recreation_min_week' =>
        v is num ? 'Out-of-breath activity: ${_minutes(v)}' : 'Out-of-breath activity: not sure',
      _ => null,
    };
    if (label != null) out.add((e.key, label));
  }
  return out;
}

String _height(num cm, bool imperial) {
  if (!imperial) return '${cm.round()} cm';
  final inches = (cm / 2.54).round();
  return '${inches ~/ 12} ft ${inches % 12} in';
}

String _num(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

/// "none" for 0, else "150 min a week".
String _minutes(num v) => v <= 0 ? 'none' : '${_num(v)} min a week';

/// Minutes as hours when it is a round-ish amount: "6 h a day", "45 min a day".
String _duration(num minutes, String per) {
  if (minutes < 60) return '${_num(minutes)} min $per';
  return '${_num((minutes / 60 * 10).round() / 10)} h $per';
}
