import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart' hide IosAudioCategory;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'cartesia_wire.dart';
import 'heard_gate.dart';
import 'speech.dart';
import 'voice_log.dart';
import 'voice_token.dart';

typedef SocketConnector = WebSocketChannel Function(Uri uri);

/// A voice socket that has not opened by then has failed.
const socketReadyLimit = Duration(seconds: 3);

/// How long Stop waits for the reply to its own "finalize" before using the words it has.
const stopFlushLimit = Duration(seconds: 1);

/// Speech that sends no audio for this long is over (or has failed, if none came at all).
const ttsSilenceLimit = Duration(seconds: 4);

/// A listening microphone sends a chunk every few tens of ms. One that sends nothing for this
/// long has stopped by itself: iOS stops the audio engine when headphones are plugged in or
/// out, and the recorder pauses for a phone call or Siri, with no error either way.
const sttMicStallLimit = Duration(seconds: 2);

WebSocketChannel _defaultConnect(Uri uri) => WebSocketChannel.connect(uri);

/// Counts microphone starts. The recorder sets its own audio session when it starts, so
/// playback set up before a listen must be set up again after it.
int _micStarts = 0;

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

/// Whether everything fed has played. Remembers a drain that came before anyone waited,
/// so [wait] never sits out the whole utterance when playback already ended.
class PlaybackDrain {
  bool _drained = true;
  Completer<void>? _waiter;

  /// Nothing fed is still queued or playing.
  bool get drained => _drained;

  void fed() => _drained = false;

  /// The player's feed callback: [frames] still queued.
  void remaining(int frames) {
    if (frames != 0) return;
    _drained = true;
    _release();
  }

  /// Completes once drained, or after [limit] if the drain event never comes.
  Future<void> wait(Duration limit) {
    if (_drained) return Future.value();
    final c = _waiter = Completer<void>();
    return c.future.timeout(limit, onTimeout: () {});
  }

  /// Playback was dropped: nothing is queued any more, and nobody should keep waiting.
  void reset() {
    _drained = true;
    _release();
  }

  void _release() {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }
}

class FlutterPcmSoundPlayer implements PcmPlayer {
  int _rate = 24000;
  int _frames = 0;
  final _drain = PlaybackDrain();

  /// The playback session that is set up now (null when released), and the mic start count
  /// at setup. Consecutive lines with no listen between them reuse it instead of
  /// releasing and setting up the audio session again.
  int? _sessionRate;
  int _sessionMic = -1;

  @override
  Future<void> begin(int sampleRate) async {
    _rate = sampleRate;
    _frames = 0;
    _drain.reset();
    if (_sessionRate == sampleRate && _sessionMic == _micStarts) return;
    voiceLog('tts', 'session_setup', 'playback ${sampleRate}Hz');
    // `playback` uses the loudspeaker. The plugin sets `playAndRecord` without
    // `defaultToSpeaker`, which iOS routes to the quiet phone-call earpiece.
    // The microphone (record package) sets its own playAndRecord + defaultToSpeaker,
    // and the app always stops speaking before it listens, so they never overlap.
    // `playback` also plays when the silent switch is on.
    await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1, iosAudioCategory: IosAudioCategory.playback);
    FlutterPcmSound.setFeedCallback(_drain.remaining);
    _sessionRate = sampleRate;
    _sessionMic = _micStarts;
  }

  @override
  Future<void> feed(Uint8List pcm) async {
    if (pcm.length < 2) return;
    final even = pcm.length.isEven ? pcm : Uint8List.sublistView(pcm, 0, pcm.length - 1);
    _frames += even.length ~/ 2;
    _drain.fed();
    await FlutterPcmSound.feed(PcmArrayInt16(bytes: ByteData.sublistView(even)));
  }

  @override
  Future<void> finish() async {
    if (_frames == 0) return;
    // Fallback in case the drain event never arrives. A drain that already came returns at once.
    await _drain.wait(Duration(milliseconds: _frames * 1000 ~/ _rate + 1500));
  }

  @override
  Future<void> stop() async {
    final idle = _drain.drained;
    _drain.reset();
    // Nothing queued: keep the session for the next line. Queued audio can only be dropped
    // by releasing.
    if (idle && _sessionRate != null) return;
    _sessionRate = null;
    voiceLog('tts', 'session_release');
    FlutterPcmSound.setFeedCallback(null);
    await FlutterPcmSound.release();
  }
}

