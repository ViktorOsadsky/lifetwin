import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'pcm_player.dart';

// One context and one set of gesture listeners per page, shared by route owners.
// No sound, microphone access or network traffic is created by unlocking it.
final _device = _BrowserAudioDevice();

PcmPlayer? createBrowserPcmPlayer() => ScheduledPcmPlayer(_device);

class _BrowserAudioDevice implements PcmAudioDevice {
  _BrowserAudioDevice() {
    final unlock = ((web.Event _) {
      try {
        final context = _context ??= web.AudioContext();
        context.resume().toDart.then((_) {}, onError: (Object _) {});
      } catch (_) {
        // Unsupported/blocked audio is reported by resume when speech is used.
      }
    }).toJS;
    // Capture before Flutter's click handler starts asynchronous token requests.
    web.document.addEventListener('pointerdown', unlock, true.toJS);
    web.document.addEventListener('click', unlock, true.toJS);
    web.document.addEventListener('keydown', unlock, true.toJS);
  }

  web.AudioContext? _context;

  @override
  double get currentTime => _context?.currentTime ?? 0;

  @override
  Future<void> resume() async {
    final context = _context ??= web.AudioContext();
    await context.resume().toDart.timeout(const Duration(seconds: 2));
    if (context.state != 'running') {
      throw StateError('Browser audio is paused. Tap Talk to enable sound.');
    }
  }

  @override
  PcmAudioSource schedule(Float32List samples, int sampleRate, double when) {
    final context = _context!;
    // The buffer's source rate is retained; Web Audio resamples to the device rate.
    final buffer = context.createBuffer(1, samples.length, sampleRate);
    buffer.copyToChannel(samples.toJS, 0);
    final node = context.createBufferSource()..buffer = buffer;
    node.connect(context.destination);
    final source = _BrowserAudioSource(node);
    node.start(when);
    return source;
  }
}

class _BrowserAudioSource implements PcmAudioSource {
  _BrowserAudioSource(this.node) {
    node.onended = ((web.Event _) => _complete()).toJS;
  }

  final web.AudioBufferSourceNode node;
  final _ended = Completer<void>();

  @override
  Future<void> get ended => _ended.future;

  void _complete() {
    if (_ended.isCompleted) return;
    node.onended = null;
    node.disconnect();
    _ended.complete();
  }

  @override
  void stop() {
    if (_ended.isCompleted) return;
    try {
      node.stop();
    } catch (_) {
      // A node that ended just before cancellation has nothing left to stop.
    } finally {
      _complete();
    }
  }
}
