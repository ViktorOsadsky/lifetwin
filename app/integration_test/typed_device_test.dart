// End-to-end TYPED test on a real iPhone, no person needed: the whole intake by
// typing (real keyboard up, answer put in the box, Send tapped), the done screen,
// the fortune (ceremony, result, outlook), back to the Room, Apple Health opened
// and cancelled, and the Home, Settings, Hide keyboard, Skip and Go back controls.
//
// `flutter test` / `flutter drive` cannot attach to the phone, so this file is
// built as the app itself and posts its progress to the Mac's harness (/log):
//   flutter build ios --config-only --profile -t integration_test/typed_device_test.dart \
//     --dart-define=API_BASE_URL=http://<mac>:8000 --dart-define=VOICE_HARNESS_URL=http://<mac>:8099
//   (then xcodebuild, devicectl install, devicectl process launch)
//
// In a Profile build `tester.enterText` is ignored (the engine checks the input
// client id), so the test sets the box's text itself after tapping into it.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/forecast/forecast_screen.dart';
import 'package:lifesim/forecast/fortune_ceremony_screen.dart';
import 'package:lifesim/forecast/outlook_detail_screen.dart';
import 'package:lifesim/health/health_screen.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/voice/speech.dart';
import 'package:lifesim/ui/widgets/widgets.dart';

const harnessUrl = String.fromEnvironment('VOICE_HARNESS_URL', defaultValue: 'http://169.254.4.42:8099');

final _client = http.Client();

Future<void> log(String line) async {
  debugPrint('TYPED-E2E $line');
  try {
    await _client
        .post(
          Uri.parse('$harnessUrl/log'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'line': line}),
        )
        .timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('TYPED-E2E (log post failed: $e)');
  }
}

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

bool shows(Finder f) => f.evaluate().isNotEmpty;

VoiceOnboardingController ctl(WidgetTester t) =>
    t.widget<VoiceOnboardingScreen>(find.byType(VoiceOnboardingScreen)).controller;

String fieldOf(VoiceOnboardingController c) => '${c.turn?.state['current_field']}';

String oneLine(String s) => s.replaceAll('\n', ' ');

/// Every piece of text on screen (each Text builds a RichText).
String screenText() => find
    .byType(RichText)
    .evaluate()
    .map((e) => (e.widget as RichText).text.toPlainText())
    .where((s) => s.trim().isNotEmpty)
    .join(' | ');

double keyboardHeight(WidgetTester t) => t.view.viewInsets.bottom / t.view.devicePixelRatio;

Future<bool> tapFinder(WidgetTester t, Finder f, {int seconds = 20}) async {
  if (!await waitUntil(t, () => shows(f), seconds: seconds)) return false;
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first, warnIfMissed: false);
  await t.pump();
  return true;
}

Future<bool> tapButton(WidgetTester t, String label, {int seconds = 20}) =>
    tapFinder(t, find.widgetWithText(LipButton, label), seconds: seconds);

Future<bool> tapLink(WidgetTester t, String label, {int seconds = 20}) =>
    tapFinder(t, find.widgetWithText(LinkButton, label), seconds: seconds);

Finder roundButton(String label) => find.byWidgetPredicate((w) => w is RoundBackButton && w.label == label);

