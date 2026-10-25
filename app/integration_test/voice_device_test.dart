// Hands-free voice on a real iPhone, with no person and no fake speech. Mochi speaks through
// the phone's speaker; the Mac answers through its own speakers (`say`, via the voice harness);
// the phone's microphone hears it, Cartesia Ink transcribes it, and the live server reads it.
// The test NEVER taps the microphone: every answer must be sent by a pause, and every listen
// must open by itself. A listen that does not open by itself counts as a needed tap (FAIL); the
// test then opens it the way a tap would, so the rest of the run still shows what else breaks.
//
//   1. Onboarding in voice mode (consent answered by tapping, as a person does): Mochi asks,
//      the Mac answers ("I'm seventy-two", "female" …), read-backs are answered "yes".
//      At the second question the Mac stays quiet for 80 s: the microphone must stay open, the
//      nudge must come exactly once, and the recognizer must restart out of sight (a listen
//      past 60 s), and the answer said after that must still be heard.
//   2. A quick daily check-in the same way, on a demo-seeded store.
// Timings: screen shown to first audio, TTS end to mic open, end of speech to send.
//
// Built as the app itself (flutter test cannot attach to the phone):
//   flutter build ios --config-only --profile -t integration_test/voice_device_test.dart \
//     --dart-define-from-file=<defines with API_BASE_URL and VOICE_HARNESS_URL>
//   then xcodebuild (Profile), devicectl install, devicectl process launch.
// Progress and the app's `[hf]` events go to the harness log; the result line is "VOICE-HF DONE".
// The test keeps its data in memory (its own TwinRepository on a MemoryBackend), so it never
// reads or writes the owner's LifeTwin data.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_screen.dart';
import 'package:lifesim/checkin/consent_screens.dart';
import 'package:lifesim/demo/demo_seed.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifesim/voice/voice_log.dart';

const harnessUrl = String.fromEnvironment('VOICE_HARNESS_URL', defaultValue: 'http://127.0.0.1:8099');

/// The whole run must end well inside the 12 minute limit.
const runBudget = Duration(minutes: 10);

/// Onboarding answers stop after this long, so the check-in still fits.
const onboardingBudget = Duration(minutes: 6);

final _client = http.Client();

Future<void> log(String line) async {
  debugPrint('VOICE-HF $line');
  try {
    await _client
        .post(
          Uri.parse('$harnessUrl/log'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'line': 'VOICE-HF $line'}),
        )
        .timeout(const Duration(seconds: 3));
  } catch (_) {}
}

Future<void> macSay(String text, {int rate = 170}) async {
  await _client
      .post(
        Uri.parse('$harnessUrl/say'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'text': text, 'rate': rate}),
      )
      .timeout(const Duration(seconds: 60));
}

/// One real-time step. The mascot animates for ever, so never pumpAndSettle.
Future<void> tick(WidgetTester t, [int ms = 100]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await t.pump();
}

Future<bool> waitUntil(WidgetTester t, bool Function() cond, {int seconds = 20}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    if (cond()) return true;
    await tick(t);
  }
  return cond();
}

bool shows(Finder f) => f.evaluate().isNotEmpty;

String oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String screenText() => oneLine(
  find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().join(' | '),
);

/// Consent and navigation taps only (never the microphone).
Future<bool> tapButton(WidgetTester t, String label, {int seconds = 20}) async {
  final f = find.widgetWithText(LipButton, label);
  if (!await waitUntil(t, () => shows(f), seconds: seconds)) return false;
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first, warnIfMissed: false);
  await t.pump();
  return true;
}

/// The first event named [name] from [source] after [after].
VoiceEvent? eventAfter(String source, String name, DateTime after, {String? detail}) {
  for (final e in voiceEvents) {
    if (e.source == source && e.name == name && e.at.isAfter(after) && (detail == null || e.detail.startsWith(detail))) {
      return e;
    }
  }
  return null;
}

