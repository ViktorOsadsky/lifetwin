import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Debug-only hands-free event log (`[hf] <time> <source> <event> <detail>`), for finding
/// where a voice session stops being continuous on a real phone. Nothing is logged in a
/// release build. Heard words are logged only in a build for the voice harness
/// (VOICE_HARNESS_URL set), where they are the Mac's synthetic speech; otherwise only their length.
const voiceHarnessUrl = String.fromEnvironment('VOICE_HARNESS_URL');

/// One logged event: when, and its name (`onb mic_open`, `stt dropped` …).
typedef VoiceEvent = ({DateTime at, String source, String name, String detail});

/// The events so far (debug and profile builds only), newest last, for tests to read.
final List<VoiceEvent> voiceEvents = [];
const _keep = 2000;

http.Client? _client;
Future<void> _posting = Future.value();

/// What [text] may show in the log: the words in a harness build, their length otherwise.
String heardForLog(String text) => voiceHarnessUrl.isNotEmpty ? '"$text"' : '${text.length} chars';

void voiceLog(String source, String name, [String detail = '']) {
  if (kReleaseMode) return;
  final at = DateTime.now();
  voiceEvents.add((at: at, source: source, name: name, detail: detail));
  if (voiceEvents.length > _keep) voiceEvents.removeRange(0, voiceEvents.length - _keep);
  final line = '[hf] ${_time(at)} $source $name${detail.isEmpty ? '' : ' $detail'}';
  if (voiceHarnessUrl.isEmpty) return; // kept in [voiceEvents] only (unit tests stay quiet)
  debugPrint(line);
  // One at a time, so the harness log keeps the order.
  _posting = _posting.then((_) async {
    try {
      await (_client ??= http.Client())
          .post(
            Uri.parse('$voiceHarnessUrl/log'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'line': line}),
          )
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  });
}

String _time(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
String _two(int n) => n.toString().padLeft(2, '0');
