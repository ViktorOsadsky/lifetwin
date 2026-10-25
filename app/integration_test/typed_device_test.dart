// End-to-end TYPED test on a real iPhone, no person needed: the whole conversation v2
// by typing (real keyboard up, answer put in the box, Send tapped): the memory question,
// age, sex and smoking, the Apple Health offer (opened, cancelled, declined), the rest of
// the questions with "I don't know", Skip and Go back, the habit follow-ups, the done
// screen, the fortune (ceremony, result checked against the on-device model, outlook),
// back to the Room, the onboarding entry in History, Apple Health from the Room, and the
// Home, Settings and Hide keyboard controls.
//
// `flutter test` / `flutter drive` cannot attach to the phone, so this file is
// built as the app itself and posts its progress to the Mac's harness (/log):
//   flutter build ios --config-only --profile -t integration_test/typed_device_test.dart \
//     --dart-define=API_BASE_URL=http://<mac>:8000 --dart-define=VOICE_HARNESS_URL=http://<mac>:8099
//   (then xcodebuild, devicectl install, devicectl process launch)
//
// The test keeps its data in memory (its own TwinRepository on a MemoryBackend), so it
// never reads or writes the owner's LifeTwin data on the phone.
//
// In a Profile build `tester.enterText` is ignored (the engine checks the input
// client id), so the test sets the box's text itself after tapping into it.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;
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
import 'package:lifesim/twin/profile_mapping.dart';
import 'package:lifesim/twin/twin_model.dart' show extrapolationCaveat;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/voice/speech.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifetwin_on_device/lifetwin_on_device.dart';

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

/// The server's conversation phase: `remembering`, `asking`, `confirming`, `offering`,
/// `probing` (a habit follow-up) or `ready`.
String serverPhase(VoiceOnboardingController c) => '${c.turn?.state['phase']}';

List<String> listOf(VoiceOnboardingController c, String key) => [
  for (final f in (c.turn?.state[key] as List?) ?? const []) '$f',
];

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

/// Mochi's wording varies by a per-session seed, so a question is found by the words
/// every wording shares, in any case (as in typed_intake_test.dart).
RegExp words(String pattern) => RegExp(pattern, caseSensitive: false, dotAll: true);

const memoryQuestion = 'Can I remember the little things you tell me';
final ageQuestion = words('how old are you');
const healthOfferLine = 'Shall I fill in your height, weight, sleep and activity from Apple Health?';
final healthDeclined = words("i'll just ask you|we'll do it together");
final heightQuestion = words('how tall');

/// Puts the keyboard away with the screen's own button, as a person would: "Go back" and
/// Home are hidden while it is up.
Future<bool> hideKeyboard(WidgetTester t) async {
  if (keyboardHeight(t) > 0) await tapButton(t, 'Hide keyboard', seconds: 2);
  final down = await waitUntil(t, () => keyboardHeight(t) == 0, seconds: 4);
  await pumpFor(t, const Duration(milliseconds: 400));
  return down;
}

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
  String field = '';
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
  final r = Reply()
    ..typed = text
    ..field = fieldOf(c);
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
  timings.add('send "$text" (on ${r.field}): ${r.ms} ms');
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

/// The model's own disclaimer ("... not an individual death date or medical prognosis.")
/// denies a date; it is the one place those words may appear.
final _disclaimer = RegExp(r'\bnot an? (individual )?death date', caseSensitive: false);

