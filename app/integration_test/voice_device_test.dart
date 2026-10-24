// End-to-end VOICE test on a real iPhone, no person needed. The phone taps
// Talk, the Mac speaks the answer through its speakers (`say`, via the voice
// harness), the phone's microphone hears it, Cartesia Ink transcribes it, the
// LifeTwin server reads it, and the test checks the read-back.
//
// `flutter test` / `flutter drive` cannot attach to the phone, so this file is
// built as the app itself and its output read from the device console:
//   flutter build ios --config-only --profile -t integration_test/voice_device_test.dart \
//     --dart-define=API_BASE_URL=http://<mac>:8000 --dart-define=VOICE_HARNESS_URL=http://<mac>:8099
//   (then xcodebuild, devicectl install, devicectl process launch --console)
// The Mac must be running the voice harness on port 8099.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/voice/speech.dart';
import 'package:lifesim/ui/widgets/widgets.dart';

const harnessUrl = String.fromEnvironment('VOICE_HARNESS_URL', defaultValue: 'http://169.254.4.42:8099');

/// Time from "Listening" to the first word, so the token, socket and mic are up.
const micWarmUp = Duration(milliseconds: 1000);

/// Time after `say` finishes for Ink to send the last words.
const inkTail = Duration(milliseconds: 1200);

final _client = http.Client();

Future<void> log(String line) async {
  debugPrint('VOICE-E2E $line');
  try {
    await _client
        .post(
          Uri.parse('$harnessUrl/log'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'line': line}),
        )
        .timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('VOICE-E2E (log post failed: $e)');
  }
}

Future<http.Response> macSay(String text, {int rate = 170}) => _client
    .post(
      Uri.parse('$harnessUrl/say'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'text': text, 'rate': rate}),
    )
    .timeout(const Duration(seconds: 60));

/// One real-time step. The mascot animates for ever, so never pumpAndSettle.
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

/// Waits for the server's next turn (or a notice). Taps "Try again" after a
/// rate-limit, as a person would.
Future<bool> waitForTurn(WidgetTester t, GuideTurn? before, {int seconds = 60}) async {
  final c = ctl(t);
  final end = DateTime.now().add(Duration(seconds: seconds));
  var lastRetry = DateTime.now();
  while (DateTime.now().isBefore(end)) {
    if (!identical(c.turn, before) && c.phase != VoicePhase.interpreting) return true;
    if (c.phase != VoicePhase.interpreting && c.phase != VoicePhase.listening && c.notice != null) {
      if (c.canRetry && DateTime.now().difference(lastRetry).inSeconds >= 12) {
        await log('  notice "${c.notice}" -> Try again');
        lastRetry = DateTime.now();
        await tapButton(t, 'Try again', seconds: 2);
      } else if (!c.canRetry) {
        return false; // e.g. "I didn't catch that": no new turn is coming
      }
    }
    await tick(t);
  }
  return false;
}

class Heard {
  Heard({this.live = '', this.said = '', this.reply = '', this.confirming = false, this.notice, this.error});
  String live; // last "Hearing: ..." caption while the mic was open
  String said; // what the app sent ("You said: ...")
  String reply; // the mascot's line after the turn
  bool confirming;
  String? notice;
  String? error;

  @override
  String toString() =>
      'ink_live="$live" ink_final="$said" readback="${oneLine(reply)}"'
      '${notice != null ? ' notice="$notice"' : ''}${error != null ? ' error="$error"' : ''}';
}

/// Taps Talk, has the Mac say [text], taps Talk again, and waits for the reply.
Future<Heard> talk(WidgetTester t, String text) async {
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
  await t.ensureVisible(talkButton);
  await t.pump();
  await t.tap(talkButton, warnIfMissed: false); // short tap: keeps listening
  if (!await waitUntil(t, () => c.phase == VoicePhase.listening, seconds: 10)) {
    h.error = 'mic never opened (phase ${c.phase}, notice ${c.notice})';
    return h;
  }
  await pumpFor(t, micWarmUp);
  if (c.phase != VoicePhase.listening) {
    h.error = 'mic closed during warm-up (phase ${c.phase}, notice ${c.notice})';
    return h;
  }
  await log('  [phone] listening; Mac says "$text"');
  var sayDone = false;
  Object? sayError;
  unawaited(macSay(text).then<void>((_) {}, onError: (Object e) => sayError = e).whenComplete(() => sayDone = true));
  while (!sayDone) {
    if (c.phase == VoicePhase.listening && c.caption.isNotEmpty) h.live = c.caption;
    await tick(t);
  }
  if (sayError != null) await log('  [harness] /say failed: $sayError');
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
    await log('  mic was already closed before stop (phase ${c.phase})');
  }
  final got = await waitForTurn(t, before);
  h.said = c.caption;
  h.reply = c.mascotLine;
  h.confirming = c.confirming;
  h.notice = c.notice;
  if (!got && identical(c.turn, before)) h.error ??= 'no new turn from the server';
  return h;
}

/// Taps Yes on a read-back and waits for the next question.
Future<bool> tapYes(WidgetTester t) async {
  final c = ctl(t);
  final before = c.turn;
  if (!await tapButton(t, 'Yes')) return false;
  return waitForTurn(t, before);
}