/// Waits for the server's next turn. Taps "Try again" after a rate limit, as a person would.
Future<bool> waitForTurn(WidgetTester t, GuideTurn? before, {int seconds = 60}) async {
  final c = ctl(t);
  final end = DateTime.now().add(Duration(seconds: seconds));
  var lastRetry = DateTime.now();
  while (DateTime.now().isBefore(end)) {
    if (!identical(c.turn, before) && c.phase != VoicePhase.interpreting) return true;
    if (c.phase != VoicePhase.interpreting && c.notice != null) {
      if (c.canRetry && DateTime.now().difference(lastRetry).inSeconds >= 12) {
        await log('  notice "${c.notice}" -> Try again');
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

/// Per-turn round trips on the phone (tap to reply on screen), for the summary.
final timings = <String>[];

class Reply {
  String typed = '';
  String reply = '';
  bool confirming = false;
  bool keyboardWasUp = false;
  int ms = -1;
  String? notice;
  String? error;

  @override
  String toString() =>
      'typed="$typed" reply="${oneLine(reply)}" ${ms}ms keyboard=${keyboardWasUp ? 'up' : 'DOWN'}'
      '${notice != null ? ' notice="$notice"' : ''}${error != null ? ' error="$error"' : ''}';
}

/// Taps into the box (the real keyboard comes up), puts [text] in it, taps Send, and
/// waits for LifeTwin's reply.
Future<Reply> type(WidgetTester t, String text) async {
  final c = ctl(t);
  final r = Reply()..typed = text;
  final box = find.byKey(const ValueKey('answer-field'));
  if (!await waitUntil(t, () => shows(box) && c.phase != VoicePhase.interpreting, seconds: 30)) {
    r.error = 'no typing box (phase ${c.phase}); screen: ${screenText()}';
    return r;
  }
  await t.ensureVisible(box);
  await t.pump();
  await t.tap(box, warnIfMissed: false);
  r.keyboardWasUp = await waitUntil(t, () => keyboardHeight(t) > 0, seconds: 3);
  await pumpFor(t, const Duration(milliseconds: 300));
  final field = t.widget<TextField>(box);
  field.controller!.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  await tick(t);
  if (field.controller!.text != text) {
    r.error = 'box holds "${field.controller!.text}" instead';
    return r;
  }
  final before = c.turn;
  final started = DateTime.now();
  if (!await tapFinder(t, find.byKey(const ValueKey('send')), seconds: 3)) {
    r.error = 'no Send button';
    return r;
  }
  await tick(t, 50);
  if (field.controller!.text.isNotEmpty && identical(c.turn, before) && c.phase != VoicePhase.interpreting) {
    r.error = 'Send was swallowed (box still "${field.controller!.text}")';
    return r;
  }
  final got = await waitForTurn(t, before);
  r.ms = DateTime.now().difference(started).inMilliseconds;
  r.reply = c.mascotLine;
  r.confirming = c.confirming;
  r.notice = c.notice;
  if (!got) r.error ??= 'no new turn from the server';
  timings.add('send "$text": ${r.ms} ms');
  return r;
}

/// Taps Yes (or another button) and waits for the next turn, timing it.
Future<(bool, int)> tapAndWait(WidgetTester t, String label, {bool link = false}) async {
  final c = ctl(t);
  final before = c.turn;
  final started = DateTime.now();
  if (!await (link ? tapLink(t, label) : tapButton(t, label))) return (false, -1);
  final ok = await waitForTurn(t, before);
  final ms = DateTime.now().difference(started).inMilliseconds;
  timings.add('tap "$label" (${fieldOf(c)} next): $ms ms');
  return (ok, ms);
}

/// Moves on after a failed step: accepts a read-back, or skips the question.
Future<void> recover(WidgetTester t) async {
  final c = ctl(t);
  await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
  if (c.confirming && c.correcting) {
    await tapButton(t, 'Never mind', seconds: 3);
    await t.pump();
  }
  if (c.confirming) {
    await log('  recover: tapping Yes on "${oneLine(c.mascotLine)}"');
    await tapAndWait(t, 'Yes');
  } else if (c.phase != VoicePhase.done) {
    await log('  recover: skipping ${fieldOf(c)}');
    final before = c.turn;
    unawaited(c.skip());
    await waitForTurn(t, before);
  }
}

/// Words a forecast must never show: a date, a year, a countdown, an age at death.
final _dateLike = [
  RegExp(r'\b(19|20)\d\d\b'),
  RegExp(r'\b(January|February|March|April|May|June|July|August|September|October|November|December)\b'),
  RegExp(r'\b\d{1,2}/\d{1,2}(/\d{2,4})?\b'),
  RegExp(r'life expectancy', caseSensitive: false),
  RegExp(r'\b(you will die|die at|death date|days left|years left)\b', caseSensitive: false),
  RegExp(r'\blive (to|until) \d+', caseSensitive: false),
];

List<String> dateProblems(String text) => [
  for (final r in _dateLike) ...r.allMatches(text).map((m) => m[0]!),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typed end to end on the phone', timeout: const Timeout(Duration(minutes: 20)), (t) async {
    var pass = 0;
    var fail = 0;
    final results = <String>[];

    Future<void> record(String name, bool ok, String detail, [String why = '']) async {
      ok ? pass++ : fail++;
      final line = 'RESULT ${ok ? 'PASS' : 'FAIL'} [$name] $detail${why.isEmpty ? '' : ' why="$why"'}';
      results.add(line);
      await log(line);
    }

    /// One question answered by typing, its read-back checked, then Yes.
    Future<void> answer(String field, String words, List<String> expects, {bool yes = true}) async {
      final c = ctl(t);
      await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
      if (fieldOf(c) != field) await log('  note: expected field $field but the app is on ${fieldOf(c)}');
      final r = await type(t, words);
      final missing = expects.where((e) => !r.reply.contains(e)).toList();
      final ok = r.error == null && r.confirming && missing.isEmpty;
      await record(
        '$field: "$words"',
        ok,
        '$r',
        ok ? '' : r.error ?? (r.confirming ? 'read-back lacks ${missing.join(', ')}' : 'no read-back'),
      );
      if (!yes) return;
      if (ok) {
        final (went, _) = await tapAndWait(t, 'Yes');
        if (!went) await recover(t);
      } else {
        await recover(t);
      }
    }

    try {
      await log('START harness=$harnessUrl');
      final launched = DateTime.now();
      await t.pumpWidget(const LifeTwinApp());
      await tick(t);

      // ---- Room -> Talk (swoosh) -> consent -> typing ----
      {
        final room = await waitUntil(t, () => shows(find.widgetWithText(LipButton, 'Talk')), seconds: 20);
        await log('room: ${screenText()}');
        await tapButton(t, 'Talk');
        await pumpFor(t, const Duration(milliseconds: 1000)); // the swoosh brings the conversation in
        final swooshed = shows(find.byType(VoiceOnboardingScreen));
        final c = ctl(t);
        final typed = await tapButton(t, "No, I'll type");
        await pumpFor(t, const Duration(milliseconds: 800)); // the AI question ignores taps for a moment
        final notNow = await tapButton(t, 'Not now');
        final first = await waitUntil(t, () => c.turn != null && c.phase != VoicePhase.interpreting, seconds: 40);
        final ms = DateTime.now().difference(launched).inMilliseconds;
        timings.add('launch to first question: $ms ms');
        final ok =
            room &&
            swooshed &&
            typed &&
            notNow &&
            first &&
            c.typing &&
            shows(find.byKey(const ValueKey('answer-field'))) &&
            c.mascotLine.contains('How old are you');
        await record(
          'Room -> Talk -> consent -> typing',
          ok,
          'first="${oneLine(c.mascotLine)}" typing=${c.typing} field=${fieldOf(c)} step="${shows(find.text('Question 1 of 11'))}"',
          ok
              ? ''
              : 'room=$room swoosh=$swooshed type=$typed notNow=$notNow first=$first; screen: ${screenText()}',
        );
        if (!first) return;
      }
      final c = ctl(t);

      // ---- Settings: opens, shows "Answer by: Type", Done closes it ----
      {
        final opened = await tapLink(t, 'Settings');
        await pumpFor(t, const Duration(milliseconds: 700));
        final sheet = shows(find.text('Answer by'));
        final seg = find.byWidgetPredicate((w) => w is SegmentedButton<bool>);
        final typeSelected = shows(seg) && t.widget<SegmentedButton<bool>>(seg).selected.contains(true);
        final aiRow = shows(find.text('AI helper'));
        await tapButton(t, 'Done', seconds: 3);
        await pumpFor(t, const Duration(milliseconds: 700));
        final closed = !shows(find.text('Answer by'));
        final ok = opened && sheet && typeSelected && aiRow && closed && c.typing;
        await record(
          'Settings sheet',
          ok,
          'opened=$opened answerBy=$sheet typeSelected=$typeSelected aiHelperRow=$aiRow closed=$closed',
          ok ? '' : 'screen: ${screenText()}',
        );
      }

      // ---- "Use my Apple Health" on the first question: open, then cancel ----
      {
        final before = c.turn;
        await pumpFor(t, const Duration(milliseconds: 800)); // the chip ignores taps right after a new turn
        final opened = await tapButton(t, 'Use my Apple Health', seconds: 3);
        final intro = await waitUntil(t, () => shows(find.text('Use Apple Health?')), seconds: 5);
        await log('  health intro: ${shows(find.byType(HealthImportScreen)) ? screenText() : '(not shown)'}');
        // Never "Yes, use Apple Health": that would bring up the real HealthKit sheet.
        final cancelled = await tapButton(t, "No thanks, I'll answer myself", seconds: 5);
        final back = await waitUntil(
          t,
          () => !shows(find.byType(HealthImportScreen)) && shows(find.byKey(const ValueKey('answer-field'))),
          seconds: 5,
        );
        await pumpFor(t, const Duration(milliseconds: 300));
        final ok = opened && intro && cancelled && back && identical(c.turn, before) && fieldOf(c) == 'age';
        await record(
          'Apple Health from Q1: open + cancel',
          ok,
          'intro=$intro cancelled=$cancelled backOnAge=${fieldOf(c) == 'age'} notice="${c.notice}"',
          ok ? '' : 'screen: ${screenText()}',
        );
      }

      // ---- Hide keyboard: the keyboard comes up in the box, the button puts it away ----
      {
        await t.tap(find.byKey(const ValueKey('answer-field')), warnIfMissed: false);
        final up = await waitUntil(t, () => keyboardHeight(t) > 0, seconds: 4);
        await pumpFor(t, const Duration(milliseconds: 400));
        final kb = keyboardHeight(t).round();
        final homeHidden = !shows(roundButton('Home'));
        final button = shows(find.widgetWithText(LipButton, 'Hide keyboard'));
        final sendVisible = shows(find.byKey(const ValueKey('send')));
        await tapButton(t, 'Hide keyboard', seconds: 2);
        final down = await waitUntil(t, () => keyboardHeight(t) == 0, seconds: 4);
        await pumpFor(t, const Duration(milliseconds: 400));
        final homeBack = shows(roundButton('Home'));
        final ok = up && button && down && homeBack;
        await record(
          'Hide keyboard',
          ok,
          'keyboardUp=$up (${kb}pt) hideButton=$button sendShown=$sendVisible homeHiddenWhileUp=$homeHidden '
              'keyboardDown=$down homeBack=$homeBack',
          ok ? '' : 'screen: ${screenText()}',
        );
      }

      // ---- age from a birth year, then a correction during the read-back ----
      {
        final r = await type(t, 'I was born in 1952');
        final ok = r.error == null && r.confirming && r.reply.contains('74');
        await record(
          'age: "I was born in 1952" -> 74/73',
          ok,
          '$r',
          ok ? '' : r.error ?? (r.confirming ? 'read-back lacks 74' : 'no read-back'),
        );
        if (c.confirming) {
          await tapButton(t, 'No, change it');
          final asked = await waitUntil(t, () => shows(find.text('Okay. What is the right answer?')), seconds: 5);
          final k = await type(t, "no, I'm 73");
          final ok2 = asked && k.error == null && k.confirming && k.reply.contains('you are 73');
          await record(
            'age correction: "No, change it" + "no, I\'m 73"',
            ok2,
            '$k',
            ok2 ? '' : k.error ?? (!asked ? 'no "right answer" prompt' : 'read-back lacks "you are 73"'),
          );
          if (c.confirming) {
            final (went, _) = await tapAndWait(t, 'Yes');
            if (!went) await recover(t);
          } else {
            await recover(t);
          }
        } else {
          await recover(t);
        }
      }

      await answer('sex', 'female', ['female at birth']);
      await answer('height_cm', 'five foot four', ['5 feet 4 inches']);
      await answer('weight_kg', 'a hundred and forty five pounds', ['145 pounds']);

      // ---- Home mid-intake: back to the Room, Talk again resumes the same question ----
      {
        await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
        final field = fieldOf(c);
        final line = c.mascotLine;
        final tapped = await tapFinder(t, roundButton('Home'), seconds: 5);
        final onRoom = await waitUntil(
          t,
          () => !shows(find.byType(VoiceOnboardingScreen)) && shows(find.widgetWithText(LipButton, 'Talk')),
          seconds: 5,
        );
        await pumpFor(t, const Duration(milliseconds: 800));
        await tapButton(t, 'Talk');
        await pumpFor(t, const Duration(milliseconds: 1000));
        final back = await waitUntil(t, () => shows(find.byType(VoiceOnboardingScreen)), seconds: 5);
        final noConsent = !shows(find.widgetWithText(LipButton, "No, I'll type"));
        final ok = tapped && onRoom && back && noConsent && fieldOf(c) == field && c.mascotLine == line && c.typing;
        await record(
          'Home mid-intake, then Talk resumes',
          ok,
          'field=$field -> ${fieldOf(c)} onRoom=$onRoom consentAgain=${!noConsent} line="${oneLine(c.mascotLine)}"',
          ok ? '' : 'screen: ${screenText()}',
        );
      }

      // ---- Skip, then Go back to the skipped question ----
      {
        await pumpFor(t, const Duration(milliseconds: 800)); // the links ignore taps right after a new turn
        final (skipped, skipMs) = await tapAndWait(t, 'Skip this question', link: true);
        final skipLine = c.mascotLine;
        final okSkip = skipped && fieldOf(c) == 'exercise_minutes_weekly' && skipLine.contains('skip');
        await record(
          'Skip (sleep)',
          okSkip,
          'reply="${oneLine(skipLine)}" ${skipMs}ms field=${fieldOf(c)}',
          okSkip ? '' : 'did not move to exercise',
        );
        await pumpFor(t, const Duration(milliseconds: 800));
        final (wentBack, backMs) = await tapAndWait(t, 'Go back', link: true);
        final okBack = wentBack && fieldOf(c) == 'sleep_hours' && c.mascotLine.contains('go back to your sleep');
        await record(
          'Go back (to skipped sleep)',
          okBack,
          'reply="${oneLine(c.mascotLine)}" ${backMs}ms field=${fieldOf(c)}',
          okBack ? '' : 'did not reopen sleep',
        );
      }

      await answer('sleep_hours', 'about seven hours', ['7 hours']);
      await answer('exercise_minutes_weekly', 'I walk thirty minutes five days a week', ['150 minutes']);
      await answer('smoking_status', 'I used to smoke but I quit years ago', ['smoked in the past']);
      await answer('alcohol_drinks_weekly', 'two glasses of wine a week', ['2 drinks']);
      await answer('diabetes', 'no', ['not told you that you have diabetes']);

      // ---- "I don't know" for blood pressure: skipped, and the intake ends ----
      {
        await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
        if (fieldOf(c) != 'systolic_bp') await log('  note: expected systolic_bp but the app is on ${fieldOf(c)}');
        final r = await type(t, "I don't know");
        final done = await waitUntil(t, () => c.phase == VoicePhase.done, seconds: 5);
        final ok = r.error == null && !r.confirming && done && r.reply.contains('skip');
        await record(
          'systolic_bp: "I don\'t know" -> skipped, done',
          ok,
          '$r phase=${c.phase} skipped=${c.turn?.state['skipped_fields']}',
          ok ? '' : r.error ?? 'not skipped or not done',
        );
      }

      // ---- done screen: Continue, Apple Health and Go back are there; Go back adds the BP ----
      {
        // Go back and Home stay hidden until the keyboard has gone down.
        await waitUntil(t, () => keyboardHeight(t) == 0, seconds: 3);
        await pumpFor(t, const Duration(milliseconds: 300));
        final done = c.phase == VoicePhase.done;
        final cont = shows(find.widgetWithText(LipButton, 'Continue'));
        final health = shows(find.widgetWithText(LipButton, 'Use my Apple Health'));
        final goBack = shows(find.widgetWithText(LinkButton, 'Go back'));
        final settingsHidden = !shows(find.widgetWithText(LinkButton, 'Settings'));
        await log('  done screen: ${screenText()}');
        final ok = done && cont && health && goBack;
        await record(
          'done screen',
          ok,
          'continue=$cont appleHealth=$health goBack=$goBack settingsHidden=$settingsHidden line="${oneLine(c.mascotLine)}"',
          ok ? '' : 'screen: ${screenText()}',
        );
        await pumpFor(t, const Duration(milliseconds: 800));
        final (wentBack, ms) = await tapAndWait(t, 'Go back', link: true);
        final okBack = wentBack && fieldOf(c) == 'systolic_bp' && c.mascotLine.contains('blood pressure');
        await record(
          'Go back from done (to skipped BP)',
          okBack,
          'reply="${oneLine(c.mascotLine)}" ${ms}ms field=${fieldOf(c)}',
          okBack ? '' : 'did not reopen blood pressure',
        );
        if (okBack) await answer('systolic_bp', '130 over 85', ['130 over 85']);
        final finished = await waitUntil(t, () => c.phase == VoicePhase.done, seconds: 20);
        await log(
          'conversation ${finished ? 'finished' : 'NOT finished (phase ${c.phase})'}; '
          'confirmed=${jsonEncode(c.confirmedProfile)}',
        );
        if (!finished) {
          for (var i = 0; i < 3 && c.phase != VoicePhase.done; i++) {
            await recover(t);
          }
        }
      }

      // ---- the fortune: Continue -> ceremony -> Ask the ball -> result ----
      var shownOutOf100 = -1;
      {
        await pumpFor(t, const Duration(milliseconds: 500));
        await tapButton(t, 'Continue', seconds: 5);
        final ceremony = await waitUntil(t, () => shows(find.byType(FortuneCeremonyScreen)), seconds: 5);
        await pumpFor(t, const Duration(milliseconds: 1200)); // taps while it slides in are ignored
        final ceremonyText = screenText();
        final peek = ceremonyText.contains('Want to peek ahead?');
        await record(
          'ceremony',
          ceremony && peek,
          'ceremony=$ceremony "Want to peek ahead?"=$peek',
          ceremony && peek ? '' : 'screen: $ceremonyText',
        );
        final asked = DateTime.now();
        await tapButton(t, 'Ask the ball', seconds: 5);
        final onForecast = await waitUntil(t, () => shows(find.byType(ForecastScreen)), seconds: 10);
        final settled = await waitUntil(
          t,
          () =>
              shows(find.text('Your look ahead')) ||
              shows(find.text('Still learning')) ||
              shows(find.widgetWithText(LipButton, 'Try again')) ||
              shows(find.widgetWithText(LipButton, 'Go back to my answers')),
          seconds: 40,
        );
        final ms = DateTime.now().difference(asked).inMilliseconds;
        timings.add('Ask the ball to result (incl. glow animation): $ms ms');
        await pumpFor(t, const Duration(milliseconds: 1500)); // the reveal fades in
        final text = screenText();
        await log('  forecast screen: $text');
        final supported = shows(find.text('Your look ahead'));
        final stillLearning = shows(find.text('Still learning'));
        final unsupported = text.contains("I can't make a forecast for you yet");
        final m = RegExp(r'About (\d+) in 100').firstMatch(text);
        shownOutOf100 = m == null ? -1 : int.parse(m[1]!);
        final years = RegExp(r'still here in (\d+) years?').firstMatch(text)?[1];
        final sentence = RegExp(r'about (\d+) were still living (\d+) years? later').firstMatch(text);
        final bears = find.byType(BearHeadArray);
        final bearFilled = shows(bears) ? t.widget<BearHeadArray>(bears).filled : -1;
        final problems = dateProblems(text);
        final consistent =
            !supported ||
            (shownOutOf100 >= 0 &&
                shownOutOf100 <= 100 &&
                sentence != null &&
                int.parse(sentence[1]!) == shownOutOf100 &&
                sentence[2] == years &&
                bearFilled == shownOutOf100);
        final ok = onForecast && settled && (supported || stillLearning || unsupported) && consistent && problems.isEmpty;
        await record(
          'forecast result',
          ok,
          'state=${supported ? 'supported' : stillLearning ? 'still learning' : unsupported ? 'unsupported' : 'other'} '
              'about=$shownOutOf100 in 100, years=$years, bears=$bearFilled, ${ms}ms, dates=${problems.isEmpty ? 'none' : problems}',
          ok ? '' : 'settled=$settled consistent=$consistent; screen: $text',
        );

        if (supported) {
          // Why?: the plain meaning lines.
          await tapLink(t, 'Why?', seconds: 3);
          final why = await waitUntil(t, () => shows(find.text('What this means')), seconds: 4);
          await pumpFor(t, const Duration(milliseconds: 800)); // the sheet slides up
          final whyText = screenText();
          final notADate = whyText.contains('not a promise, and they are not a date');
          final gotIt = find.widgetWithText(LipButton, 'Got it');
          final rect = shows(gotIt) ? t.getRect(gotIt) : null;
          await tapButton(t, 'Got it', seconds: 3);
          final closed = await waitUntil(t, () => !shows(find.text('What this means')), seconds: 3);
          final after = shows(gotIt) ? t.getRect(gotIt) : null;
          await record(
            'Why? sheet',
            why && notADate && closed && dateProblems(whyText).isEmpty,
            'shown=$why notADateLine=$notADate gotItCloses=$closed dates=${dateProblems(whyText)}',
            closed ? '' : 'Got it at $rect (after ensureVisible $after), screen ${t.view.physicalSize / t.view.devicePixelRatio}',
          );
          if (!closed) {
            await log('  closing the Why? sheet with Navigator.pop to go on');
            Navigator.of(t.element(find.text('What this means'))).pop();
            await pumpFor(t, const Duration(milliseconds: 600));
          }

          // The outlook: "See what shaped it".
          await tapButton(t, 'See what shaped it', seconds: 3);
          final outlook = await waitUntil(t, () => shows(find.byType(OutlookDetailScreen)), seconds: 5);
          await pumpFor(t, const Duration(milliseconds: 800));
          // A lazy list: scroll to the end, gathering what each part shows.
          final seen = <String>{};
          final list = find.descendant(of: find.byType(OutlookDetailScreen), matching: find.byType(Scrollable)).first;
          for (var i = 0; i < 12; i++) {
            seen.addAll(screenText().split(' | '));
            if (seen.any((s) => s.startsWith('Model '))) break;
            await t.drag(list, const Offset(0, -300), warnIfMissed: false);
            await pumpFor(t, const Duration(milliseconds: 300));
          }
          final oText = seen.join(' | ');
          await log('  outlook: $oText');
          final built = oText.contains('Built from your answers');
          final limits = oText.contains('Not a promise, not a date');
          final oProblems = dateProblems(oText);
          final okO = outlook && built && limits && oProblems.isEmpty;
          await record(
            'outlook detail',
            okO,
            'built=$built limits=$limits assumed=${oText.contains('We assumed')} dates=${oProblems.isEmpty ? 'none' : oProblems}',
            okO ? '' : 'screen: $oText',
          );
          // Its back button scrolls with the list: back to the top first.
          for (var i = 0; i < 12 && !shows(roundButton('Back to your look ahead')); i++) {
            await t.drag(list, const Offset(0, 400), warnIfMissed: false);
            await pumpFor(t, const Duration(milliseconds: 300));
          }
          await tapFinder(t, roundButton('Back to your look ahead'), seconds: 3);
          await waitUntil(t, () => !shows(find.byType(OutlookDetailScreen)), seconds: 5);
          await pumpFor(t, const Duration(milliseconds: 500));
        } else {
          await record('Still learning / unsupported state', stillLearning || unsupported, 'screen: $text');
        }

        // ---- Back to the Room ----
        await tapFinder(t, roundButton('Back'), seconds: 3);
        final room = await waitUntil(
          t,
          () => !shows(find.byType(ForecastScreen)) && shows(find.byType(RoomScreen)) && shows(find.widgetWithText(LipButton, 'Talk')),
          seconds: 6,
        );
        await pumpFor(t, const Duration(milliseconds: 800));
        final roomText = screenText();
        final card = RegExp(r'about (\d+) in 100').firstMatch(roomText);
        final cardOk = !supported || (card != null && int.parse(card[1]!) == shownOutOf100);
        await record(
          'back to the Room',
          room && cardOk,
          'room=$room outlookCard="${card?[0]}" matches=$cardOk',
          room && cardOk ? '' : 'screen: $roomText',
        );
      }

      // ---- "Use my Apple Health" from the Room: open, then cancel ----
      {
        final pill = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Use my Apple Health');
        final there = await waitUntil(t, () => shows(pill), seconds: 3);
        if (there) {
          await t.ensureVisible(pill.first);
          await t.pump();
          await t.tap(pill.first, warnIfMissed: false);
        }
        final intro = await waitUntil(t, () => shows(find.text('Use Apple Health?')), seconds: 5);
        final cancelled = await tapButton(t, "No thanks, I'll answer myself", seconds: 5);
        final room = await waitUntil(
          t,
          () => !shows(find.byType(HealthImportScreen)) && shows(find.widgetWithText(LipButton, 'Talk')),
          seconds: 5,
        );
        final ok = there && intro && cancelled && room;
        await record(
          'Apple Health from the Room: open + cancel',
          ok,
          'pill=$there intro=$intro cancelled=$cancelled backOnRoom=$room',
          ok ? '' : 'screen: ${screenText()}',
        );
      }

      // ---- Talk again after that: the finished conversation, without a stale notice ----
      {
        await pumpFor(t, const Duration(milliseconds: 800));
        await tapButton(t, 'Talk', seconds: 5);
        await pumpFor(t, const Duration(milliseconds: 1200));
        final text = screenText();
        final open = shows(find.byType(VoiceOnboardingScreen));
        final done = open && ctl(t).phase == VoicePhase.done && shows(find.widgetWithText(LipButton, 'Continue'));
        final stale = text.contains("I'll keep asking you");
        await record(
          'Talk after the Room\'s Apple Health cancel',
          done && !stale,
          'done=$done keepAskingNotice=$stale notice="${open ? ctl(t).notice : '-'}"',
          done && !stale ? '' : 'screen: $text',
        );
        await tapFinder(t, roundButton('Home'), seconds: 3);
        await pumpFor(t, const Duration(milliseconds: 800));
      }
    } catch (e, s) {
      fail++;
      await log('EXCEPTION $e\n$s');
    } finally {
      await log('TIMINGS\n${timings.join('\n')}');
      await log('SUMMARY\n${results.join('\n')}');
      await log('TYPED-E2E DONE pass=$pass fail=$fail');
    }
  });
}
