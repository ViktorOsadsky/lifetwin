// Manual browser check: flutter build web --target tool/browser_pcm_smoke.dart
// --output build/browser-pcm-smoke --release --no-web-resources-cdn
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lifesim/voice/browser_pcm_stub.dart'
    if (dart.library.js_interop) 'package:lifesim/voice/browser_pcm_web.dart';
import 'package:lifesim/voice/pcm_player.dart';

void main() => runApp(const MaterialApp(home: AudioCheck()));

class AudioCheck extends StatefulWidget {
  const AudioCheck({super.key});
  @override
  State<AudioCheck> createState() => _AudioCheckState();
}

class _AudioCheckState extends State<AudioCheck> {
  final PcmPlayer? player = createBrowserPcmPlayer();
  String status = 'Ready';
  int generation = 0;

  Future<void> play() async {
    final current = ++generation;
    setState(() => status = 'Playing');
    try {
      await player!.begin(24000);
      final pcm = Uint8List(24000 * 2 * 3);
      final data = ByteData.sublistView(pcm);
      for (var i = 0; i < pcm.length ~/ 2; i++) {
        final envelope = math.min(
          1.0,
          math.min(i / 240, (pcm.length ~/ 2 - i) / 240),
        );
        data.setInt16(
          i * 2,
          (2000 * envelope * math.sin(2 * math.pi * 440 * i / 24000)).round(),
          Endian.little,
        );
      }
      // Intentionally split samples on odd byte boundaries, as network chunks may.
      for (var i = 0; i < pcm.length; i += 501) {
        await player!.feed(
          Uint8List.sublistView(pcm, i, math.min(i + 501, pcm.length)),
        );
      }
      await player!.finish();
      if (mounted && current == generation) {
        setState(() => status = 'Playback finished');
      }
    } catch (error) {
      if (mounted && current == generation) {
        setState(() => status = 'Failed: $error');
      }
    }
  }

  Future<void> stop() async {
    generation++;
    await player?.stop();
    if (mounted) setState(() => status = 'Stopped');
  }

  @override
  void dispose() {
    generation++;
    player?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Browser PCM playback check',
                style: TextStyle(fontSize: 24),
              ),
              const Text(
                'Three-second synthetic tone. No microphone, provider or health data.',
              ),
              const SizedBox(height: 24),
              Text(status, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: player == null ? null : play,
                child: const Text('Play test tone'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: stop, child: const Text('Stop')),
            ],
          ),
        ),
      ),
    ),
  );
}
