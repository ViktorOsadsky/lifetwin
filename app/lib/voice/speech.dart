import 'dart:async';

/// Voice is only input/output around the server-run conversation.
/// Everything the UI knows about voice goes through these interfaces.

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
  /// Speaks [text]. Completes when speech finished or was stopped.
  /// Throws [VoiceUnavailableException] or [VoiceFailure].
  Future<void> speak(String text);

  /// Stops speech right now (cancels the request and playback).
  Future<void> stop();

  /// Whether the last spoken audio is still in memory.
  bool get canReplay;

  /// Plays the last spoken audio again from memory (no network).
  Future<void> replay();

  Future<void> dispose();
}

abstract class SpeechInput {
  /// Starts listening. [onCaption] receives the words heard so far.
  /// Throws [MicDeniedException], [VoiceUnavailableException] or [VoiceFailure].
  Future<void> start(void Function(String text) onCaption);

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
  });

  final Map<String, dynamic> state;
  final String message;
  final bool complete;
  final String mascotState;

  /// The server's AI-helper status for this turn, e.g. `consent_required`.
  final String providerStatus;

  String get phase => (state['phase'] as String?) ?? 'idle';
  bool get isConfirming => phase == 'confirming';
}

/// The server is the authority for the conversation: one call per turn.
abstract class ConversationGuide {
  /// [action] is one of start, reply, confirm, correct, skip, cancel, import.
  /// [values] carries already-confirmed answers for import (e.g. Apple Health).
  /// [aiHelper] is the person's consent for the server's AI helper to read replies.
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
    Map<String, num>? values,
    bool aiHelper = false,
  });
}

/// Server could not be reached or sent something unusable.
class GuideFailure implements Exception {
  const GuideFailure(this.message);
  final String message;
  @override
  String toString() => 'GuideFailure($message)';
}