/// Moves on after a failed step: accepts a read-back, or skips the question.
Future<void> recover(WidgetTester t) async {
  final c = ctl(t);
  await waitUntil(t, () => c.phase != VoicePhase.interpreting && c.phase != VoicePhase.listening, seconds: 30);
  if (c.confirming && c.correcting) {
    await tapButton(t, 'Never mind', seconds: 3);
    await t.pump();
  }
  if (c.confirming) {
    await log('  recover: tapping Yes on "${oneLine(c.mascotLine)}"');
    await tapYes(t);
  } else if (c.phase != VoicePhase.done) {
    await log('  recover: skipping ${fieldOf(c)}');
    final before = c.turn;
    unawaited(c.skip());
    await waitForTurn(t, before);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'voice end to end: Mac speaks, phone hears, server reads back',
    timeout: const Timeout(Duration(minutes: 30)),
    (t) async {
      var pass = 0;
      var fail = 0;
      final results = <String>[];

      Future<void> record(String name, bool ok, String detail, [String why = '']) async {
        ok ? pass++ : fail++;
        final line = 'RESULT ${ok ? 'PASS' : 'FAIL'} [$name] $detail${why.isEmpty ? '' : ' why="$why"'}';
        results.add(line);
        await log(line);
      }

      try {
        await log('START harness=$harnessUrl');
        await t.pumpWidget(const LifeTwinApp());
        await tick(t);
        await tapButton(t, 'Talk');
        await tick(t);
        final c = ctl(t);
        // The AI question ignores taps for a moment, so a double tap can't answer it.
        final talked = await tapButton(t, "Yes, I'll talk");
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (!talked || !await tapButton(t, 'Not now')) {
          await log('could not get past consent; screen: ${screenText()}');
          fail++;
          return;
        }
        if (!await waitUntil(t, () => c.turn != null && c.phase != VoicePhase.interpreting, seconds: 40)) {
          await log('first question never came; notice=${c.notice}; screen: ${screenText()}');
          fail++;
          return;
        }
        await log('first question (${fieldOf(c)}): "${oneLine(c.mascotLine)}"');

        // ---- "what?" repeats the question, with no read-back ----
        {
          final h = await talk(t, 'what?');
          final ok =
              h.error == null &&
              !h.confirming &&
              fieldOf(c) == 'age' &&
              h.reply.contains('How old are you') &&
              !h.reply.contains("didn't understand");
          await record(
            'what? repeats question',
            ok,
            '$h',
            ok
                ? ''
                : h.error ??
                      (h.confirming
                          ? 'read-back shown'
                          : h.reply.contains("didn't understand")
                          ? 'treated as a failed answer, not a repeat request'
                          : !h.reply.contains('How old are you')
                          ? 'question not repeated'
                          : 'field moved to ${fieldOf(c)}'),
          );
          if (c.confirming) await recover(t);
        }

        // ---- age from a birth year, then a spoken correction during the read-back ----
        {
          final h = await talk(t, 'I was born in nineteen fifty two');
          final ok = h.error == null && h.confirming && (h.reply.contains('74') || h.reply.contains('73'));
          await record(
            'born 1952 -> 74/73',
            ok,
            '$h',
            ok ? '' : h.error ?? (h.confirming ? 'read-back lacks 74/73' : 'no read-back'),
          );
          if (c.confirming) {
            if (find.byType(TalkButton).evaluate().isEmpty) {
              await log('  note: the read-back screen has no Talk button; tapping "No, change it" to talk');
              await tapButton(t, 'No, change it');
              await waitUntil(t, () => find.byType(TalkButton).evaluate().isNotEmpty, seconds: 5);
            }
            final k = await talk(t, 'no, sixty');
            final ok2 = k.error == null && k.confirming && k.reply.contains('you are 60');
            await record(
              '"no, sixty" corrects read-back',
              ok2,
              '$k',
              ok2 ? '' : k.error ?? (k.confirming ? 'read-back lacks "you are 60"' : 'no read-back'),
            );
            if (c.confirming) {
              if (!await tapYes(t)) await recover(t);
            } else {
              await recover(t);
            }
          } else {
            await record('"no, sixty" corrects read-back', false, 'skipped', 'no age read-back to correct');
            await recover(t);
          }
        }

        // ---- the remaining questions, by voice ----
        const steps = [
          ('sex', 'female', ['female at birth']),
          ('height_cm', 'five foot four', ['5 feet 4 inches']),
          ('weight_kg', 'a hundred and forty five pounds', ['145 pounds']),
          ('sleep_hours', 'about seven hours', ['7 hours']),
          ('exercise_minutes_weekly', 'I walk thirty minutes five days a week', ['150 minutes']),
          ('smoking_status', 'I used to smoke but I quit years ago', ['smoked in the past']),
          ('alcohol_drinks_weekly', 'two glasses of wine a week', ['2 drinks']),
          ('diabetes', 'no', ['not told you that you have diabetes']),
          ('systolic_bp', 'one thirty over eighty five', ['130 over 85']),
        ];
        for (final (field, words, expects) in steps) {
          await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
          if (fieldOf(c) != field) {
            await log('  note: expected field $field but the app is on ${fieldOf(c)}');
          }
          final h = await talk(t, words);
          final missing = expects.where((e) => !h.reply.contains(e)).toList();
          final ok = h.error == null && h.confirming && missing.isEmpty;
          await record(
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

        // A skipped top blood-pressure number still asks for the bottom one: skip what is left.
        for (var i = 0; i < 3 && !await waitUntil(t, () => c.phase == VoicePhase.done, seconds: 5); i++) {
          await recover(t);
        }
        final finished = await waitUntil(t, () => c.phase == VoicePhase.done, seconds: 20);
        await log(
          'conversation ${finished ? 'finished' : 'NOT finished (phase ${c.phase})'}; '
          'confirmed=${jsonEncode(c.confirmedProfile)}',
        );
      } catch (e, s) {
        fail++;
        await log('EXCEPTION $e\n$s');
      } finally {
        await log('SUMMARY\n${results.join('\n')}');
        await log('VOICE-E2E DONE pass=$pass fail=$fail');
      }
    },
  );
}
