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

  int starts = 0;
  int finishes = 0;
  int cancels = 0;

  @override
  Future<void> start(void Function(String text) onCaption) async {
    starts++;
    if (startError != null) throw startError!;
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
  Future<void> dispose() async {}
}

/// A small scripted conversation: asks age, then height, then asks to confirm.
class FakeConversationGuide implements ConversationGuide {
  /// Every request made, as {action, text, fromTranscript, state}.
  final calls = <Map<String, dynamic>>[];

  /// Fails the next call with a [GuideFailure].
  bool failNext = false;

  /// Waits on this before answering, to test overlapping taps.
  Completer<void>? gate;

  @override
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
  }) async {
    calls.add({'action': action, 'text': text, 'fromTranscript': fromTranscript, 'state': state});
    if (gate != null) await gate!.future;
    if (failNext) {
      failNext = false;
      throw const GuideFailure('offline');
    }
    final confirmed = Map<String, dynamic>.from((state?['confirmed_profile'] as Map?) ?? const {});
    final pending = Map<String, dynamic>.from((state?['pending_profile'] as Map?) ?? const {});
    switch (action) {
      case 'start':
        return _turn('asking', 'How old are you?', confirmed, pending);
      case 'reply':
        if (state?['phase'] == 'asking' && state?['current_field'] == 'age') {
          return _turn('confirming', 'I heard 70 years old. Is that right?', confirmed, {'age': 70},
              mascot: 'confirming');
        }
        return _turn('asking', 'How old are you?', confirmed, pending);
      case 'confirm':
        return _turn('ready', 'Thank you. That is all I need.', {...confirmed, ...pending}, {},
            complete: true, mascot: 'celebrating');
      case 'correct':
        return _turn('asking', 'Okay. How old are you?', confirmed, {});
      default:
        return _turn('asking', 'How old are you?', confirmed, pending);
    }
  }

  GuideTurn _turn(String phase, String message, Map<String, dynamic> confirmed, Map<String, dynamic> pending,
      {bool complete = false, String mascot = 'asking'}) {
    return GuideTurn(
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
