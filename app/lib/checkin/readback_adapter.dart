import 'checkin_client.dart';

/// One answer in a read-back list ("Sleep: 7 hours").
class ReadbackItem {
  const ReadbackItem(this.field, this.label, this.value);
  final String field;
  final String label;

  /// The answer in words, or null when it was skipped.
  final String? value;
}

/// What the screen shows of the server's read-back, kept behind one small seam so the contract can move
/// without touching the screens.
abstract class ReadbackAdapter {
  /// The answers to list for [turn]: every question of the check-in, each with the value the server holds now
  /// (or null when it was skipped).
  List<ReadbackItem> items(CheckinTurn turn);

  /// The answers heard so far (`pending`), for the open question. Empty when none.
  List<ReadbackItem> heard(CheckinTurn turn);
}

/// The server contract (`app/lib/checkin/README.md`, "The read-back contract"): the answers are in
/// `state.pending` while questions are open and at the final read-back. Within one answer the last value
/// wins ("20, no wait 25" is 25): the server keeps one value per field, so showing `pending` shows the final value.
class ServerReadback implements ReadbackAdapter {
  const ServerReadback();

  static const labels = {
    'wellbeing': 'Feeling',
    'sleep_hours_last_night': 'Sleep',
    'vigorous_recreation_min': 'Out of breath',
    'moderate_recreation_min': 'Easy moves',
    'sedentary_min_day': 'Sitting',
    'sleep_hours': 'Sleep',
    'vigorous_recreation_min_week': 'Hard exercise a week',
    'moderate_recreation_min_week': 'Moderate exercise a week',
    'alcohol_drinks_weekly': 'Drinks this week',
    'smoking_status': 'Smoking',
    'weight_kg': 'Weight',
    'systolic_bp': 'Blood pressure',
  };

  static String _n(num x) => x == x.roundToDouble() ? '${x.round()}' : x.toStringAsFixed(1);

  /// "7 hours", "1 hour", "20 minutes", in plain words (older eyes first: no "h" or "min").
  static String _hours(num h) => '${_n(h)} ${h == 1 ? 'hour' : 'hours'}';
  static String _minutes(num m) {
    if (m >= 60 && m % 30 == 0) return _hours(m / 60);
    return '${_n(m)} ${m == 1 ? 'minute' : 'minutes'}';
  }

  static String? words(String field, Object? v) {
    if (v == null) return null;
    return switch (field) {
      'wellbeing' => switch ('$v') {
        'good' => 'Good',
        'okay' => 'Okay',
        'not_great' => 'Not great',
        final s => s,
      },
      'sleep_hours_last_night' || 'sleep_hours' when v is num => '${_hours(v)} a night',
      'vigorous_recreation_min' || 'moderate_recreation_min' when v is num => _minutes(v),
      'vigorous_recreation_min_week' || 'moderate_recreation_min_week' when v is num => '${_minutes(v)} a week',
      'sedentary_min_day' when v is num => '${_minutes(v)} a day',
      'alcohol_drinks_weekly' when v is num => '${v.round()} ${v == 1 ? 'drink' : 'drinks'}',
      'weight_kg' when v is num => '${_n(v)} kg',
      'systolic_bp' when v is num => 'top number ${v.round()}',
      _ => '$v',
    };
  }

  @override
  List<ReadbackItem> items(CheckinTurn turn) {
    final fields = [
      ...turn.questions,
      for (final f in turn.pending.keys)
        if (!turn.questions.contains(f)) f,
    ];
    return [for (final f in fields) ReadbackItem(f, labels[f] ?? f, words(f, turn.pending[f]))];
  }

  @override
  List<ReadbackItem> heard(CheckinTurn turn) => [
    for (final e in turn.pending.entries) ReadbackItem(e.key, labels[e.key] ?? e.key, words(e.key, e.value)),
  ];
}
