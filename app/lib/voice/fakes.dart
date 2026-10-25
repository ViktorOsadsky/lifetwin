import 'dart:async';

import 'speech.dart';

/// Development and test stand-ins. They never touch the network or the microphone.

class FakeSpeechOutput implements SpeechOutput {
  /// Everything that was spoken, in order.
  final spoken = <String>[];
  int stops = 0;
  int replays = 0;

  /// When true, [speak] waits until [finishSpeaking] or [stop].
  bool holdSpeech = false;
  Object? speakError;

  Completer<void>? _gate;

  @override
  bool get canReplay => spoken.isNotEmpty;

  @override
  Future<void> speak(String text) async {
    if (speakError != null) throw speakError!;
    spoken.add(text);
    if (holdSpeech) {
      final g = _gate = Completer<void>();
      await g.future;
    }
  }

  void finishSpeaking() {
    if (!(_gate?.isCompleted ?? true)) _gate!.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    finishSpeaking();
  }

  @override
  Future<void> replay() async {
    replays++;
  }

  @override
  Future<void> dispose() async {}
}

class FakeSpeechInput implements SpeechInput {
  /// What [finish] returns.
  String transcript = 'I am 70';

  /// Words shown while listening.
  List<String> captions = const [];

  /// Thrown by [start] if set (e.g. [MicDeniedException]).
  Object? startError;
  Object? finishError;

  /// Thrown by [warmUp] if set.
  Object? warmUpError;
  int warmUps = 0;

  int starts = 0;
  int finishes = 0;
  int cancels = 0;
  int disposals = 0;

  /// Set to hold the "Allow microphone?" answer until it is completed.
  Completer<bool>? permission;

  @override
  Future<bool> hasPermission() async => permission == null ? true : permission!.future;

  @override
  Future<void> warmUp() async {
    warmUps++;
    if (warmUpError != null) throw warmUpError!;
  }

  @override
  Future<void> start(void Function(String text) onCaption) async {
    starts++;
    if (startError != null) throw startError!;
    if (!await hasPermission()) throw const MicDeniedException(); // as the real recorder does
    for (final c in captions) {
      onCaption(c);
    }
  }

  @override
  Future<String> finish() async {
    finishes++;
    if (finishError != null) throw finishError!;
    return transcript;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

/// A small scripted conversation: asks age, then height, then asks to confirm.
class FakeConversationGuide implements ConversationGuide {
  /// Every request made, as {action, text, fromTranscript, state}.
  final calls = <Map<String, dynamic>>[];

  /// Fails the next call with a [GuideFailure].
  bool failNext = false;

  /// Rejects the next call with this server reason ([GuideRejected]).
  String? rejectNext;

  /// Waits on this before answering, to test overlapping taps.
  Completer<void>? gate;

  @override
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
    Map<String, Object>? values,
    bool aiHelper = false,
    String? importSource,
  }) async {
    calls.add({
      'action': action,
      'text': text,
      'fromTranscript': fromTranscript,
      'state': state,
      'values': values,
      'aiHelper': aiHelper,
      'importSource': importSource,
    });
    if (gate != null) await gate!.future;
    if (failNext) {
      failNext = false;
      throw const GuideFailure('offline');
    }
    if (rejectNext case final reason?) {
      rejectNext = null;
      throw GuideRejected(reason);
    }
    final confirmed = Map<String, dynamic>.from((state?['confirmed_profile'] as Map?) ?? const {});
    final pending = Map<String, dynamic>.from((state?['pending_profile'] as Map?) ?? const {});
    switch (action) {
      case 'import':
        return _turn('asking', 'Thanks! I added your Health answers. Do you smoke?', {
          ...confirmed,
          ...?values,
        }, pending);
      case 'start':
        return _turn('asking', 'How old are you?', confirmed, pending);
      case 'reply' when text == 'about five foot eight':
        return aiHelper
            ? _turn('confirming', 'I heard you are 5 feet 8 inches (about 173 cm) tall. Is that right?', confirmed, {
                'height_cm': 172.72,
              }, provider: 'used')
            : _turn(
                'asking',
                "I couldn't read that. You can let the AI helper try.",
                confirmed,
                pending,
                provider: 'consent_required',
              );
      // A spoken or typed answer to the read-back: "yes" saves it, anything else asks again.
      case 'reply' when state?['phase'] == 'confirming':
        if (RegExp(r'^(yes|yeah|yep|that.s right)\b', caseSensitive: false).hasMatch(text ?? '')) {
          return _done({...confirmed, ...pending});
        }
        return _turn(
          'confirming',
          'Okay, nothing has changed. What is the right answer for your age?',
          confirmed,
          pending,
        );
      // Something urgent: pause calmly. "resume" (Continue) asks the same question again.
      case 'reply' when (text ?? '').contains('chest pain'):
        return _turn(
          'asking',
          'I’m sorry you’re going through that. If you need help right now, please call 911. We can carry on whenever you’re ready.',
          confirmed,
          pending,
          emergency: true,
        );
      case 'resume':
        return _turn('asking', 'How old are you?', confirmed, pending);
      case 'reply' when text == 'go back':
        return _turn('asking', "Okay, let's go back to your age. How old are you?", confirmed, pending);
      case 'reply':
        if (state?['phase'] == 'asking' && state?['current_field'] == 'age') {
          return _turn('confirming', 'I heard you are 70. Is that right?', confirmed, {
            'age': 70,
          }, mascot: 'confirming');
        }
        return _turn('asking', 'How old are you?', confirmed, pending);
      case 'confirm':
        return _done({...confirmed, ...pending});
      case 'correct':
        return _turn('asking', 'Okay. How old are you?', confirmed, {});
      default:
        return _turn('asking', 'How old are you?', confirmed, pending);
    }
  }

  GuideTurn _done(Map<String, dynamic> confirmed) => _turn(
    'ready',
    'All done. Thank you. Tap Continue to see your forecast.',
    confirmed,
    {},
    complete: true,
    mascot: 'celebrating',
  );

  GuideTurn _turn(
    String phase,
    String message,
    Map<String, dynamic> confirmed,
    Map<String, dynamic> pending, {
    bool complete = false,
    String mascot = 'asking',
    String provider = 'not_configured',
    bool emergency = false,
  }) {
    return GuideTurn(
      emergency: emergency,
      providerStatus: provider,
      state: {
        'phase': phase,
        'current_field': phase == 'asking' ? 'age' : null,
        'confirmed_profile': confirmed,
        'pending_profile': pending,
      },
      message: message,
      complete: complete,
      mascotState: mascot,
    );
  }
}
