import 'dart:async';

/// Voice is only input/output around the server-run conversation.
/// Everything the UI knows about voice goes through these interfaces.

/// End of turn while listening, for onboarding and check-ins alike. Before any word is heard,
/// the microphone closes after [voiceQuietClose] of quiet. Once a word has been heard, what
/// was said is sent after [voiceEndOfTurn] with the transcript unchanged and no new partials.
/// A tap still sends at once.
///
/// Hands-free (the app's voice mode, VoiceOver off): quiet never closes the microphone.
/// After [voiceNudgeAfter] of quiet Mochi nudges once, and the recognizer is restarted out of
/// sight every [voiceSessionRestart] so the phone's session limit (about a minute) never shows.
/// One answer is sent at the latest 30 s after its first word (time spent thinking before it
/// does not count).
const voiceQuietClose = Duration(seconds: 8);
const voiceEndOfTurn = Duration(milliseconds: 2500);
const voiceNudgeAfter = Duration(seconds: 20);
const voiceSessionRestart = Duration(seconds: 50);

/// Hands-free: the first prompt's audio has this long to start. Otherwise its words stay on
/// screen and the microphone opens, rather than leaving dead air.
const voiceFirstAudioLimit = Duration(milliseconds: 1500);

/// Hands-free: every later line's audio has this long to start (a token re-mint or a TTS
/// socket that won't open can otherwise leave 4-8 s of dead air). Its words stay on screen
/// and the microphone opens. Not for "Hear it again", which plays from memory.
const voiceLaterAudioLimit = Duration(seconds: 3);

/// Said (once per question) when the server marks a heard reply `off_topic`: the words were
/// most likely someone else (a TV, another person). Nothing was recorded; Mochi listens again.
const offTopicLine = 'Sorry, I think I heard someone else. Could you say that again?';

/// Voice cannot be used right now (server says off, no token, provider down).
/// The app falls back to typing.
class VoiceUnavailableException implements Exception {
  const VoiceUnavailableException([this.reason = 'voice_unavailable']);
  final String reason;
  @override
  String toString() => 'VoiceUnavailableException($reason)';
}

/// The user (or the phone) did not allow the microphone.
class MicDeniedException implements Exception {
  const MicDeniedException();
}

/// A network or socket problem while using voice.
class VoiceFailure implements Exception {
  const VoiceFailure(this.message);
  final String message;
  @override
  String toString() => 'VoiceFailure($message)';
}

abstract class SpeechOutput {
  /// Speaks [text]. Completes when speech finished or was stopped. [onAudio] is called once,
  /// when the first audio is played. Throws [VoiceUnavailableException] or [VoiceFailure].
  Future<void> speak(String text, {void Function()? onAudio});

  /// Stops speech right now (cancels the request and playback).
  Future<void> stop();

  /// Whether the last spoken audio is still in memory.
  bool get canReplay;

  /// Plays the last spoken audio again from memory (no network).
  Future<void> replay();

  Future<void> dispose();
}

abstract class SpeechInput {
  /// Whether the microphone may be used. Shows the system's "Allow microphone?" question
  /// the first time, and waits for the answer however long the person takes to read it.
  Future<bool> hasPermission();

  /// Gets voice ready ahead of time (an access token), so the first Talk and the first
  /// spoken line don't wait for it. Throws [VoiceUnavailableException] or [VoiceFailure].
  Future<void> warmUp();

  /// Starts listening. [onCaption] receives the words heard so far. [onDropped] is called
  /// once if the connection is lost while listening; listening has then already ended.
  /// Throws [MicDeniedException], [VoiceUnavailableException] or [VoiceFailure].
  Future<void> start(void Function(String text) onCaption, {void Function(Object error)? onDropped});

  /// Stops listening and returns the final transcript (may be empty).
  Future<String> finish();

  /// Stops listening and drops everything heard.
  Future<void> cancel();

  Future<void> dispose();
}

/// What the server sent back for one turn. [state] is opaque and caller-held:
/// send it back unchanged with the next request.
class GuideTurn {
  const GuideTurn({
    required this.state,
    required this.message,
    required this.complete,
    this.mascotState = 'asking',
    this.providerStatus = 'not_configured',
    this.modelInputs,
    this.clientAction,
    this.emergency = false,
    this.recommendations = const [],
    this.offTopic = false,
  });

  final Map<String, dynamic> state;
  final String message;
  final bool complete;
  final String mascotState;

  /// The server's AI-helper status for this turn, e.g. `consent_required`.
  final String providerStatus;

  /// The server's `model_inputs`: the on-device model's `profile` from confirmed answers
  /// only, and `status` (`ready`, `still_learning` or `unsupported_age`). Null from a
  /// server that doesn't send it.
  final Map<String, dynamic>? modelInputs;

  /// What the server asks the app to do now: `open_health_import` after a yes to the
  /// Apple Health offer, `open_ideas` after "what should I do?".
  final String? clientAction;

  /// The ideas the server attaches to the turn that finishes the intake (raw items, up to three).
  final List<Map<String, dynamic>> recommendations;

  /// Something urgent was said: pause calmly, show "Call 911" and Continue (which sends `resume`).
  final bool emergency;

  /// The server judged the heard reply to be someone else talking (`off_topic: true`):
  /// nothing was recorded and the same question is still open. See [offTopicLine].
  final bool offTopic;

  String get phase => (state['phase'] as String?) ?? 'idle';
  bool get isConfirming => phase == 'confirming';
}

/// The server is the authority for the conversation: one call per turn.
abstract class ConversationGuide {
  /// [action] is one of start, reply, confirm, correct, skip, cancel, import.
  /// [values] carries already-confirmed answers for import (e.g. Apple Health).
  /// [aiHelper] is the person's consent for the server's AI helper to read replies.
  /// [importSource] names where imported values came from: `apple_health` (default) or `document`.
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
    Map<String, Object>? values,
    bool aiHelper = false,
    String? importSource,
  });
}

/// Server could not be reached or sent something unusable.
class GuideFailure implements Exception {
  const GuideFailure(this.message);
  final String message;
  @override
  String toString() => 'GuideFailure($message)';
}

/// The server answered but refused the request, with a plain-language reason
/// (e.g. "Please check these answers: height."). Retrying unchanged won't help.
/// The server is asking the app to slow down (HTTP 429). Retrying later is safe.
class GuideTooBusy extends GuideFailure {
  const GuideTooBusy(super.message);
}

class GuideRejected extends GuideFailure {
  const GuideRejected(super.message);
}