int countSince(String source, String name, DateTime after, {String? detail}) => voiceEvents
    .where((e) => e.source == source && e.name == name && e.at.isAfter(after) && (detail == null || e.detail.startsWith(detail)))
    .length;

/// Every "TTS ended normally, then the microphone opened" gap in ms, since [after].
List<int> ttsToMic(String source, DateTime after) {
  final gaps = <int>[];
  DateTime? ended;
  for (final e in voiceEvents.where((e) => e.source == source && e.at.isAfter(after))) {
    if (e.name == 'tts_end') ended = e.detail.startsWith('done') || e.detail.startsWith('gave_up') ? e.at : null;
    if (e.name == 'tts_start' || e.name == 'send') ended = null;
    if (e.name == 'mic_open' && ended != null) {
      gaps.add(e.at.difference(ended).inMilliseconds);
      ended = null;
    }
  }
  return gaps;
}

/// Every "TTS ended, then the recorder was running" gap in ms (the moment words are kept).
List<int> ttsToRecorder(DateTime after) {
  final gaps = <int>[];
  DateTime? ended;
  for (final e in voiceEvents.where((e) => e.at.isAfter(after))) {
    if (e.name == 'tts_end' && e.source != 'tts') ended = e.at;
    if (e.source == 'stt' && e.name == 'recorder_started' && ended != null) {
      gaps.add(e.at.difference(ended).inMilliseconds);
      ended = null;
    }
  }
  return gaps;
}

String stats(List<int> ms) {
  if (ms.isEmpty) return 'n=0';
  final s = [...ms]..sort();
  return 'n=${s.length} median=${s[s.length ~/ 2]}ms max=${s.last}ms';
}

