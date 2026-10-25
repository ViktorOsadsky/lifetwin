import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/voice/browser_pcm_stub.dart';
import 'package:lifesim/voice/pcm_player.dart';

class Device implements PcmAudioDevice {
  double time = 1;
  Completer<void>? gate;
  final sources = <Source>[];
  @override
  double get currentTime => time;
  @override
  Future<void> resume() async => gate?.future;
  @override
  Source schedule(Float32List samples, int sampleRate, double when) {
    final source = Source(Float32List.fromList(samples), sampleRate, when);
    sources.add(source);
    return source;
  }
}

class Source implements PcmAudioSource {
  Source(this.samples, this.rate, this.when);
  final Float32List samples;
  final int rate;
  final double when;
  final done = Completer<void>();
  bool stopped = false;
  @override
  Future<void> get ended => done.future;
  @override
  void stop() => stopped = true;
}

void main() {
  test('non-browser factory retains the existing native player selection', () {
    expect(createBrowserPcmPlayer(), isNull);
  });

  test('split PCM16 little-endian samples retain sign, amplitude and byte boundaries', () async {
    final device = Device();
    final player = ScheduledPcmPlayer(device);
    await player.begin(24000);
    await player.feed(Uint8List.fromList([0]));
    expect(device.sources, isEmpty);
    await player.feed(Uint8List.fromList([128, 255]));
    await player.feed(Uint8List.fromList([127, 0, 0]));
    expect(device.sources.expand((s) => s.samples), [-1.0, 32767 / 32768, 0.0]);
    expect(device.sources.every((s) => s.rate == 24000), isTrue);
    await player.stop();
  });

  test(
    'chunks queue on the device clock and finish waits for every source',
    () async {
      final device = Device();
      final player = ScheduledPcmPlayer(device);
      await player.begin(24000);
      await player.feed(Uint8List(4800)); // 100 ms
      await player.feed(Uint8List(9600)); // 200 ms
      expect(device.sources[0].when, closeTo(1.02, 1e-9));
      expect(device.sources[1].when, closeTo(1.12, 1e-9));
      var finished = false;
      final finishing = player.finish().then((_) => finished = true);
      device.sources[1].done.complete();
      await pumpEventQueue();
      expect(
        finished,
        isFalse,
        reason: 'Completion of one chunk cannot end another chunk early.',
      );
      device.sources[0].done.complete();
      await finishing;
      expect(finished, isTrue);
    },
  );

  test('an underrun schedules new audio in the future rather than overlapping old audio', () async {
    final device = Device();
    final player = ScheduledPcmPlayer(device);
    await player.begin(16000);
    await player.feed(Uint8List(3200));
    device.time = 2;
    await player.feed(Uint8List(3200));
    expect(device.sources.last.when, closeTo(2.02, 1e-9));
    await player.stop();
  });

  test(
    'stop cancels queued sound, releases finish and discards late data',
    () async {
      final device = Device();
      final player = ScheduledPcmPlayer(device);
      await player.begin(24000);
      await player.feed(Uint8List(4800));
      final finishing = player.finish();
      await player.stop();
      await finishing;
      expect(device.sources.single.stopped, isTrue);
      await player.feed(Uint8List(4800));
      expect(device.sources, hasLength(1));
      await player.begin(24000);
      await player.feed(Uint8List(4800));
      var newFinished = false;
      final second = player.finish().then((_) => newFinished = true);
      device.sources.first.done
          .complete(); // stale ended event from the cancelled line
      await pumpEventQueue();
      expect(newFinished, isFalse);
      device.sources.last.done.complete();
      await second;
    },
  );

  test('a pending audio unlock cannot resume a cancelled utterance', () async {
    final device = Device()..gate = Completer<void>();
    final player = ScheduledPcmPlayer(device);
    final beginning = player.begin(24000);
    await pumpEventQueue();
    await player.stop();
    device.gate!.complete();
    await beginning;
    await player.feed(Uint8List(4800));
    expect(device.sources, isEmpty);
  });

  test('malformed and unbounded streams stop their queued audio', () async {
    final device = Device();
    final player = ScheduledPcmPlayer(device);
    await player.begin(8000);
    await player.feed(Uint8List(1600));
    await player.feed(Uint8List(1));
    await expectLater(player.finish(), throwsStateError);
    expect(device.sources.first.stopped, isTrue);
    await player.begin(8000);
    await expectLater(player.feed(Uint8List(8000 * 2 * 61)), throwsStateError);
    await expectLater(player.begin(0), throwsArgumentError);
  });
}
