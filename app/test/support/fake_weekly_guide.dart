import 'package:lifesim/checkin/checkin_client.dart';
import 'package:lifesim/checkin/checkin_models.dart';

/// A scripted weekly check-in server (`kind: weekly`): one question (sitting on a usual day), read back, then a
/// finished reply with a `profile_update`.
class FakeWeeklyGuide implements CheckinGuide {
  FakeWeeklyGuide({this.sittingMinutes = 180});

  /// What the finished check-in sets `sedentary_min_day` to.
  final int sittingMinutes;
  final calls = <String>[];

  static const questions = ['sedentary_min_day'];

  Map<String, dynamic> _raw(
    String phase,
    String message, {
    Map<String, dynamic> pending = const {},
    bool complete = false,
    Map<String, dynamic> extra = const {},
  }) => {
    'message': message,
    'complete': complete,
    'emergency': false,
    'mascot_events': [
      {'state': complete ? 'celebrating' : 'asking', 'caption': message},
    ],
    'daily_logs': [],
    'profile_update': complete ? {'sedentary_min_day': sittingMinutes} : {},
    'state': {
      'kind': 'weekly',
      'phase': phase,
      'questions': questions,
      'current_field': complete ? null : 'sedentary_min_day',
      'confirmed': complete ? {'sedentary_min_day': sittingMinutes} : {},
      'pending': pending,
      'skipped_fields': <String>[],
      'from_health': false,
      'local_date': '2026-11-01',
      ...extra,
    },
  };

  @override
  Future<CheckinTurn> start({
    required String kind,
    required String localDate,
    Map<String, dynamic> previous = const {},
    QuickPlan? quick,
  }) async {
    calls.add('start:$kind');
    return CheckinTurn(_raw('asking', 'About how many hours do you sit on a usual day?'));
  }

  @override
  Future<CheckinTurn> turn({
    required String action,
    required Map<String, dynamic> state,
    String? text,
    bool fromTranscript = false,
  }) async {
    calls.add(action);
    // The engine's care reply (weekly too): empathy, the soft 911 line, then keep going or stop.
    if (action == 'reply' && text == 'awful' && state['care_line_shown'] != true) {
      return CheckinTurn(
        _raw(
          'asking',
          'I’m sorry it was a hard week. If you’re ever thinking about hurting yourself, please call 911. Keep going, or stop here for today?',
          extra: {'care_line_shown': true, 'care_question_open': true},
        ),
      );
    }
    if (state['care_question_open'] == true && action == 'reply') {
      return CheckinTurn(
        _raw('confirming', 'Before I save anything... Is that right?', pending: {'sedentary_min_day': sittingMinutes}),
      );
    }
    if (action == 'confirm') return CheckinTurn(_raw('ready', 'Thank you!', complete: true));
    return CheckinTurn(
      _raw('confirming', 'I heard $text. Is that right?', pending: {'sedentary_min_day': sittingMinutes}),
    );
  }
}