/// Cartesia Sonic text-to-speech over WebSocket. Wire details are in [CartesiaWire].
class CartesiaSpeechOutput implements SpeechOutput {
  CartesiaSpeechOutput({
    required this.tokens,
    PcmPlayer? player,
    SocketConnector? connect,
    this.readyLimit = socketReadyLimit,
    this.silenceLimit = ttsSilenceLimit,
  }) : _player = player ?? FlutterPcmSoundPlayer(),
       _connect = connect ?? _defaultConnect;

  final VoiceTokenProvider tokens;
  final Duration readyLimit;
  final Duration silenceLimit;
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
  Future<void> speak(String text, {void Function()? onAudio}) async {
    await stop();
    final id = _contextId = _newContextId();
    try {
      await _speakOnce(text, id, forceNewToken: false, onAudio: onAudio);
    } on VoiceUnavailableException {
      rethrow;
    } catch (_) {
      if (_contextId != id) return; // stopped meanwhile
      await _speakOnce(text, id, forceNewToken: true, onAudio: onAudio); // re-mint once, then give up
    }
  }

  Future<void> _speakOnce(String text, String id, {required bool forceNewToken, void Function()? onAudio}) async {
    final clock = Stopwatch()..start();
    final token = await tokens.get(forceNew: forceNewToken);
    voiceLog('tts', 'token', '+${clock.elapsedMilliseconds}ms${forceNewToken ? ' new' : ''}');
    final done = Completer<void>();
    _stopped = done;
    final ch = _channel = _connect(CartesiaWire.ttsUri(token));
    final audio = BytesBuilder(copy: false);
    var gotAudio = false;
    StreamSubscription<dynamic>? sub;
    Timer? silence;
    try {
      _lastRate = token.ttsSampleRate;
      // The socket opens while the player sets up.
      await Future.wait([ch.ready.timeout(readyLimit), _player.begin(token.ttsSampleRate)]);
      voiceLog('tts', 'socket_ready', '+${clock.elapsedMilliseconds}ms');
      if (_contextId != id) return;
      final finished = Completer<void>();
      // A stream that goes quiet must not leave the mascot "speaking" until the caller's limit.
      void armSilence() {
        silence?.cancel();
        silence = Timer(silenceLimit, () {
          if (finished.isCompleted) return;
          voiceLog('tts', 'quiet_end', gotAudio ? 'after audio' : 'no audio');
          gotAudio ? finished.complete() : finished.completeError(const VoiceFailure('tts: no audio'));
        });
      }

      sub = ch.stream.listen(
        (m) async {
          if (m is! String) return;
          switch (CartesiaWire.parseTts(m, contextId: id)) {
            case TtsAudio(:final pcm):
              gotAudio = true;
              armSilence();
              audio.add(pcm);
              if (_contextId == id) {
                final first = onAudio;
                onAudio = null;
                if (first != null) voiceLog('tts', 'audio', '+${clock.elapsedMilliseconds}ms');
                first?.call();
                await _player.feed(pcm);
              }
            case TtsDone():
              voiceLog('tts', 'stream_done', '+${clock.elapsedMilliseconds}ms');
              if (!finished.isCompleted) finished.complete();
            case TtsError(:final message):
              voiceLog('tts', 'error', message);
              if (!finished.isCompleted) finished.completeError(VoiceFailure(message));
            case TtsIgnored():
              break;
          }
        },
        onError: (Object e) {
          if (!finished.isCompleted) finished.completeError(VoiceFailure('$e'));
        },
        onDone: () {
          if (finished.isCompleted) return;
          // Closed before any audio (a refused token, a dropped connection): a failure, so
          // it is tried again with a new token rather than "said" in silence.
          gotAudio ? finished.complete() : finished.completeError(const VoiceFailure('tts: closed before audio'));
        },
      );
      ch.sink.add(CartesiaWire.ttsRequest(token, text, id));
      armSilence();
      await Future.any([finished.future, done.future]);
      if (_contextId == id && gotAudio) {
        final audioMs = audio.length * 500 ~/ token.ttsSampleRate; // PCM16 mono
        _last
          ..clear()
          ..add(audio.takeBytes());
        _hasLast = true;
        await Future.any([_player.finish(), done.future]);
        voiceLog(
          'tts',
          'played',
          '+${clock.elapsedMilliseconds}ms audio=${audioMs}ms${done.isCompleted ? ' stopped' : ''}',
        );
      }
    } catch (e) {
      voiceLog('tts', 'error', '$e');
      if (e is VoiceFailure) rethrow;
      throw VoiceFailure('$e');
    } finally {
      silence?.cancel();
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
  CartesiaSpeechInput({
    required this.tokens,
    AudioRecorder? recorder,
    SocketConnector? connect,
    this.readyLimit = socketReadyLimit,
    this.micStallLimit = sttMicStallLimit,
  }) : _recorder = recorder ?? AudioRecorder(),
       _connect = connect ?? _defaultConnect;

  final VoiceTokenProvider tokens;
  final Duration readyLimit;

  /// See [sttMicStallLimit].
  final Duration micStallLimit;
  final AudioRecorder _recorder;
  final SocketConnector _connect;

  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<dynamic>? _msgSub;
  final _chunks = ChunkBuffer();
  var _pause = PauseDetector();
  var _gate = HeardGate();

  /// The caption last handed to the caller, so an unchanged one never restarts its wait.
  String _shown = '';
  final _early = <Uint8List>[];
  bool _ready = false;
  final _finals = <String>[];
  String _partial = '';
  String? _error;
  Completer<void>? _flushed;
  bool _forceNewToken = false;
  void Function(String)? _onCaption;
  void Function(Object error)? _onDropped;
  bool _finishing = false;

  /// Bumped by every teardown, so a start that was cancelled while waiting stops there.
  int _gen = 0;

  /// Runs out when the microphone has sent nothing for [micStallLimit] (see there). Armed once
  /// the socket is open, and again by every chunk.
  Timer? _stall;

  void _watchMic() {
    _stall?.cancel();
    _stall = Timer(micStallLimit, () {
      _stall = null;
      voiceLog('stt', 'mic_stalled', 'no audio for ${micStallLimit.inMilliseconds}ms');
      _drop('mic stalled', newToken: false);
    });
  }

  void _endFlush() {
    final f = _flushed;
    if (f != null && !f.isCompleted) f.complete();
  }

  String get _caption => CartesiaWire.joinTranscript(_finals, _partial);

  /// Hands the caller the gated caption, only when it changed (see [HeardGate]).
  void _showCaption() {
    final shown = _gate.caption(_caption);
    if (shown == _shown) return;
    _shown = shown;
    _onCaption?.call(shown);
  }

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// The token is shared with [CartesiaSpeechOutput], so this readies both.
  @override
  Future<void> warmUp() => tokens.prefetch();

  @override
  Future<void> start(void Function(String text) onCaption, {void Function(Object error)? onDropped}) async {
    await _teardown();
    final gen = _gen;
    final clock = Stopwatch()..start();
    if (!await _recorder.hasPermission()) throw const MicDeniedException();
    if (gen != _gen) return; // cancelled meanwhile
    _onCaption = onCaption;
    _onDropped = onDropped;
    _finishing = false;
    _finals.clear();
    _partial = '';
    _error = null;
    _ready = false;
    _pause = PauseDetector();
    _gate = HeardGate();
    _shown = '';
    _early.clear();
    _micStarts++;
    // The mic starts before the token and the socket, so the first words are not lost:
    // the screen already says "listening". Audio waits in [_early] until the socket is open.
    final stream = await _recorder.startStream(
      // On iOS, record_ios 2.1 turns `echoCancel` into AVAudioEngine's
      // `inputNode.setVoiceProcessingEnabled(true)`: Apple's voice-processing I/O (echo
      // cancel and noise suppression together; `noiseSuppress` itself is unused there) on a
      // playAndRecord session with defaultToSpeaker. `autoGain` is its AGC. It favors the
      // voice close to the phone. Voice Isolation, the strongest filter for other voices, is
      // the person's choice in the system Mic Mode menu (see mic_modes.dart).
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
    );
    if (gen != _gen) {
      await _recorder.cancel();
      return;
    }
    _micSub = stream.listen(_onMic);
    voiceLog('stt', 'recorder_started', '+${clock.elapsedMilliseconds}ms');
    try {
      final token = await tokens.get(forceNew: _forceNewToken); // may throw VoiceUnavailableException
      if (gen != _gen) return; // cancelled meanwhile; cancel() stopped the mic
      _forceNewToken = false;
      await _open(token, gen);
      voiceLog('stt', 'socket_ready', '+${clock.elapsedMilliseconds}ms');
      if (gen == _gen && _ready) _watchMic();
    } on VoiceUnavailableException {
      if (gen == _gen) await cancel();
      rethrow;
    } catch (e) {
      voiceLog('stt', 'error', 'start $e');
      if (gen == _gen) await cancel();
      if (e is VoiceFailure) rethrow;
      throw VoiceFailure('$e');
    }
  }

  /// The socket closed or failed while listening (not while finishing): stop now and say so.
  /// Before the socket is open, a failure fails [start] instead.
  void _drop(Object e, {bool newToken = true}) {
    final cb = _onDropped;
    voiceLog('stt', 'socket_lost', '$e finishing=$_finishing ready=$_ready');
    if (_finishing || !_ready || cb == null) return;
    _onDropped = null;
    _error ??= '$e';
    if (newToken) _forceNewToken = true;
    // The caller is told only once the mic is closed: hands-free restarts the recognizer from
    // the callback, and a teardown still running would stop that new listen as it starts.
    unawaited(cancel().whenComplete(() => cb(VoiceFailure('stt: $e'))));
  }

  void _onMic(Uint8List data) {
    if (_stall != null) _watchMic();
    for (final raw in _chunks.add(data)) {
      final c = _gate.audio(raw);
      final ch = _channel;
      final paused = _pause.add(c);
      if (_ready && ch != null) {
        ch.sink.add(c);
        if (paused) {
          ch.sink.add(CartesiaWire.sttFinalize); // its reply is not awaited by anyone
        }
      } else {
        _early.add(c);
      }
    }
  }

  /// Opens the socket and sends the audio held so far. A socket that fails or does not open
  /// within [readyLimit] fails the start right away.
  Future<void> _open(VoiceToken token, int gen) async {
    final ch = _channel = _connect(CartesiaWire.sttUri(token));
    _msgSub = ch.stream.listen(
      (m) {
        if (m is! String) return;
        switch (CartesiaWire.parseStt(m)) {
          case SttTranscript(:final text, :final isFinal, :final confidence):
            if (!_gate.keep(confidence)) {
              voiceLog('stt', 'gated', 'low_confidence $confidence ${isFinal ? 'final' : 'partial'}');
              if (isFinal) _partial = '';
            } else if (isFinal) {
              if (text.isNotEmpty) _finals.add(text);
              _partial = '';
            } else {
              _partial = text;
            }
            _showCaption();
          case SttFlushed():
            // Stop waits only for the flush it asked for: the first reply after it. Replies
            // to pause finalizes before Stop find nobody waiting.
            _endFlush();
          case SttError(:final message):
            voiceLog('stt', 'error', message);
            _error = message;
            _endFlush();
          case SttIgnored():
            break;
        }
      },
      onError: (Object e) {
        _error = '$e';
        _endFlush();
        _drop(e);
      },
      onDone: () {
        _endFlush();
        _drop('closed');
      },
    );
    try {
      await ch.ready.timeout(readyLimit);
    } catch (e) {
      _forceNewToken = true;
      throw VoiceFailure('stt connect: $e');
    }
    if (gen != _gen || !identical(_channel, ch)) return; // cancelled meanwhile
    _ready = true;
    for (final c in _early) {
      ch.sink.add(c);
    }
    _early.clear();
  }

  @override
  Future<String> finish() async {
    final ch = _channel;
    if (ch == null) {
      await cancel(); // never connected: just close the mic
      return '';
    }
    _finishing = true;
    _stall?.cancel();
    _stall = null;
    await _recorder.stop();
    await _micSub?.cancel();
    _micSub = null;
    final tail = _chunks.flush();
    if (_ready) {
      if (tail != null) ch.sink.add(tail);
      final flushed = _flushed = Completer<void>();
      ch.sink.add(CartesiaWire.sttFinalize);
      await flushed.future.timeout(stopFlushLimit, onTimeout: () {});
      try {
        ch.sink.add(CartesiaWire.sttClose);
      } catch (_) {}
    }
    final heard = _caption;
    final text = _gate.caption(heard);
    final error = _error;
    voiceLog('stt', 'finished', '${text.length} chars${error != null ? ' error=$error' : ''}');
    if (text.isEmpty && heard.isNotEmpty) {
      voiceLog('stt', 'gated', '${heardForLog(heard)} ${_gate.voiced ? 'no_words' : 'too_little_voice'}');
    }
    await _teardown();
    if (heard.isEmpty && error != null) {
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
    _gen++; // a start still waiting for the token or the mic gives up
    _stall?.cancel();
    _stall = null;
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
    _onDropped = null;
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
