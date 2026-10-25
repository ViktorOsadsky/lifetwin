import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

/// Streaming PCM16 little-endian mono playback.
abstract class PcmPlayer {
  Future<void> begin(int sampleRate);
  Future<void> feed(Uint8List pcm);

  /// Completes when all queued audio has actually ended (or is cancelled).
  Future<void> finish();

  /// Drops queued sound and releases any pending finish immediately.
  Future<void> stop();
}

/// The browser's audio clock and one-shot sources, isolated for deterministic tests.
abstract interface class PcmAudioDevice {
  double get currentTime;
  Future<void> resume();
  PcmAudioSource schedule(Float32List samples, int sampleRate, double when);
}

abstract interface class PcmAudioSource {
  Future<void> get ended;
  void stop();
}

/// Queues PCM against the audio device's clock, not a wall-clock playback timer.
/// Native playback continues to use its existing plugin; this is the web engine.
class ScheduledPcmPlayer implements PcmPlayer {
  ScheduledPcmPlayer(this.device);

  final PcmAudioDevice device;
  final _sources = <PcmAudioSource>{};
  Completer<void>? _drained;
  int _generation = 0;
  int _rate = 24000;
  int? _carry;
  bool _ready = false;
  double _next = 0;

  @override
  Future<void> begin(int sampleRate) async {
    if (sampleRate < 8000 || sampleRate > 96000) {
      throw ArgumentError.value(sampleRate, 'sampleRate');
    }
    await stop();
    final generation = _generation;
    await device.resume();
    if (generation != _generation) return;
    _rate = sampleRate;
    _next = device.currentTime;
    _ready = true;
  }

  @override
  Future<void> feed(Uint8List pcm) async {
    if (!_ready || pcm.isEmpty) return;
    final bytes = _carry == null
        ? pcm
        : (Uint8List(pcm.length + 1)
            ..[0] = _carry!
            ..setRange(1, pcm.length + 1, pcm));
    final count = bytes.length ~/ 2;
    _carry = bytes.length.isOdd ? bytes.last : null;
    if (count == 0) return;
    final data = ByteData.sublistView(bytes);
    final samples = Float32List(count);
    for (var i = 0; i < count; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768;
    }
    final now = device.currentTime;
    final when = math.max(_next, now + 0.02);
    // Bound accidental/untrusted streams instead of retaining an unlimited queue.
    if (when + count / _rate - now > 60) {
      await stop();
      throw StateError('Browser speech exceeded the audio queue limit.');
    }
    final generation = _generation;
    final source = device.schedule(samples, _rate, when);
    _next = when + count / _rate;
    if (_sources.isEmpty) _drained = Completer<void>();
    _sources.add(source);
    source.ended.then((_) {
      if (generation != _generation) return;
      _sources.remove(source);
      if (_sources.isEmpty) _release();
    });
  }

  @override
  Future<void> finish() async {
    if (_carry != null) {
      await stop();
      throw StateError('Incomplete PCM16 audio sample.');
    }
    final drained = _drained;
    if (drained == null || drained.isCompleted) return;
    // A suspended/interrupted browser must not leave the conversation hanging.
    await drained.future.timeout(
      const Duration(seconds: 65),
      onTimeout: () {
        stop();
        throw StateError(
          'Browser audio did not finish. Tap Talk to try again.',
        );
      },
    );
  }

  void _release() {
    final drained = _drained;
    if (drained != null && !drained.isCompleted) drained.complete();
  }

  @override
  Future<void> stop() async {
    _generation++;
    _ready = false;
    _carry = null;
    final sources = _sources.toList();
    _sources.clear();
    _release();
    for (final source in sources) {
      source.stop();
    }
  }
}