/// The microphone side of one conversation, onboarding or check-in.
class Voice {
  Voice(this.source, this.phase, this.listening, this.caption, this.turnOf, this.openByTap, this.done);
  final String source;
  final String Function() phase;
  final bool Function() listening;
  final String Function() caption;
  final Object? Function() turnOf;
  final Future<void> Function() openByTap;
  final bool Function() done;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('hands-free voice on the phone', timeout: const Timeout(Duration(minutes: 13)), (t) async {
    final runStart = DateTime.now();
    var pass = 0;
    var fail = 0;
    var tapsNeeded = 0;
    final results = <String>[];
    final timings = <String>[];
    final speechToSend = <int>[];

    Future<void> record(String name, bool ok, String detail) async {
      ok ? pass++ : fail++;
      final line = 'RESULT ${ok ? 'PASS' : 'FAIL'} [$name] $detail';
      results.add(line);
      await log(line);
    }

    /// Waits for the microphone to open by itself. If it doesn't, that is a needed tap: the
    /// test records it, then opens it as a tap would.
    Future<bool> micOpens(Voice v, String why, {int seconds = 25}) async {
      if (await waitUntil(t, () => v.listening() || v.done(), seconds: seconds)) return !v.done();
      tapsNeeded++;
      await record(
        'TAP NEEDED (${v.source}: $why)',
        false,
        'phase=${v.phase()} screen: ${screenText()}',
      );
      await v.openByTap();
      return waitUntil(t, v.listening, seconds: 10);
    }

    /// The Mac says [words] once the microphone is open; the pause must send it. Returns what was heard.
    Future<String?> answer(Voice v, String words) async {
      if (!await micOpens(v, 'before "$words"')) return null;
      // The socket is up before the first word, so nothing is lost.
      final opened = DateTime.now();
      await waitUntil(t, () => eventAfter('stt', 'socket_ready', opened.subtract(const Duration(seconds: 5))) != null,
          seconds: 4);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final before = v.turnOf();
      await log('  [${v.source}] mic open; Mac says "$words"');
      await macSay(words);
      final saidAt = DateTime.now();
      final sent = await waitUntil(t, () => eventAfter(v.source, 'send', saidAt.subtract(const Duration(seconds: 1))) != null,
          seconds: 15);
      if (!sent) {
        await record('${v.source} "$words" sent by the pause', false, 'no send 15 s after the speech; phase=${v.phase()} caption="${v.caption()}"');
        return null;
      }
      final send = eventAfter(v.source, 'send', saidAt.subtract(const Duration(seconds: 1)))!;
      final ms = send.at.difference(saidAt).inMilliseconds;
      speechToSend.add(ms);
      final heard = v.caption();
      await waitUntil(t, () => !identical(v.turnOf(), before) || v.done(), seconds: 40);
      await log('  [${v.source}] heard "$heard"; sent ${ms}ms after the speech ended');
      return heard;
    }

    try {
      await log('START harness=$harnessUrl');

      // ---- 1. Onboarding by voice ----
      final repo = await openTwin(backend: MemoryBackend(), demo: false);
      await t.pumpWidget(LifeTwinApp(twin: Future.value(repo)));
      await tick(t);
      final talk = await tapButton(t, 'Talk', seconds: 30);
      await Future<void>.delayed(const Duration(seconds: 1));
      await tick(t);
      final yes = await tapButton(t, "Yes, I'll talk");
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final notNow = await tapButton(t, 'Not now');
      final shownAt = DateTime.now();
      await log('  consent: talk=$talk yes=$yes aiNotNow=$notNow (consent taps, not microphone taps)');
      final c = t.widget<VoiceOnboardingScreen>(find.byType(VoiceOnboardingScreen)).controller;
      final onb = Voice(
        'onb',
        () => '${c.phase.name} typing=${c.typing} notice=${c.notice}',
        () => c.phase == VoicePhase.listening,
        () => c.caption,
        () => c.turn,
        () => c.startTalk(),
        () => c.phase == VoicePhase.done,
      );
      final firstAudio = await waitUntil(t, () => eventAfter('onb', 'first_audio', shownAt) != null, seconds: 30);
      final fa = eventAfter('onb', 'first_audio', shownAt);
      timings.add('onboarding: screen shown -> first audio ${fa?.at.difference(shownAt).inMilliseconds} ms (${fa?.detail})');
      await record('onb: Mochi speaks first, no tap', firstAudio, 'first_audio=${fa?.detail} tts=${eventAfter('onb', 'tts_end', shownAt)?.detail}');

      String words(String field) => switch (field) {
        'age' => "I'm seventy-two",
        'sex' => 'female',
        'smoking_status' => 'I quit smoking ten years ago',
        'height_cm' => 'five foot four',
        'weight_kg' => 'a hundred and forty five pounds',
        'sleep_hours' => 'about seven hours',
        'general_health' => 'good',
        'hypertension_diagnosed' => 'no',
        'diabetes' => 'no',
        'sedentary_min_day' => 'about six hours',
        'moderate_recreation_min_week' => 'I walk thirty minutes five days a week',
        'vigorous_recreation_min_week' => 'none',
        _ => 'yes',
      };
      var silenceDone = false;
      var recognitionSkips = 0;
      final tries = <String, int>{};
      final answered = <String>[];
      for (var i = 0; i < 40 && c.phase != VoicePhase.done; i++) {
        if (DateTime.now().difference(runStart) > onboardingBudget) {
          await log('  onboarding budget used; moving on to the check-in');
          break;
        }
        await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
        if (shows(find.byType(OutsideAiConsentScreen))) {
          await log('  NOTE outside-AI consent covered the conversation');
          await tapButton(t, 'No thanks', seconds: 3);
        }
        final field = '${c.turn?.state['current_field']}';
        final phase = '${c.turn?.state['phase']}';
        if (!silenceDone) {
          // ---- the long quiet, at the first question: it never closes the microphone ----
          silenceDone = true;
          if (!await micOpens(onb, 'before the long quiet')) break;
          final quietFrom = DateTime.now();
          DateTime? idleAt;
          var longestIdle = 0;
          while (DateTime.now().difference(quietFrom) < const Duration(seconds: 80)) {
            // Idle = neither listening, nor Mochi speaking, nor waiting for the server: a tap would be needed.
            if (c.phase == VoicePhase.idle) {
              idleAt ??= DateTime.now();
              final ms = DateTime.now().difference(idleAt).inMilliseconds;
              if (ms > longestIdle) longestIdle = ms;
            } else {
              idleAt = null;
            }
            await tick(t, 200);
          }
          final nudges = countSince('onb', 'nudge', quietFrom);
          final restarts = countSince('onb', 'recognizer_restart', quietFrom);
          final drops = countSince('onb', 'dropped', quietFrom);
          final roomSpeech = countSince('onb', 'send', quietFrom);
          final closes = voiceEvents
              .where((e) => e.source == 'onb' && e.name == 'mic_close' && e.at.isAfter(quietFrom))
              .map((e) => e.detail)
              .toList();
          await record(
            'onb: 80 s quiet never leaves the mic closed',
            longestIdle < 3000 && c.phase != VoicePhase.idle,
            'longestIdleMs=$longestIdle phase=${c.phase.name} notice=${c.notice} closes=$closes drops=$drops',
          );
          // Speech in the room during the quiet (sent as answers) resets the quiet: then the
          // nudge and the 50 s restart are not expected, and are reported only.
          final quiet = roomSpeech == 0;
          await record(
            'onb: one nudge, recognizer restarted past 60 s${quiet ? '' : ' (room speech heard: informational)'}',
            !quiet || (nudges == 1 && restarts >= 1),
            'nudges=$nudges restarts=$restarts roomSpeechSends=$roomSpeech',
          );
          continue;
        }
        final key = '$field/$phase';
        tries[key] = (tries[key] ?? 0) + 1;
        if (tries[key]! > 3) {
          // Not understood three times (speech in the room): skip, as a person would, and go on.
          recognitionSkips++;
          await log('  recognition: "$key" not understood 3 times; Skip');
          final before = c.turn;
          await c.skip();
          await waitUntil(t, () => !identical(c.turn, before), seconds: 30);
          continue;
        }
        final say = c.confirming
            ? 'yes'
            : switch (phase) {
                'remembering' => 'yes please',
                'offering' => 'no thanks',
                'probing' => "let's move on",
                _ => words(field),
              };
        final heard = await answer(onb, say);
        answered.add('$field${c.confirming ? '(readback)' : ''}="$say"->"${heard ?? 'NOT SENT'}"');
      }
      await log('  onboarding answers: ${answered.join('; ')}');
      final gapsOnb = ttsToMic('onb', shownAt);
      timings.add('onboarding: TTS end -> mic open ${stats(gapsOnb)}');
      timings.add('onboarding: TTS end -> recorder running ${stats(ttsToRecorder(shownAt))}');
      await record('onb: answers by voice, no microphone tap', tapsNeeded == 0 && answered.length >= 4,
          'answers=${answered.length} tapsNeeded=$tapsNeeded recognitionSkips=$recognitionSkips '
          'field=${c.turn?.state['current_field']} confirmed=${jsonEncode(c.confirmedProfile)}');

      // ---- 2. A quick daily check-in by voice ----
      if (DateTime.now().difference(runStart) < runBudget) {
        final tapsBefore = tapsNeeded;
        final repo2 = await openTwin(backend: MemoryBackend(), demo: true);
        await t.pumpWidget(const SizedBox());
        await tick(t);
        await t.pumpWidget(LifeTwinApp(twin: Future.value(repo2)));
        await tick(t);
        if (await waitUntil(t, () => shows(find.byType(OutsideAiConsentScreen)), seconds: 15)) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          await tick(t);
          final f = find.text('No thanks');
          if (shows(f)) await t.tap(f.first, warnIfMissed: false);
          await waitUntil(t, () => !shows(find.byType(OutsideAiConsentScreen)), seconds: 5);
        }
        final opened = await tapButton(t, 'Check in', seconds: 30);
        final chkShown = DateTime.now();
        await waitUntil(t, () => shows(find.byType(CheckInScreen)), seconds: 5);
        final k = shows(find.byType(CheckInScreen)) ? t.widget<CheckInScreen>(find.byType(CheckInScreen)).controller : null;
        if (!opened || k == null) {
          await record('chk: open', false, 'opened=$opened screen: ${screenText()}');
        } else {
          final chk = Voice(
            'chk',
            () => '${k.phase.name} typing=${k.typing} notice=${k.notice}',
            () => k.phase == CheckinPhase.listening,
            () => k.caption,
            () => k.turn,
            () => k.startTalk(),
            () => k.phase == CheckinPhase.done,
          );
          final first = await waitUntil(t, () => eventAfter('chk', 'first_audio', chkShown) != null, seconds: 30);
          final fa2 = eventAfter('chk', 'first_audio', chkShown);
          timings.add('check-in: screen shown -> first audio ${fa2?.at.difference(chkShown).inMilliseconds} ms (${fa2?.detail})');
          await record('chk: Mochi speaks first, no tap', first, 'first_audio=${fa2?.detail} voiceUsable=${k.voiceUsable}');
          String chkWords(String f) {
            if (f.contains('sleep')) return 'about seven hours';
            if (f.contains('vigorous')) return 'no, nothing';
            if (f.contains('moderate')) return 'I walked for about thirty minutes';
            if (f.contains('sedentary')) return 'about six hours';
            if (f.contains('wellbeing')) return 'good';
            return 'yes';
          }

          final said = <String>[];
          final chkTries = <String, int>{};
          for (var i = 0; i < 10 && k.phase != CheckinPhase.done; i++) {
            if (DateTime.now().difference(runStart) > runBudget) break;
            await waitUntil(t, () => k.phase != CheckinPhase.interpreting, seconds: 30);
            if (k.phase == CheckinPhase.done || (k.turn?.complete ?? false)) break;
            final f = k.turn?.currentField ?? '';
            final key = '$f/${k.turn?.phase}';
            chkTries[key] = (chkTries[key] ?? 0) + 1;
            if (chkTries[key]! > 3) {
              await log('  recognition: "$key" not understood 3 times; Skip');
              final before = k.turn;
              await k.skip();
              await waitUntil(t, () => !identical(k.turn, before), seconds: 30);
              continue;
            }
            final say = k.confirming || k.finalReadback ? "yes, that's right" : chkWords(f);
            final heard = await answer(chk, say);
            said.add('$f${k.confirming ? '(readback)' : ''}="$say"->"${heard ?? 'NOT SENT'}"');
          }
          final done = await waitUntil(t, () => k.phase == CheckinPhase.done || (k.turn?.complete ?? false), seconds: 20);
          await log('  check-in answers: ${said.join('; ')}');
          timings.add('check-in: TTS end -> mic open ${stats(ttsToMic('chk', chkShown))}');
          timings.add('check-in: TTS end -> recorder running ${stats(ttsToRecorder(chkShown))}');
          await record('chk: finished by voice, no microphone tap', done && tapsNeeded == tapsBefore,
              'done=$done answers=${said.length} tapsNeeded=${tapsNeeded - tapsBefore} saved=${repo2.store.checkins.length}');
        }
      }
      timings.add('end of speech -> send ${stats(speechToSend)}');
    } catch (e, s) {
      fail++;
      await log('EXCEPTION $e ${s.toString().split('\n').take(6).join(' / ')}');
    } finally {
      await log('TIMINGS\n${timings.join('\n')}');
      await log('SUMMARY\n${results.join('\n')}');
      await log('DONE pass=$pass fail=$fail tapsNeeded=$tapsNeeded');
    }
  });
}
