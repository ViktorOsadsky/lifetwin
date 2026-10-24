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
