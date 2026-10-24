// SILENT end-to-end voice test for the iOS Simulator. Real Cartesia Ink, real
// server, real UI. The microphone is a WAV file ([FileRecorder]); speech output
// is muted ([MutedOutput]). Nothing plays out loud.
//   flutter test integration_test/voice_sim_test.dart -d <sim> --dart-define=API_BASE_URL=http://127.0.0.1:8020
// Clips come from support/gen_audio.sh (macOS `say` to files).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/voice/cartesia_speech.dart';
import 'package:lifesim/voice/http_conversation_guide.dart';
import 'package:lifesim/voice/speech.dart';
import 'package:lifesim/voice/voice_token.dart';
import 'package:lifesim/widgets/lip_button.dart';

import 'support/sim_support.dart';

/// Time after the clip ends for Ink to send the last words.
const inkTail = Duration(milliseconds: 1200);

void log(String line) => debugPrint('VOICE-SIM $line');

Future<void> tick(WidgetTester t, [int ms = 100]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await t.pump();
}

Future<void> pumpFor(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tick(t);
  }
}

Future<bool> waitUntil(WidgetTester t, bool Function() cond, {int seconds = 20}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    if (cond()) return true;
    await tick(t);
  }
  return cond();
}

VoiceOnboardingController ctl(WidgetTester t) =>
    t.widget<VoiceOnboardingScreen>(find.byType(VoiceOnboardingScreen)).controller;

String fieldOf(VoiceOnboardingController c) => '${c.turn?.state['current_field']}';
String oneLine(String s) => s.replaceAll('\n', ' ');

String screenText() => find
    .byType(Text)
    .evaluate()
    .map((e) => (e.widget as Text).data)
    .whereType<String>()
    .where((s) => s.isNotEmpty)
    .join(' | ');

Future<bool> tapFinder(WidgetTester t, Finder f, {int seconds = 20}) async {
  if (!await waitUntil(t, () => f.evaluate().isNotEmpty, seconds: seconds)) return false;
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first, warnIfMissed: false);
  await t.pump();
  return true;
}

Future<bool> tapButton(WidgetTester t, String label, {int seconds = 20}) =>
    tapFinder(t, find.widgetWithText(LipButton, label), seconds: seconds);

Future<bool> waitForTurn(WidgetTester t, GuideTurn? before, {int seconds = 60}) async {
  final c = ctl(t);
  final end = DateTime.now().add(Duration(seconds: seconds));
  var lastRetry = DateTime.now();
  while (DateTime.now().isBefore(end)) {
    if (!identical(c.turn, before) && c.phase != VoicePhase.interpreting) return true;
    if (c.phase != VoicePhase.interpreting && c.phase != VoicePhase.listening && c.notice != null) {
      if (c.canRetry && DateTime.now().difference(lastRetry).inSeconds >= 12) {
        log('  notice "${c.notice}" -> Try again');
        lastRetry = DateTime.now();
        await tapButton(t, 'Try again', seconds: 2);
      } else if (!c.canRetry) {
        return false;
      }
    }
    await tick(t);
  }
  return false;
}

class Heard {
  String live = ''; // last "Hearing: ..." caption while the mic was open
  String said = ''; // what the app sent
  String reply = ''; // the mascot's line after the turn
  bool confirming = false;
  String? notice;
  String? error;
  bool stoppedItself = false;

  @override
  String toString() =>
      'ink_live="$live" ink_final="$said" readback="${oneLine(reply)}"'
      '${stoppedItself ? ' (Talk stopped itself)' : ''}'
      '${notice != null ? ' notice="$notice"' : ''}${error != null ? ' error="$error"' : ''}';
}

