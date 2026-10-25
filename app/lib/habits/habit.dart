/// One habit record as the phone stores it and the server reads it
/// (`HabitRecord` in contracts/habits.*.schema.json). Pure Dart: no Flutter.
library;

enum HabitStatus { proposed, active, dismissed, graduated }

/// A day's answer to the check-in habit question. A day with no result is
/// unknown, which is never the same as [notToday].
enum HabitResult {
  done('done'),
  partly('partly'),
  notToday('not_today');

  const HabitResult(this.wire);
  final String wire;

  /// Done or sort of done: the day counts as a habit day.
  bool get isHabitDay => this != notToday;

  static HabitResult parse(Object? wire) => values.firstWhere(
    (r) => r.wire == wire,
    orElse: () => throw FormatException('unknown habit result', wire),
  );
}

class Habit {
  const Habit({
    required this.id,
    required this.catalogId,
    required this.pillar,
    required this.anchor,
    required this.tinyAction,
    required this.source,
    required this.status,
    this.whyWords,
    this.lever,
    this.startedOn,
    this.dismissedUntil,
  });

  final String id;
  final String catalogId;

  /// move, sleep, sit_less, unwind, smoke_free, connect or nourish.
  final String pillar;

  /// "After lunch": the routine the habit hangs on (at most 80 characters).
  final String anchor;

  /// "walk for 2 minutes outside" (at most 80 characters).
  final String tinyAction;

  /// The person's own reason, in their words, when the idea came from them.
  final String? whyWords;

  /// The model lever behind it (quit_smoking, vigorous_activity, ...), or null.
  final String? lever;

  /// said, model_lever or guideline.
  final String source;
  final HabitStatus status;

  /// Phone-local days, YYYY-MM-DD.
  final String? startedOn;
  final String? dismissedUntil;

  bool get isActive => status == HabitStatus.active;

  Habit copyWith({
    String? anchor,
    String? tinyAction,
    String? whyWords,
    HabitStatus? status,
    String? startedOn,
    String? dismissedUntil,
  }) => Habit(
    id: id,
    catalogId: catalogId,
    pillar: pillar,
    anchor: anchor ?? this.anchor,
    tinyAction: tinyAction ?? this.tinyAction,
    whyWords: whyWords ?? this.whyWords,
    lever: lever,
    source: source,
    status: status ?? this.status,
    startedOn: startedOn ?? this.startedOn,
    dismissedUntil: dismissedUntil ?? this.dismissedUntil,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'catalog_id': catalogId,
    'pillar': pillar,
    'anchor': anchor,
    'tiny_action': tinyAction,
    'why_words': whyWords,
    'lever': lever,
    'source': source,
    'status': status.name,
    'started_on': startedOn,
    'dismissed_until': dismissedUntil,
  };

  /// Throws [FormatException] for anything that is not a habit record.
  static Habit fromJson(Object? json) {
    if (json is! Map) throw const FormatException('habit is not an object');
    String text(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) throw FormatException('habit $key missing');
      return value;
    }

    String? optional(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String) throw FormatException('habit $key is not text');
      return value;
    }

    final status = HabitStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => throw const FormatException('unknown habit status'),
    );
    return Habit(
      id: text('id'),
      catalogId: text('catalog_id'),
      pillar: text('pillar'),
      anchor: text('anchor'),
      tinyAction: text('tiny_action'),
      whyWords: optional('why_words'),
      lever: optional('lever'),
      source: text('source'),
      status: status,
      startedOn: optional('started_on'),
      dismissedUntil: optional('dismissed_until'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Habit && _same(toJson(), other.toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);
}

bool _same(Map<String, Object?> a, Map<String, Object?> b) =>
    a.length == b.length && a.keys.every((k) => a[k] == b[k]);
