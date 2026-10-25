import 'package:lifesim/checkin/change_chat.dart';
import 'package:lifesim/checkin/checkin_client.dart';

/// A scripted `/api/change/*`: Mochi says the current value, asks what changed, reads the new number
/// back, and returns `profile_update` ONLY on the confirm turn. `cancel` saves nothing.
class FakeChangeClient implements ChangeClient {
  final turns = <String>[];
  final starts = <({String? field, bool memory})>[];
  Map<String, dynamic>? lastProfile;

  CheckInResponse _r(
    Map<String, dynamic> state,
    String message, {
    bool complete = false,
    bool emergency = false,
    Map<String, dynamic>? update,
    Map<String, dynamic>? note,
  }) => CheckInResponse({
    'schema_version': '1',
    'message': message,
    'state': state,
    'complete': complete,
    'emergency': emergency,
    'profile_update': update ?? <String, dynamic>{},
    'habit_note': note,
    'guide_mode': 'guided',
    'provider_status': 'not_configured',
    'voice_status': 'unavailable',
    'speech_hint': null,
    'accepted_input_modes': ['text', 'transcript'],
    'mascot_events': [
      {'state': 'listening'},
    ],
    'limitations': <String>[],
  });

  @override
  Future<CheckInResponse> start({
    required Map<String, dynamic> profile,
    String? field,
    required bool memoryConsent,
  }) async {
    starts.add((field: field, memory: memoryConsent));
    lastProfile = profile;
    return field == null
        ? _r({
            'phase': 'choosing',
            'field': null,
            'pending': <String, dynamic>{},
          }, 'Hi, it’s Mochi! What would you like to update?')
        : _r({'phase': 'asking', 'field': field, 'pending': <String, dynamic>{}}, 'What changed about your $field?');
  }

  @override
  Future<CheckInResponse> turn({
    required String action,
    required Map<String, dynamic> state,
    required Map<String, dynamic> profile,
    required bool memoryConsent,
    String? text,
    bool fromTranscript = false,
  }) async {
    turns.add(action);
    lastProfile = profile;
    final field = (state['field'] as String?) ?? 'sleep_hours';
    switch (action) {
      case 'reply':
        final t = (text ?? '').toLowerCase();
        if (t.contains('safe')) {
          return _r(
            state,
            'I’m sorry you’re going through that. If you need help right now, please call 911. We can carry on whenever you’re ready.',
            emergency: true,
          );
        }
        final n = num.tryParse(RegExp(r'[0-9]+(\.[0-9]+)?').firstMatch(t)?.group(0) ?? '');
        if (state['phase'] == 'confirming' && t == 'no') {
          return _r({...state, 'phase': 'asking', 'pending': <String, dynamic>{}}, 'Okay. What is it, then?');
        }
        return _r({
          'phase': 'confirming',
          'field': field,
          'pending': {field: n},
        }, '$field: about $n. Right?');
      case 'confirm':
        final pending = Map<String, dynamic>.from(state['pending'] as Map);
        return _r(
          {'phase': 'ready', 'field': field, 'pending': <String, dynamic>{}},
          'Saved.',
          complete: true,
          update: pending,
          note: memoryConsent ? {'field': field, 'text': 'walks after dinner'} : null,
        );
      case 'cancel':
        return _r({'phase': 'cancelled', 'field': field, 'pending': <String, dynamic>{}}, 'Okay. Nothing changed.');
      case 'resume':
        return _r({'phase': 'asking', 'field': field, 'pending': <String, dynamic>{}}, 'Okay, let’s carry on.');
    }
    return _r(state, '');
  }
}
