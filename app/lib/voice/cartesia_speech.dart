import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart' hide IosAudioCategory;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'cartesia_wire.dart';
import 'speech.dart';
import 'voice_token.dart';

typedef SocketConnector = WebSocketChannel Function(Uri uri);

WebSocketChannel _defaultConnect(Uri uri) => WebSocketChannel.connect(uri);

String _newContextId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Streaming PCM16 mono playback.
abstract class PcmPlayer {
  Future<void> begin(int sampleRate);
  Future<void> feed(Uint8List pcm);

  /// Completes when everything fed has been played.
  Future<void> finish();

  /// Drops queued audio now.
  Future<void> stop();
}

class FlutterPcmSoundPlayer implements PcmPlayer {
  int _rate = 24000;
  int _frames = 0;
  Completer<void>? _drained;

  @override
  Future<void> begin(int sampleRate) async {
    _rate = sampleRate;
    _frames = 0;
    _drained = null;
    // `playback` uses the loudspeaker. The plugin sets `playAndRecord` without
    // `defaultToSpeaker`, which iOS routes to the quiet phone-call earpiece.
    // The microphone (record package) sets its own playAndRecord + defaultToSpeaker,
    // and the app always stops speaking before it listens, so they never overlap.
    // `playback` also plays when the silent switch is on.
    await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1, iosAudioCategory: IosAudioCategory.playback);
    FlutterPcmSound.setFeedCallback((remaining) {
      if (remaining == 0 && !(_drained?.isCompleted ?? true)) _drained!.complete();
    });
  }

  @override
  Future<void> feed(Uint8List pcm) async {
    if (pcm.length < 2) return;
    final even = pcm.length.isEven ? pcm : Uint8List.sublistView(pcm, 0, pcm.length - 1);
    _frames += even.length ~/ 2;
    await FlutterPcmSound.feed(PcmArrayInt16(bytes: ByteData.sublistView(even)));
  }

  @override
  Future<void> finish() async {
    if (_frames == 0) return;
    final c = _drained = Completer<void>();
    // Fallback in case the drain event never arrives.
    final limit = Duration(milliseconds: _frames * 1000 ~/ _rate + 1500);
    await c.future.timeout(limit, onTimeout: () {});
  }

  @override
  Future<void> stop() async {
    final c = _drained;
    if (c != null && !c.isCompleted) c.complete();
    FlutterPcmSound.setFeedCallback(null);
    await FlutterPcmSound.release();
  }
}

/// Cartesia Sonic text-to-speech over WebSocket. Wire details are in [CartesiaWire].
class CartesiaSpeechOutput implements SpeechOutput {
  CartesiaSpeechOutput({required this.tokens, PcmPlayer? player, SocketConnector? connect})
    : _player = player ?? FlutterPcmSoundPlayer(),
      _connect = connect ?? _defaultConnect;

  final VoiceTokenProvider tokens;
  final PcmPlayer _player;
  final SocketConnector _connect;

  /// Last spoken audio, kept in memory only, for "Hear it again".
  final _last = BytesBuilder(copy: false);
  int _lastRate = 24000;
  bool _hasLast = false;

  String? _contextId;
  WebSocketChannel? _channel;
  Completer<void>? _stopped;

  @override
  bool get canReplay => _hasLast;

  @override
  Future<void> speak(String text) async {
    await stop();
    final id = _contextId = _newContextId();
    try {
      await _speakOnce(text, id, forceNewToken: false);
    } on VoiceUnavailableException {
      rethrow;
    } catch (_) {
      if (_contextId != id) return; // stopped meanwhile
      await _speakOnce(text, id, forceNewToken: true); // re-mint once, then give up
    }
  }

  Future<void> _speakOnce(String text, String id, {required bool forceNewToken}) async {
    final token = await tokens.get(forceNew: forceNewToken);
    final done = Completer<void>();
    _stopped = done;
    final ch = _channel = _connect(CartesiaWire.ttsUri(token));
    final audio = BytesBuilder(copy: false);
    var gotAudio = false;
    StreamSubscription<dynamic>? sub;
    try {
      await ch.ready;
      if (_contextId != id) return;
      _lastRate = token.ttsSampleRate;
      await _player.begin(token.ttsSampleRate);
      final finished = Completer<void>();
      sub = ch.stream.listen(
        (m) async {
          if (m is! String) return;
          switch (CartesiaWire.parseTts(m, contextId: id)) {
            case TtsAudio(:final pcm):
              gotAudio = true;
              audio.add(pcm);
              if (_contextId == id) await _player.feed(pcm);
            case TtsDone():
              if (!finished.isCompleted) finished.complete();
            case TtsError(:final message):
              if (!finished.isCompleted) finished.completeError(VoiceFailure(message));
            case TtsIgnored():
              break;
          }
        },
        onError: (Object e) {
          if (!finished.isCompleted) finished.completeError(VoiceFailure('$e'));
        },
        onDone: () {
          if (!finished.isCompleted) finished.complete();
        },
      );
      ch.sink.add(CartesiaWire.ttsRequest(token, text, id));
      await Future.any([finished.future, done.future]);
      if (_contextId == id && gotAudio) {
        _last
          ..clear()
          ..add(audio.takeBytes());
        _hasLast = true;
        await Future.any([_player.finish(), done.future]);
      }
    } catch (e) {
      if (e is VoiceFailure) rethrow;
      throw VoiceFailure('$e');
    } finally {
      await sub?.cancel();
      if (identical(_channel, ch)) _channel = null;
      try {
        await ch.sink.close();
      } catch (_) {}
    }
  }

