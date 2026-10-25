import 'package:lifesim/checkin/checkin_client.dart';

/// A scripted check-in server that follows `contracts/checkin.schema.json`: one question at a time,
/// a per-answer "Is that right?" confirming phase (which the app must answer silently), `skip`,
/// the emergency pause and `resume`, and a final `complete` reply with every confirmed answer.
class FakeCheckinClient implements CheckInClient {
  FakeCheckinClient({this.profileUpdate = const {}});

  static const dailyQuestions = ['sleep_hours_last_night', 'exercise_minutes_today', 'wellbeing'];
  static const weeklyQuestions = ['sleep_hours', 'exercise_minutes_weekly', 'wellbeing'];

  /// Applied by a finished weekly check-in.
  final Map<String, dynamic> profileUpdate;

  final turns = <({String action, String? text})>[];
  int starts = 0;

  CheckInResponse _reply(Map<String, dynamic> state, String message, {bool complete = false, bool emergency = false}) =>
      CheckInResponse({
        'schema_version': '1',
        'message': message,
        'state': state,
        'complete': complete,
        'emergency': emergency,
        'profile_update': complete && state['kind'] == 'weekly' ? profileUpdate : <String, dynamic>{},
        'guide_mode': 'guided',
        'provider_status': 'not_configured',
        'voice_status': 'unavailable',
        'speech_hint': null,
        'accepted_input_modes': ['text', 'transcript'],
        'mascot_events': [
          {'state': emergency ? 'concerned' : 'listening'},
        ],
        'limitations': <String>[],
      });

  Map<String, dynamic> _state(
    CheckInKind kind,
    List<String> qs, {
    String phase = 'asking',
    int at = 0,
    Map<String, dynamic>? confirmed,
    Map<String, dynamic>? pending,
    List<String> skipped = const [],
  }) => {
    'kind': kind.name,
    'phase': phase,
    'questions': qs,
    'current_field': at < qs.length ? qs[at] : null,
    'previous': <String, dynamic>{},
    'confirmed': confirmed ?? <String, dynamic>{},
    'pending': pending ?? <String, dynamic>{},
    'skipped_fields': skipped,
  };

  @override
  Future<CheckInResponse> start(CheckInKind kind, {String? localDate, Map<String, dynamic> previous = const {}}) async {
    starts++;
    final qs = kind == CheckInKind.daily ? dailyQuestions : weeklyQuestions;
    return _reply(_state(kind, qs), 'Hi, it’s Mochi! ${_ask(qs.first)}');
  }

  static String _ask(String f) => switch (f) {
    'sleep_hours_last_night' || 'sleep_hours' => 'How many hours did you sleep?',
    'exercise_minutes_today' || 'exercise_minutes_weekly' => 'How many minutes did you move?',
    _ => 'How are you feeling: good, okay, or not great?',
  };

  static num? _number(String text) => num.tryParse(RegExp(r'[0-9]+(\.[0-9]+)?').firstMatch(text)?.group(0) ?? '');

  @override
  Future<CheckInResponse> turn({
    required String action,
    required Map<String, dynamic> state,
    String? text,
    bool fromTranscript = false,
  }) async {
    turns.add((action: action, text: text));
    final kind = state['kind'] == 'weekly' ? CheckInKind.weekly : CheckInKind.daily;
    final qs = [for (final q in state['questions'] as List) '$q'];
    final field = state['current_field'] as String?;
    final at = field == null ? qs.length : qs.indexOf(field);
    final confirmed = Map<String, dynamic>.from(state['confirmed'] as Map);
    final pending = Map<String, dynamic>.from(state['pending'] as Map);
    final skipped = [for (final q in state['skipped_fields'] as List) '$q'];

    CheckInResponse next(int i, {Map<String, dynamic>? c, List<String>? s}) {
      final cc = c ?? confirmed;
      final ss = s ?? skipped;
      if (i >= qs.length) {
        return _reply(_state(kind, qs, phase: 'ready', at: i, confirmed: cc, skipped: ss), 'All done.', complete: true);
      }
      return _reply(_state(kind, qs, at: i, confirmed: cc, skipped: ss), _ask(qs[i]));
    }

    switch (action) {
      case 'reply':
        final t = (text ?? '').toLowerCase();
        if (t.contains('chest pain') || t.contains('safe')) {
          return _reply(
            state,
            'I’m sorry you’re going through that. If you need help right now, please call 911. We can carry on whenever you’re ready.',
            emergency: true,
          );
        }
        if (state['phase'] == 'confirming') {
          return t.startsWith('y')
              ? next(at + 1, c: {...confirmed, ...pending})
              : _reply(_state(kind, qs, at: at, confirmed: confirmed), _ask(field!));
        }
        final Object? value = field == 'wellbeing'
            ? (t.contains('not')
                  ? 'not_great'
                  : t.contains('okay')
                  ? 'okay'
                  : 'good')
            : _number(t);
        return _reply(
          _state(
            kind,
            qs,
            phase: 'confirming',
            at: at,
            confirmed: confirmed,
            pending: {field!: value},
            skipped: skipped,
          ),
          'I heard $value. Is that right?',
        );
      case 'confirm':
        return next(at + 1, c: {...confirmed, ...pending});
      case 'skip':
        return next(at + 1, s: [...skipped, ?field]);
      case 'resume':
        return _reply(
          _state(kind, qs, at: at, confirmed: confirmed, skipped: skipped),
          'Okay, let’s carry on. ${_ask(field!)}',
        );
      default:
        return _reply(state, 'Okay. Nothing changed.');
    }
  }
}
