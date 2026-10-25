/// A thin client for `/api/habits/*` (contracts/habits.*.schema.json). The
/// server is stateless: every call sends the person's age, the phone's own day
/// and the habit records the phone holds.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../voice/api_base.dart';
import 'habit.dart';

/// The profile fields the habits server reads (for model levers, ages 30+).
const habitProfileFields = {'smoking_status', 'exercise_minutes_weekly', 'sleep_hours'};

enum HabitAction { accept, edit, dismiss }

enum HabitQuestionAction { ask, reply, skip }

/// Any habits response. Which fields are set depends on the route and status.
class HabitsReply {
  const HabitsReply({
    required this.status,
    required this.message,
    required this.mood,
    this.emergency = false,
    this.safety,
    this.habit,
    this.supports,
    this.sourceTitle,
    this.sourceUrl,
    this.habitId,
    this.question,
    this.result,
    this.weekStart,
    this.habitDaysThisWeek,
    this.goodWeekThisWeek,
    this.goodWeeksTotal,
  });

  /// propose: proposed, pending, at_limit, nothing_new, age_not_supported, safety.
  /// update: active, proposed, dismissed, at_limit, age_not_supported, safety.
  /// question: asking, answered, not_understood, skipped, no_active_habit,
  /// age_not_supported, safety. week: ok, age_not_supported.
  final String status;

  /// What Mochi says. Shown or spoken as is.
  final String message;

  /// happy, proud, celebrate, cozy or concerned.
  final String mood;

  /// An emergency line is in [message]: show a "Call 911" button the person taps.
  final bool emergency;

  /// The safety gate that answered (emergency, eating_care, supplement, medical, alcohol).
  final String? safety;

  /// The proposal (propose) or the changed habit (update).
  final Habit? habit;
  final String? supports;
  final String? sourceTitle;
  final String? sourceUrl;

  final String? habitId;
  final String? question;

  /// question, answered only. Null is unknown (skipped or not understood).
  final HabitResult? result;

  final String? weekStart;
  final int? habitDaysThisWeek;
  final bool? goodWeekThisWeek;
  final int? goodWeeksTotal;

  bool get ageNotSupported => status == 'age_not_supported';

  static HabitsReply parse(Object? json) {
    if (json is! Map || json['status'] is! String || json['message'] is! String || json['mood'] is! String) {
      throw const HabitsFailure('unexpected response');
    }
    try {
      final habit = json['proposal'] ?? json['habit'];
      return HabitsReply(
        status: json['status'] as String,
        message: json['message'] as String,
        mood: json['mood'] as String,
        emergency: json['emergency'] == true,
        safety: json['safety'] as String?,
        habit: habit == null ? null : Habit.fromJson(habit),
        supports: json['supports'] as String?,
        sourceTitle: json['source_title'] as String?,
        sourceUrl: json['source_url'] as String?,
        habitId: json['habit_id'] as String?,
        question: json['question'] as String?,
        result: json['result'] == null ? null : HabitResult.parse(json['result']),
        weekStart: json['week_start'] as String?,
        habitDaysThisWeek: (json['habit_days_this_week'] as num?)?.toInt(),
        goodWeekThisWeek: json['good_week_this_week'] as bool?,
        goodWeeksTotal: (json['good_weeks_total'] as num?)?.toInt(),
      );
    } on FormatException catch (e) {
      throw HabitsFailure('bad habit in response: ${e.message}');
    } on TypeError {
      throw const HabitsFailure('unexpected response');
    }
  }
}

class HabitsFailure implements Exception {
  const HabitsFailure(this.message, {this.plain, this.statusCode});
  final String message;

  /// A server message that is safe to show (for example a 422's plain reason).
  final String? plain;
  final int? statusCode;

  @override
  String toString() => 'HabitsFailure($message)';
}

class HttpHabitsClient {
  HttpHabitsClient({required this.base, http.Client? client}) : _client = client ?? http.Client();

  final ApiBase base;
  final http.Client _client;

  /// One small idea, asked first. [ownWords] (habit notes, recent check-in
  /// text, newest first, at most 5) are sent only with [memoryConsent].
  Future<HabitsReply> propose({
    required int age,
    required String today,
    required List<Habit> habits,
    Map<String, Object?> profile = const {},
    int? sittingMinutesDaily,
    List<String> ownWords = const [],
    bool memoryConsent = false,
  }) => _post('propose', {
    'age': age,
    'local_date': today,
    'habits': [for (final h in habits) h.toJson()],
    'profile': {
      for (final e in profile.entries)
        if (habitProfileFields.contains(e.key) && e.value != null) e.key: e.value,
    },
    'sitting_minutes_daily': ?sittingMinutesDaily,
    if (memoryConsent) ...{'own_words': ownWords.take(5).toList(), 'memory_consent': true},
  });

  Future<HabitsReply> update({
    required int age,
    required String today,
    required List<Habit> habits,
    required HabitAction action,
    required String habitId,
    String? anchor,
    String? tinyAction,
    String? whyWords,
  }) => _post('update', {
    'age': age,
    'local_date': today,
    'habits': [for (final h in habits) h.toJson()],
    'action': action.name,
    'habit_id': habitId,
    'anchor': ?anchor,
    'tiny_action': ?tinyAction,
    'why_words': ?whyWords,
  });

  /// The one check-in habit question ([HabitQuestionAction.ask]), then the
  /// answer ("Yes / sort of / not today") or a skip, which stays unknown.
  Future<HabitsReply> question({
    required int age,
    required String today,
    required List<Habit> habits,
    required HabitQuestionAction action,
    String? habitId,
    String? text,
  }) => _post('question', {
    'age': age,
    'local_date': today,
    'habits': [for (final h in habits) h.toJson()],
    'action': action.name,
    'habit_id': ?habitId,
    'text': ?text,
  });

  /// The weekly card. The phone can also compute it locally with
  /// `habitWeekProgress`; both use the same rule. At most 400 days are sent.
  Future<HabitsReply> week({
    required int age,
    required String today,
    required Habit habit,
    required Map<String, HabitResult> results,
  }) {
    final days = results.keys.toList()..sort();
    final recent = days.length > 400 ? days.sublist(days.length - 400) : days;
    return _post('week', {
      'age': age,
      'local_date': today,
      'habit': habit.toJson(),
      'results': {for (final d in recent) d: results[d]!.wire},
    });
  }

  Future<HabitsReply> _post(String route, Map<String, Object?> body) async {
    try {
      final url = await base.url();
      final r = await _client
          .post(
            Uri.parse('$url/api/habits/$route'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        throw HabitsFailure('HTTP ${r.statusCode}', plain: _reason(r.bodyBytes), statusCode: r.statusCode);
      }
      return HabitsReply.parse(jsonDecode(utf8.decode(r.bodyBytes)));
    } on HabitsFailure {
      rethrow;
    } catch (e) {
      base.forget();
      throw HabitsFailure('$e');
    }
  }

  static String? _reason(List<int> body) {
    try {
      final json = jsonDecode(utf8.decode(body));
      final message = json is Map ? json['message'] : null;
      return message is String && message.trim().isNotEmpty ? message.trim() : null;
    } catch (_) {
      return null;
    }
  }
}