  @override
  Future<void> stop() async {
    final id = _contextId;
    _contextId = null;
    final ch = _channel;
    if (id != null && ch != null) {
      try {
        ch.sink.add(CartesiaWire.ttsCancel(id));
      } catch (_) {}
    }
    final s = _stopped;
    if (s != null && !s.isCompleted) s.complete();
    await _player.stop();
  }

  @override
  Future<void> replay() async {
    if (!_hasLast) return;
    await stop();
    final id = _contextId = _newContextId();
    final done = _stopped = Completer<void>();
    final bytes = Uint8List.fromList(_last.toBytes());
    await _player.begin(_lastRate);
    const step = 9600; // 200 ms at 24 kHz
    for (var i = 0; i < bytes.length && _contextId == id; i += step) {
      await _player.feed(Uint8List.sublistView(bytes, i, min(i + step, bytes.length)));
    }
    if (_contextId == id) await Future.any([_player.finish(), done.future]);
  }

  @override
  Future<void> dispose() async {
    await stop();
    _last.clear();
    _hasLast = false;
  }
}

/// Cartesia streaming speech-to-text. Tap-to-talk: start, then finish.
class CartesiaSpeechInput implements SpeechInput {
  CartesiaSpeechInput({required this.tokens, AudioRecorder? recorder, SocketConnector? connect})
    : _recorder = recorder ?? AudioRecorder(),
      _connect = connect ?? _defaultConnect;

  final VoiceTokenProvider tokens;
  final AudioRecorder _recorder;
  final SocketConnector _connect;

  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<dynamic>? _msgSub;
  final _chunks = ChunkBuffer();
  var _pause = PauseDetector();
  int _flushesOwed = 0;
  final _early = <Uint8List>[];
  bool _ready = false;
  final _finals = <String>[];
  String _partial = '';
  String? _error;
  Completer<void>? _flushed;
  bool _forceNewToken = false;
  void Function(String)? _onCaption;

  void _endFlush() {
    final f = _flushed;
    if (f != null && !f.isCompleted) f.complete();
  }

  String get _caption => CartesiaWire.joinTranscript(_finals, _partial);

  @override
  Future<void> start(void Function(String text) onCaption) async {
    await _teardown();
    if (!await _recorder.hasPermission()) throw const MicDeniedException();
    final token = await tokens.get(forceNew: _forceNewToken); // may throw VoiceUnavailableException
    _forceNewToken = false;
    _onCaption = onCaption;
    _finals.clear();
    _partial = '';
    _error = null;
    _ready = false;
    _pause = PauseDetector();
    _flushesOwed = 0;
    _early.clear();
    final ch = _channel = _connect(CartesiaWire.sttUri(token));
    _msgSub = ch.stream.listen(
      (m) {
        if (m is! String) return;
        switch (CartesiaWire.parseStt(m)) {
          case SttTranscript(:final text, :final isFinal):
            if (isFinal) {
              if (text.isNotEmpty) _finals.add(text);
              _partial = '';
            } else {
              _partial = text;
            }
            _onCaption?.call(_caption);
          case SttFlushed():
            // Pauses also ask for a flush; Stop waits for the last one owed.
            if (_flushesOwed > 0) _flushesOwed--;
            if (_flushesOwed == 0) _endFlush();
          case SttError(:final message):
            _error = message;
            _endFlush();
          case SttIgnored():
            break;
        }
      },
      onError: (Object e) {
        _error = '$e';
        _endFlush();
      },
      onDone: () {
        _endFlush();
      },
    );
    // Start the mic first so the first words are not lost while the socket connects.
    final stream = await _recorder.startStream(
      // Apple's voice processing (echo cancel + noise suppression) favors the voice
      // close to the phone over other people talking in the room; gain helps soft voices.
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
    );
    _micSub = stream.listen((data) {
      for (final c in _chunks.add(data)) {
        _ready ? ch.sink.add(c) : _early.add(c);
        if (_pause.add(c) && _ready) {
          _flushesOwed++;
          ch.sink.add(CartesiaWire.sttFinalize);
        }
      }
    });
    unawaited(
      ch.ready.then(
        (_) {
          _ready = true;
          for (final c in _early) {
            ch.sink.add(c);
          }
          _early.clear();
        },
        onError: (Object e) {
          _error = '$e';
          _forceNewToken = true;
        },
      ),
    );
  }

  @override
  Future<String> finish() async {
    final ch = _channel;
    if (ch == null) return '';
    await _recorder.stop();
    await _micSub?.cancel();
    _micSub = null;
    final tail = _chunks.flush();
    if (_ready) {
      if (tail != null) ch.sink.add(tail);
      _flushed = Completer<void>();
      _flushesOwed++;
      ch.sink.add(CartesiaWire.sttFinalize);
      await _flushed!.future.timeout(const Duration(seconds: 3), onTimeout: () {});
      try {
        ch.sink.add(CartesiaWire.sttClose);
      } catch (_) {}
    }
    final text = _caption;
    final error = _error;
    await _teardown();
    if (text.isEmpty && error != null) {
      _forceNewToken = true;
      throw VoiceFailure(error);
    }
    return text;
  }

  @override
  Future<void> cancel() async {
    if (await _recorder.isRecording()) await _recorder.cancel();
    await _teardown();
  }

  Future<void> _teardown() async {
    await _micSub?.cancel();
    _micSub = null;
    await _msgSub?.cancel();
    _msgSub = null;
    final ch = _channel;
    _channel = null;
    _ready = false;
    _early.clear();
    _chunks.flush();
    _onCaption = null;
    try {
      await ch?.sink.close();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}