List<String> dateProblems(String text) {
  final checked = text.replaceAll(_disclaimer, 'not an individual [disclaimer]');
  return [for (final r in _dateLike) ...r.allMatches(checked).map((m) => m[0]!)];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('typed end to end on the phone', timeout: const Timeout(Duration(minutes: 20)), (t) async {
    var pass = 0;
    var fail = 0;
    final results = <String>[];
    // The test's own store, in memory: the owner's data on the phone is never touched.
    final backend = MemoryBackend();
    final twin = TwinRepository.open(backend: backend);
    // "Question N of 11" when each question is first asked, in order.
    final steps = <String, int?>{};
    // The habit follow-ups Mochi asked (memory consent is yes), and what was typed.
    final followUps = <String>[];
    var sittingNote = false;

    Future<void> record(String name, bool ok, String detail, [String why = '']) async {
      ok ? pass++ : fail++;
      final line = 'RESULT ${ok ? 'PASS' : 'FAIL'} [$name] $detail${why.isEmpty ? '' : ' why="$why"'}';
      results.add(line);
      await log(line);
    }

    /// A habit follow-up (only with memory consent) after a confirmed answer: the sitting
    /// one is answered, so a habit note is kept; any other with "let's move on".
    Future<void> settleFollowUps() async {
      final c = ctl(t);
      for (var i = 0; i < 4; i++) {
        await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
        if (serverPhase(c) != 'probing') return;
        final asked = c.mascotLine;
        final sitting = !sittingNote && RegExp(r'\bsit', caseSensitive: false).hasMatch(asked);
        final words = sitting ? 'mostly TV and reading' : "let's move on";
        final r = await type(t, words);
        if (sitting) sittingNote = true;
        followUps.add('"${oneLine(asked)}" -> "$words"');
        final ok = r.error == null && !r.confirming && serverPhase(c) != 'probing' && fieldOf(c) != 'null';
        await record(
          'follow-up ${followUps.length}',
          ok,
          'asked="${oneLine(asked)}" $r next=${fieldOf(c)}',
          ok ? '' : r.error ?? 'did not move on to the next question',
        );
        if (!ok) return;
      }
    }

    /// Taps Yes on a read-back, then answers any habit follow-up.
    Future<void> yes() async {
      final (went, _) = await tapAndWait(t, 'Yes');
      if (!went) {
        await recover(t);
      } else {
        await settleFollowUps();
      }
    }

    /// One question answered by typing, its read-back checked, then Yes.
    Future<void> answer(String field, String words, List<String> expects, {bool yes_ = true}) async {
      final c = ctl(t);
      await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
      final onField = fieldOf(c) == field;
      steps.putIfAbsent(field, () => c.questionNumber);
      final r = await type(t, words);
      final missing = expects.where((e) => !r.reply.contains(e)).toList();
      final ok = onField && r.error == null && r.confirming && missing.isEmpty;
      await record(
        '$field: "$words"',
        ok,
        '$r',
        ok
            ? ''
            : !onField
            ? 'asked ${r.field}, not $field'
            : r.error ?? (r.confirming ? 'read-back lacks ${missing.join(', ')}' : 'no read-back'),
      );
      if (!yes_) return;
      if (r.confirming) {
        await yes();
      } else {
        await recover(t);
      }
    }

    try {
      await log('START harness=$harnessUrl');
      final launched = DateTime.now();
      await t.pumpWidget(LifeTwinApp(twin: twin));
      await tick(t);

      // ---- Room -> Talk (swoosh) -> consent -> typing -> the memory question ----
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
        timings.add('launch to first question (memory): $ms ms');
        final memory = c.mascotLine.contains(memoryQuestion);
        final noAgeYet = !ageQuestion.hasMatch(c.mascotLine);
        final ok =
            room &&
            swooshed &&
            typed &&
            notNow &&
            first &&
            c.typing &&
            shows(find.byKey(const ValueKey('answer-field'))) &&
            memory &&
            noAgeYet &&
            serverPhase(c) == 'remembering';
        await record(
          'Room -> Talk -> consent -> typing -> memory question',
          ok,
          'first="${oneLine(c.mascotLine)}" ${ms}ms typing=${c.typing} phase=${serverPhase(c)} '
              'step="${shows(find.text('Question 1 of 12'))}"',
          ok
              ? ''
              : 'room=$room swoosh=$swooshed type=$typed notNow=$notNow first=$first memory=$memory '
                    'noAgeYet=$noAgeYet; screen: ${screenText()}',
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

      // ---- The opening (3fc79e9): no Health button on the first question, one plain "Try saying" line;
      // Apple Health and documents are in the "Fill this in faster" pill, which waits for question 3 ----
      {
        await pumpFor(t, const Duration(milliseconds: 800));
        final text = screenText();
        final noButton = !shows(find.widgetWithText(LipButton, 'Use my Apple Health'));
        final noPill = !shows(find.byType(FasterPill));
        final trySaying = text.contains('Try saying');
        final onMemory = c.mascotLine.contains(memoryQuestion);
        final ok = noButton && noPill && trySaying && onMemory;
        await record(
          'Opening: no first-question Health button, pill waits',
          ok,
          'noHealthButton=$noButton noPillYet=$noPill trySaying=$trySaying onMemory=$onMemory',
          ok ? '' : 'screen: $text',
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

      // ---- memory consent, typed: "Sure" -> kept, then the age question ----
      {
        final r = await type(t, 'Sure');
        final consent = c.turn?.state['memory_consent'];
        final ok =
            r.error == null && !r.confirming && consent == true && fieldOf(c) == 'age' && ageQuestion.hasMatch(r.reply);
        await record(
          'memory: "Sure" -> consent, then age',
          ok,
          '$r memory_consent=$consent field=${fieldOf(c)}',
          ok ? '' : r.error ?? 'consent=$consent field=${fieldOf(c)}',
        );
        if (!ok) await recover(t);
      }

      // ---- age from a birth year, then a correction during the read-back ----
      {
        steps.putIfAbsent('age', () => c.questionNumber);
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
            await yes();
          } else {
            await recover(t);
          }
        } else {
          await recover(t);
        }
      }

      await answer('sex', 'female', ['female at birth']);
      await answer('smoking_status', 'I used to smoke but I quit years ago', ['smoked in the past']);

      // ---- the Apple Health offer: the button opens Health (cancelled), then "No thanks" ----
      {
        await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
        final offered = serverPhase(c) == 'offering' && c.mascotLine.contains(healthOfferLine) && c.healthOffer;
        final before = c.turn;
        await pumpFor(t, const Duration(milliseconds: 800)); // the button ignores taps right after a new turn
        final opened = await tapButton(t, 'Use my Apple Health', seconds: 3);
        final intro = await waitUntil(t, () => shows(find.text('Use Apple Health?')), seconds: 5);
        final cancelled = await tapButton(t, "No thanks, I'll answer myself", seconds: 5);
        final back = await waitUntil(
          t,
          () => !shows(find.byType(HealthImportScreen)) && shows(find.byKey(const ValueKey('answer-field'))),
          seconds: 5,
        );
        await pumpFor(t, const Duration(milliseconds: 300));
        final stillOffer = identical(c.turn, before) && c.mascotLine.contains(healthOfferLine);
        final okOffer = offered && opened && intro && cancelled && back && stillOffer;
        await record(
          'Apple Health offer: button opens Health, cancel returns to the offer',
          okOffer,
          'offered=$offered opened=$opened intro=$intro cancelled=$cancelled backOnOffer=$stillOffer '
              'notice="${c.notice}"',
          okOffer ? '' : 'line="${oneLine(c.mascotLine)}" phase=${serverPhase(c)}; screen: ${screenText()}',
        );
        final r = await type(t, 'No thanks');
        final ok =
            r.error == null &&
            !r.confirming &&
            healthDeclined.hasMatch(r.reply) &&
            heightQuestion.hasMatch(r.reply) &&
            fieldOf(c) == 'height_cm';
        await record(
          'Apple Health offer: "No thanks" -> height',
          ok,
          '$r field=${fieldOf(c)}',
          ok ? '' : r.error ?? 'not declined, or not on height',
        );
        if (!ok) await recover(t);
      }

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
        final okSkip =
            skipped &&
            fieldOf(c) == 'general_health' &&
            skipLine.contains('skip') &&
            listOf(c, 'skipped_fields').contains('sleep_hours');
        await record(
          'Skip (sleep)',
          okSkip,
          'reply="${oneLine(skipLine)}" ${skipMs}ms field=${fieldOf(c)} skipped=${listOf(c, 'skipped_fields')}',
          okSkip ? '' : 'did not move to general health',
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
      await answer('general_health', 'very good', ['your health is very good']);

      // ---- "I don't know" for high blood pressure: left out (still learning); Go back adds it ----
      {
        await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
        final onField = fieldOf(c) == 'hypertension_diagnosed';
        steps.putIfAbsent('hypertension_diagnosed', () => c.questionNumber);
        final r = await type(t, "I don't know");
        final unknown = listOf(c, 'unknown_fields');
        final ok =
            onField &&
            r.error == null &&
            !r.confirming &&
            r.reply.contains("Your twin will say it's still learning") &&
            unknown.contains('hypertension_diagnosed') &&
            fieldOf(c) == 'diabetes' &&
            c.turn?.modelInputs?['status'] != 'ready';
        await record(
          'hypertension_diagnosed: "I don\'t know" -> left out, still learning',
          ok,
          '$r unknown=$unknown field=${fieldOf(c)} model_inputs=${c.turn?.modelInputs?['status']}',
          ok ? '' : r.error ?? (onField ? 'not recorded as unknown' : 'asked ${r.field}, not hypertension_diagnosed'),
        );
        // Go back is hidden while the keyboard is up.
        await hideKeyboard(t);
        await pumpFor(t, const Duration(milliseconds: 800));
        final (wentBack, ms) = await tapAndWait(t, 'Go back', link: true);
        final okBack =
            wentBack && fieldOf(c) == 'hypertension_diagnosed' && c.mascotLine.contains('high blood pressure');
        await record(
          'Go back (to the unknown high blood pressure)',
          okBack,
          'reply="${oneLine(c.mascotLine)}" ${ms}ms field=${fieldOf(c)}',
          okBack ? '' : 'did not reopen high blood pressure',
        );
        if (okBack) {
          await answer('hypertension_diagnosed', 'no', ['not told you that you have high blood pressure']);
        } else {
          await recover(t);
        }
      }

      await answer('diabetes', 'no', ['not told you that you have diabetes']);
      await answer('sedentary_min_day', 'about six hours', ['sit about 6 hours']);
      await answer('moderate_recreation_min_week', 'I walk thirty minutes five days a week', [
        '150 minutes of lighter activity',
      ]);

      // ---- "I don't know" for harder exercise: Mochi asks a simpler question ----
      {
        await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
        final onField = fieldOf(c) == 'vigorous_recreation_min_week';
        steps.putIfAbsent('vigorous_recreation_min_week', () => c.questionNumber);
        final r = await type(t, "I don't know");
        final ok =
            onField &&
            r.error == null &&
            !r.confirming &&
            fieldOf(c) == 'vigorous_recreation_min_week' &&
            r.reply.contains('out of breath');
        await record(
          'vigorous_recreation_min_week: "I don\'t know" -> simpler question',
          ok,
          '$r field=${fieldOf(c)}',
          ok ? '' : r.error ?? (onField ? 'no simpler question' : 'asked ${r.field}, not vigorous'),
        );
        final k = await type(t, 'no');
        final ok2 = k.error == null && k.confirming && k.reply.contains('no harder exercise');
        await record(
          'vigorous_recreation_min_week: "no" to the simpler question',
          ok2,
          '$k',
          ok2 ? '' : k.error ?? (k.confirming ? 'read-back lacks "no harder exercise"' : 'no read-back'),
        );
        if (k.confirming) {
          await yes();
        } else {
          await recover(t);
        }
      }

      // ---- done screen: Continue, Apple Health and Go back; Go back + "keep it" ----
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
        final ok = done && cont && health && goBack && c.mascotLine.contains('All done');
        await record(
          'done screen',
          ok,
          'continue=$cont appleHealth=$health goBack=$goBack settingsHidden=$settingsHidden line="${oneLine(c.mascotLine)}"',
          ok ? '' : 'phase=${c.phase} screen: ${screenText()}',
        );
        await pumpFor(t, const Duration(milliseconds: 800));
        final (wentBack, ms) = await tapAndWait(t, 'Go back', link: true);
        final okBack =
            wentBack && fieldOf(c) == 'vigorous_recreation_min_week' && c.mascotLine.contains('say "keep it"');
        await record(
          'Go back from done (to harder exercise)',
          okBack,
          'reply="${oneLine(c.mascotLine)}" ${ms}ms field=${fieldOf(c)}',
          okBack ? '' : 'did not reopen harder exercise',
        );
        if (okBack) {
          final k = await type(t, 'keep it');
          final okKeep = k.error == null && c.phase == VoicePhase.done && k.reply.contains('kept your answer');
          await record('"keep it" -> done again', okKeep, '$k phase=${c.phase}', okKeep ? '' : k.error ?? 'not done');
        }
        final finished = await waitUntil(t, () => c.phase == VoicePhase.done, seconds: 20);
        await log(
          'conversation ${finished ? 'finished' : 'NOT finished (phase ${c.phase})'}; '
          'confirmed=${jsonEncode(c.confirmedProfile)} model_inputs=${jsonEncode(c.modelInputs)} '
          'unknown=${listOf(c, 'unknown_fields')} skipped=${listOf(c, 'skipped_fields')} '
          'estimated=${listOf(c, 'estimated_fields')}',
        );
        if (!finished) {
          for (var i = 0; i < 3 && c.phase != VoicePhase.done; i++) {
            await recover(t);
          }
        }
      }

      // ---- progress and follow-ups across the conversation ----
      {
        final numbers = [for (final n in steps.values) n ?? -1];
        final expected = [for (var i = 1; i <= numbers.length; i++) i];
        final ok = numbers.length == 12 && listEquals(numbers, expected);
        await record(
          'progress "Question N of ${VoiceOnboardingController.questionCount}" counts each question once',
          ok,
          'steps=$steps',
          ok ? '' : 'expected 1..12 in order',
        );
        final okF = followUps.isNotEmpty && followUps.length <= 3;
        await record('habit follow-ups (memory consent yes): 1 to 3', okF, 'followUps=$followUps');
      }

      // The answers the forecast is made from, before Continue drops the conversation.
      final confirmed = Map<String, dynamic>.from(c.confirmedProfile);
      final modelInputs = c.modelInputs == null ? null : Map<String, dynamic>.from(c.modelInputs!);

      // ---- the fortune: Continue -> ceremony -> Ask the ball -> result ----
      var shownOutOf100 = -1;
      var shownYears = 5;
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
        final m = RegExp(r'About (\d+) in 100').firstMatch(text);
        shownOutOf100 = m == null ? -1 : int.parse(m[1]!);
        final years = RegExp(r'still here in (\d+) years?').firstMatch(text)?[1];
        shownYears = int.tryParse(years ?? '') ?? 5;
        final sentence = RegExp(r'about (\d+) were still living (\d+) years? later').firstMatch(text);
        final bears = find.byType(BearHeadArray);
        final bearFilled = shows(bears) ? t.widget<BearHeadArray>(bears).filled : -1;
        final problems = dateProblems(text);
        // Every model input was answered, so the phone must show a number.
        final consistent =
            supported &&
            shownOutOf100 >= 0 &&
            shownOutOf100 <= 100 &&
            sentence != null &&
            int.parse(sentence[1]!) == shownOutOf100 &&
            sentence[2] == years &&
            bearFilled == shownOutOf100;
        final ok = onForecast && settled && consistent && problems.isEmpty && !text.contains(extrapolationCaveat);
        await record(
          'forecast result (a number)',
          ok,
          'state=${supported ? 'supported' : 'NOT supported'} about=$shownOutOf100 in 100, years=$years, '
              'bears=$bearFilled, ${ms}ms, dates=${problems.isEmpty ? 'none' : problems}',
          ok ? '' : 'settled=$settled consistent=$consistent; screen: $text',
        );

        // ---- the same profile through the on-device model, outside the app ----
        {
          final engine = LifeTwinEngine(await loadLifeTwinModel());
          final appMapped = toModelProfile(confirmed);
          final serverMapped = TwinRepository.readyModelProfile(modelInputs);
          final raw = engine.assess({'profile': appMapped});
          final survival = Map<String, dynamic>.from(raw['survival'] as Map);
          final probs = Map<String, dynamic>.from(survival['survival_probabilities'] as Map? ?? const {});
          final horizon = years ?? '5';
          final p = (probs[horizon] as num?)?.toDouble();
          final expected = p == null ? -1 : (100 * p).round();
          // The app reads the server's model_inputs when ready; it must agree with the
          // app's own mapping of the confirmed answers.
          final sameInputs =
              serverMapped != null &&
              serverMapped.entries.every((e) => appMapped[e.key] == e.value) &&
              appMapped.keys.toSet().containsAll(serverMapped.keys);
          final ok = survival['status'] == 'available' && expected == shownOutOf100 && sameInputs;
          await record(
            'forecast matches the on-device model for the same profile',
            ok,
            'shown=$shownOutOf100 model=$expected (p${horizon}y=${p?.toStringAsFixed(4)}) '
                'status=${survival['status']} version=${survival['model_version']} '
                'curve=${{for (final e in probs.entries) e.key: (e.value as num).toStringAsFixed(3)}} '
                'serverInputsAgree=$sameInputs',
            ok ? '' : 'appMapped=${jsonEncode(appMapped)} serverMapped=${jsonEncode(serverMapped)}',
          );
        }

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
            closed
                ? ''
                : 'Got it at $rect (after ensureVisible $after), screen ${t.view.physicalSize / t.view.devicePixelRatio}',
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
        }

        // ---- Back to the Room ----
        await tapFinder(t, roundButton('Back'), seconds: 3);
        final room = await waitUntil(
          t,
          () =>
              !shows(find.byType(ForecastScreen)) &&
              shows(find.byType(RoomScreen)) &&
              shows(find.widgetWithText(LipButton, 'Talk')),
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

      // ---- History: the onboarding entry, with every confirmed answer, and memory kept ----
      {
        final repo = await twin;
        await waitUntil(t, () => repo.history().any((e) => e.kind == HistoryKind.onboarding), seconds: 5);
        final entries = repo.history();
        final onboarding = entries.where((e) => e.kind == HistoryKind.onboarding).toList();
        final items = onboarding.isEmpty ? const <HistoryItem>[] : onboarding.first.items;
        final byField = {for (final i in items) i.field: i};
        const asked = [
          'age',
          'sex',
          'smoking_status',
          'height_cm',
          'weight_kg',
          'sleep_hours',
          'general_health',
          'hypertension_diagnosed',
          'diabetes',
          'sedentary_min_day',
          'moderate_recreation_min_week',
          'vigorous_recreation_min_week',
        ];
        final missing = [
          for (final f in asked)
            if (!byField.containsKey(f)) f,
        ];
        final wrong = [
          for (final f in asked)
            if (byField.containsKey(f) && byField[f]!.value != confirmed[f]) '$f=${byField[f]!.value}/${confirmed[f]}',
        ];
        final saidByYou = items.every((i) => i.source == HistorySource.said);
        final stored = repo.profile;
        final storedOk = asked.every((f) => stored[f] == confirmed[f]);
        final current = repo.current;
        final currentN = current == null || !current.available
            ? -1
            : (100 * (current.survivalByYear[shownYears] ?? -1)).round();
        final notesOk = !sittingNote || repo.store.habitNotes.any((n) => (n['note'] as Map?)?['topic'] == 'sitting');
        final ok =
            onboarding.length == 1 &&
            missing.isEmpty &&
            wrong.isEmpty &&
            saidByYou &&
            storedOk &&
            repo.store.memoryConsent &&
            notesOk &&
            currentN == shownOutOf100 &&
            backend.writes > 0;
        await record(
          'History: onboarding entry',
          ok,
          'entries=${entries.map((e) => e.kind).toList()} onboarding=${onboarding.length} items=${items.length} '
              '[${items.map((i) => '${i.label}: ${i.text}${i.estimated ? ' (${i.estimateText})' : ''}').join('; ')}] '
              'memoryConsent=${repo.store.memoryConsent} habitNotes=${repo.store.habitNotes.map((n) => (n['note'] as Map?)?['topic']).toList()} '
              'storedForecast=$currentN writes=${backend.writes}',
          ok
              ? ''
              : 'missing=$missing wrong=$wrong saidByYou=$saidByYou storedOk=$storedOk notesOk=$notesOk '
                    'storedForecast=$currentN shown=$shownOutOf100',
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