/// Taps Talk, streams [clip] as the microphone, taps Talk again, waits for the reply.
Future<Heard> talk(WidgetTester t, FileRecorder mic, String clip) async {
  final c = ctl(t);
  final h = Heard();
  final talkButton = find.byType(TalkButton);
  final ready = await waitUntil(
    t,
    () => talkButton.evaluate().isNotEmpty && (c.phase == VoicePhase.idle || c.phase == VoicePhase.speaking),
    seconds: 30,
  );
  if (!ready) {
    h.error = 'no Talk button (phase ${c.phase}); screen: ${screenText()}';
    return h;
  }
  final before = c.turn;
  mic.clip = clip;
  await t.ensureVisible(talkButton);
  await t.pump();
  await t.tap(talkButton, warnIfMissed: false);
  if (!await waitUntil(t, () => c.phase == VoicePhase.listening, seconds: 10)) {
    h.error = 'mic never opened (phase ${c.phase}, notice ${c.notice})';
    return h;
  }
  log('  [mic file] "$clip" (${mic.clipLength(clip).inMilliseconds} ms)');
  while (mic.clipEndedAt == null && c.phase == VoicePhase.listening) {
    if (c.caption.isNotEmpty) h.live = c.caption;
    await tick(t);
  }
  final tail = DateTime.now().add(inkTail);
  while (DateTime.now().isBefore(tail)) {
    if (c.phase == VoicePhase.listening && c.caption.isNotEmpty) h.live = c.caption;
    await tick(t);
  }
  if (c.phase == VoicePhase.listening) {
    await t.ensureVisible(talkButton);
    await t.pump();
    await t.tap(talkButton, warnIfMissed: false); // stop and send
  } else {
    h.stoppedItself = true;
  }
  final got = await waitForTurn(t, before);
  h.said = c.caption;
  h.reply = c.mascotLine;
  h.confirming = c.confirming;
  h.notice = c.notice;
  if (!got && identical(c.turn, before)) h.error ??= 'no new turn from the server';
  return h;
}

Future<bool> tapYes(WidgetTester t) async {
  final c = ctl(t);
  final before = c.turn;
  if (!await tapButton(t, 'Yes')) return false;
  return waitForTurn(t, before);
}

Future<void> recover(WidgetTester t) async {
  final c = ctl(t);
  await waitUntil(t, () => c.phase != VoicePhase.interpreting && c.phase != VoicePhase.listening, seconds: 30);
  if (c.confirming && c.correcting) {
    await tapButton(t, 'Never mind', seconds: 3);
    await t.pump();
  }
  if (c.confirming) {
    log('  recover: tapping Yes on "${oneLine(c.mascotLine)}"');
    await tapYes(t);
  } else if (c.phase != VoicePhase.done) {
    log('  recover: skipping ${fieldOf(c)}');
    final before = c.turn;
    unawaited(c.skip());
    await waitForTurn(t, before);
  }
}

