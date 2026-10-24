// Silent voice-test support: the microphone is a WAV file, the speaker is muted.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lifesim/voice/cartesia_speech.dart';
import 'package:lifesim/voice/speech.dart';
import 'package:record/record.dart' hide IosAudioCategory;

import 'audio_data.dart';

/// 16 kHz mono PCM16 samples of a clip from [voiceClips] (skips the WAV header chunks).
Uint8List clipPcm(String name) {
  final b = base64Decode(voiceClips[name]!);
  final d = ByteData.sublistView(b);
  var i = 12;
  while (i + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(i, i + 4));
    final size = d.getUint32(i + 4, Endian.little);
    if (id == 'data') return Uint8List.sublistView(b, i + 8, (i + 8 + size).clamp(0, b.length));
    i += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw StateError('no data chunk in clip $name');
}

/// Stands in for the `record` package. Streams the chosen clip in real-time 100 ms
/// chunks, then silence until stopped, like a quiet room.
class FileRecorder implements AudioRecorder {
  String? clip;
  bool _recording = false;
  StreamController<Uint8List>? _ctl;
  Timer? _timer;
  DateTime? clipEndedAt;
  int starts = 0;

  Duration clipLength(String name) => Duration(milliseconds: clipPcm(name).length ~/ 32);

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<bool> isRecording() async => _recording;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    starts++;
    await _halt();
    final pcm = clip == null ? Uint8List(0) : clipPcm(clip!);
    clipEndedAt = null;
    var pos = 0;
    const chunk = 3200; // 100 ms
    final c = _ctl = StreamController<Uint8List>();
    _recording = true;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (c.isClosed) return;
      if (pos < pcm.length) {
        final end = (pos + chunk).clamp(0, pcm.length);
        final out = Uint8List(chunk)..setRange(0, end - pos, pcm, pos);
        pos = end;
        if (pos >= pcm.length) clipEndedAt = DateTime.now();
        c.add(out);
      } else {
        c.add(Uint8List(chunk));
      }
    });
    return c.stream;
  }

  Future<void> _halt() async {
    _timer?.cancel();
    _timer = null;
    final c = _ctl;
    _ctl = null;
    _recording = false;
    if (c != null && !c.isClosed) await c.close();
  }

  @override
  Future<String?> stop() async {
    await _halt();
    return null;
  }

  @override
  Future<void> cancel() => _halt();

  @override
  Future<void> dispose() => _halt();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

/// Never plays. Records what would have been said. The real [CartesiaSpeechOutput]
/// is built (so the app wiring is the real one) but never asked to speak.
class MutedOutput implements SpeechOutput {
  MutedOutput(this.real);
  final CartesiaSpeechOutput real;
  final spoken = <String>[];

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {}

  @override
  bool get canReplay => false;

  @override
  Future<void> replay() async {}

  @override
  Future<void> dispose() => real.dispose();
}
