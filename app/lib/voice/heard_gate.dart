import 'dart:math' as math;
import 'dart:typed_data';

import 'cartesia_wire.dart';

/// Decides what the microphone heard counts as the person talking, for one listen.
///
/// Apple's voice processing (echo cancel, noise suppression, gain) runs before this, in the
/// recorder. This gate catches what still gets through:
/// - Sound already going when the microphone opened (Mochi's last word in the room, a TV
///   sentence in progress) is sent as silence: the first [settle], then for up to
///   [onsetLimit] until the first quiet moment.
/// - Words count only once the microphone has heard about [minVoiced] of voice, and only
///   real words do: "[noise]", "(music)" and "um" alone are not an answer.
/// - A transcript piece the recognizer marks below [minConfidence] is dropped. (Ink does not
///   send a confidence today; this is a no-op until it does.)
///
/// Until the gate opens the caption is empty, so the end-of-turn wait never starts on noise.
/// The levels are PCM16 root-mean-square values (of 32768). They are not measured on a phone.
class HeardGate {
  HeardGate({
    this.settle = const Duration(milliseconds: 300),
    this.onsetLimit = const Duration(seconds: 1),
    this.minVoiced = const Duration(milliseconds: 200),
    this.onsetLevel = 600,
    this.quietLevel = 300,
    this.minConfidence = 0.4,
  });

  final Duration settle;
  final Duration onsetLimit;
  final Duration minVoiced;

  /// A chunk at least this loud right after the microphone opens is sound already going.
  final double onsetLevel;

  /// A chunk at least this loud (and three times the room's floor) is voice.
  final double quietLevel;
  final double minConfidence;

  int _ms = 0;
  bool _muting = true;
  bool _quietSeen = false;
  int _voicedMs = 0;
  double? _floor;

  /// Enough voice has been heard for words to count.
  bool get voiced => _voicedMs >= minVoiced.inMilliseconds;

  /// The audio to send for one mic chunk of 16 kHz PCM16 mono: the chunk itself, or the
  /// same length of silence while sound from before the listen is still going.
  Uint8List audio(Uint8List pcm16) {
    final at = _ms;
    final ms = pcm16.length ~/ 32;
    _ms += ms;
    final l = PauseDetector.level(pcm16);
    final f = _floor;
    _floor = f == null || l < f ? l : f + (l - f) * 0.002; // as PauseDetector: drops at once, rises slowly
    if (l < onsetLevel) _quietSeen = true;
    if (_muting) {
      final settling = at < settle.inMilliseconds;
      final ongoing = !_quietSeen && at < onsetLimit.inMilliseconds; // loud since the mic opened
      if (settling || ongoing) return Uint8List(pcm16.length);
      _muting = false;
    }
    if (l >= math.max(quietLevel, _floor! * 3)) _voicedMs += ms;
    return pcm16;
  }

  /// Whether to use a transcript piece with this recognizer confidence (null: not sent).
  bool keep(double? confidence) => confidence == null || confidence >= minConfidence;

  /// What the person is shown and what is sent: [raw] without sound labels, or empty while
  /// it holds no real word or too little voice was heard.
  String caption(String raw) {
    final text = clean(raw);
    return voiced && hasWords(text) ? text : '';
  }

  static final _labels = RegExp(r'\[[^\]]*\]|\([^)]*\)|<[^>]*>|\*[^*]*\*|[♪♫]');

  /// [raw] without sound labels such as "[noise]", "(music)" or "♪".
  static String clean(String raw) {
    if (!_labels.hasMatch(raw)) return raw.trim();
    return raw.replaceAll(_labels, ' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// Hesitation sounds that are never an answer on their own. "Mhm", "uh-huh" and "oh"
  /// are left out on purpose: they can mean yes.
  static const fillers = {'uh', 'um', 'umm', 'uhm', 'er', 'erm', 'hmm', 'hm', 'mm', 'mmm', 'ah', 'eh'};

  /// At least one word that is not only a hesitation sound.
  static bool hasWords(String text) {
    for (final w in text.toLowerCase().split(RegExp(r'\s+'))) {
      final word = w.replaceAll(RegExp(r'[^a-z0-9À-ɏ]'), '');
      if (word.isNotEmpty && !fillers.contains(word)) return true;
    }
    return false;
  }
}