/// From a read-back, goes back to talking (the read-back screen may lack a Talk button).
Future<void> toCorrection(WidgetTester t) async {
  if (find.byType(TalkButton).evaluate().isEmpty) {
    log('  note: read-back has no Talk button; tapping "No, change it"');
    await tapButton(t, 'No, change it');
    await waitUntil(t, () => find.byType(TalkButton).evaluate().isNotEmpty, seconds: 5);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('silent voice end to end: audio files in, Ink, server, UI', timeout: const Timeout(Duration(minutes: 20)), (
    t,
  ) async {
    var pass = 0;
    var fail = 0;
    final results = <String>[];
    void record(String name, bool ok, String detail, [String why = '']) {
      ok ? pass++ : fail++;
      final line = 'RESULT ${ok ? 'PASS' : 'FAIL'} [$name] $detail${why.isEmpty ? '' : ' why="$why"'}';
      results.add(line);
      log(line);
    }

    final mic = FileRecorder();
    final api = ApiBase();
    final tokens = VoiceTokenProvider(base: api);
    final output = MutedOutput(CartesiaSpeechOutput(tokens: tokens));
    final controller = VoiceOnboardingController(
      guide: HttpConversationGuide(base: api),
      input: CartesiaSpeechInput(tokens: tokens, recorder: mic),
      output: output,
    );

    try {
      log('START api=${const String.fromEnvironment('API_BASE_URL')}');
      await t.pumpWidget(LifeTwinApp(controller: controller));
      await tick(t);
      final c = ctl(t);
      if (!await tapButton(t, "Yes, I'll talk") || !await tapButton(t, 'Not now')) {
        record('consent', false, '', 'could not get past consent; screen: ${screenText()}');
        return;
      }
      if (!await waitUntil(t, () => c.turn != null && c.phase != VoicePhase.interpreting, seconds: 40)) {
        record('first question', false, '', 'never came; notice=${c.notice}; screen: ${screenText()}');
        return;
      }
      log('first question (${fieldOf(c)}): "${oneLine(c.mascotLine)}"');

      {
        final h = await talk(t, mic, 'what');
        final ok = h.error == null && !h.confirming && fieldOf(c) == 'age' && h.reply.contains('How old are you');
        record(
          'what? repeats question',
          ok,
          '$h',
          ok ? '' : h.error ?? (h.confirming ? 'read-back shown' : 'question not repeated / field ${fieldOf(c)}'),
        );
        if (c.confirming) await recover(t);
      }

      {
        final h = await talk(t, mic, 'born');
        final ok = h.error == null && h.confirming && (h.reply.contains('74') || h.reply.contains('73'));
        record('born 1952 -> 74/73', ok, '$h', ok ? '' : h.error ?? 'read-back lacks 74/73 or none');
        if (c.confirming) {
          await toCorrection(t);
          final k = await talk(t, mic, 'sixty');
          final ok2 = k.error == null && k.confirming && k.reply.contains('you are 60');
          record('"no, sixty" corrects read-back', ok2, '$k', ok2 ? '' : k.error ?? 'read-back lacks "you are 60"');
          if (c.confirming) {
            if (!await tapYes(t)) await recover(t);
          } else {
            await recover(t);
          }
        } else {
          record('"no, sixty" corrects read-back', false, 'skipped', 'no age read-back to correct');
          await recover(t);
        }
      }

      // Chatter before the answer, at the sex question.
      await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
      {
        final h = await talk(t, mic, 'chatter');
        final ok = h.error == null && h.confirming && h.reply.contains('female at birth');
        record(
          'chatter + "Female."',
          ok,
          '$h',
          ok ? '' : h.error ?? (h.confirming ? 'read-back lacks female at birth' : 'no read-back (chatter not handled)'),
        );
        if (c.confirming) {
          // Now the clean "female" clip, as a correction of the read-back.
          await toCorrection(t);
          final k = await talk(t, mic, 'sex');
          final ok2 = k.error == null && k.confirming && k.reply.contains('female at birth');
          record('sex: "female"', ok2, '$k', ok2 ? '' : k.error ?? 'no read-back / lacks female at birth');
          if (c.confirming) {
            if (!await tapYes(t)) await recover(t);
          } else {
            await recover(t);
          }
        } else {
          await recover(t);
        }
      }

      const steps = [
        ('height_cm', 'height', 'five foot four', ['5 feet 4 inches']),
        ('weight_kg', 'weight', 'a hundred and forty five pounds', ['145 pounds']),
        ('sleep_hours', 'sleep', 'about seven hours', ['7 hours']),
        ('exercise_minutes_weekly', 'exercise', 'I walk thirty minutes five days a week', ['150 minutes']),
        ('smoking_status', 'smoking', 'I used to smoke but I quit years ago', ['smoked in the past']),
        ('alcohol_drinks_weekly', 'alcohol', 'two glasses of wine a week', ['2 drinks']),
        ('diabetes', 'diabetes', 'no', ['not told you that you have diabetes']),
        ('systolic_bp', 'bp', 'one thirty over eighty five', ['130 over 85']),
      ];
      for (final (field, clip, words, expects) in steps) {
        await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
        if (fieldOf(c) != field) log('  note: expected field $field but the app is on ${fieldOf(c)}');
        final h = await talk(t, mic, clip);
        final missing = expects.where((e) => !h.reply.contains(e)).toList();
        final ok = h.error == null && h.confirming && missing.isEmpty;
        record(
          '$field: "$words"',
          ok,
          '$h',
          ok ? '' : h.error ?? (h.confirming ? 'read-back lacks ${missing.join(', ')}' : 'no read-back'),
        );
        if (ok) {
          if (!await tapYes(t)) await recover(t);
        } else {
          await recover(t);
        }
      }

      for (var i = 0; i < 3 && !await waitUntil(t, () => c.phase == VoicePhase.done, seconds: 5); i++) {
        await recover(t);
      }
      final finished = await waitUntil(t, () => c.phase == VoicePhase.done, seconds: 20);
      log('conversation ${finished ? 'finished' : 'NOT finished (phase ${c.phase})'}; confirmed=${jsonEncode(c.confirmedProfile)}');

      if (finished && await tapButton(t, 'Continue')) {
        final seen = await waitUntil(t, () => screenText().contains('still living'), seconds: 45);
        record('forecast screen', seen, 'screen="${screenText()}"', seen ? '' : 'no "still living" text');
      } else {
        record('forecast screen', false, '', 'conversation not finished / no Continue button; screen: ${screenText()}');
      }
      log('muted output would have said ${output.spoken.length} lines; mic opened ${mic.starts} times');
    } catch (e, s) {
      fail++;
      log('EXCEPTION $e\n$s');
    } finally {
      log('SUMMARY\n${results.join('\n')}');
      log('VOICE-SIM DONE pass=$pass fail=$fail');
    }
    expect(fail, 0);
  });
}
