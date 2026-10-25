import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/voice/cartesia_speech.dart';
import 'package:lifesim/voice/voice_token.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Test stand-ins for the Cartesia engine: a token server, a microphone, sockets and a player.

String tokenBody(int n) => jsonEncode({
  'token': 'tok$n',
  'expires_in': 300,
  'cartesia_version': '2025-04-16',
  'stt': {'model': 'ink-whisper'},
  'tts': {'model': 'sonic-2', 'voice_id': 'v'},
});

/// A token server that answers when [gate] is completed (at once when null).
class TokenServer {
  Completer<void>? gate;
  int status = 200;
  int mints = 0;
  late final provider = VoiceTokenProvider(
    baseUrl: 'http://x',
    client: MockClient((_) async {
      await gate?.future;
      mints++;
      return http.Response(status == 200 ? tokenBody(mints) : '', status);
    }),
  );
}

class FakeRecorder implements AudioRecorder {
  final mic = StreamController<Uint8List>.broadcast();
  bool recording = false;
  int starts = 0;
  int cancels = 0;

  /// How long each call to the platform takes (a real phone answers in a few ms, in order).
  Duration latency = Duration.zero;
  Future<void> _lag() => latency == Duration.zero ? Future.value() : Future.delayed(latency);

  @override
  Future<bool> hasPermission({bool request = true}) async {
    await _lag();
    return true;
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    await _lag();
    starts++;
    recording = true;
    lastConfig = config;
    return mic.stream;
  }

  RecordConfig? lastConfig;

  @override
  Future<String?> stop() async {
    await _lag();
    recording = false;
    return null;
  }

  @override
  Future<void> cancel() async {
    await _lag();
    cancels++;
    recording = false;
  }

  @override
  Future<bool> isRecording() async {
    await _lag();
    return recording;
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeSink implements WebSocketSink {
  final sent = <Object?>[];
  bool closed = false;
  @override
  void add(Object? data) => sent.add(data);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async => closed = true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeSocket implements WebSocketChannel {
  FakeSocket(this.uri);
  final Uri uri;
  final opened = Completer<void>();
  final incoming = StreamController<dynamic>();
  @override
  final FakeSink sink = FakeSink();
  @override
  Future<void> get ready => opened.future;
  @override
  Stream<dynamic> get stream => incoming.stream;
  void open() => opened.complete();
  void reply(Map<String, Object?> m) => incoming.add(jsonEncode(m));

  /// Audio chunks and text messages sent so far.
  List<Uint8List> get audio => sink.sent.whereType<Uint8List>().toList();
  List<String> get texts => sink.sent.whereType<String>().toList();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Hands out [FakeSocket]s; [autoOpen] opens each one at once.
class Sockets {
  Sockets({this.autoOpen = true});
  final bool autoOpen;
  final made = <FakeSocket>[];
  FakeSocket get last => made.last;
  WebSocketChannel connect(Uri uri) {
    final s = FakeSocket(uri);
    made.add(s);
    if (autoOpen) s.open();
    return s;
  }
}

class FakePlayer implements PcmPlayer {
  final calls = <String>[];
  Completer<void>? beginGate;
  @override
  Future<void> begin(int sampleRate) async {
    calls.add('begin');
    await beginGate?.future;
  }

  @override
  Future<void> feed(Uint8List pcm) async => calls.add('feed');
  @override
  Future<void> finish() async => calls.add('finish');
  @override
  Future<void> stop() async => calls.add('stop');
}

/// A loud chunk of 16 kHz PCM16 (100 ms), so it counts as speech.
Uint8List loudChunk([int value = 4000]) {
  final b = ByteData(3200);
  for (var i = 0; i < 1600; i++) {
    b.setInt16(i * 2, i.isEven ? value : -value, Endian.little);
  }
  return b.buffer.asUint8List();
}
