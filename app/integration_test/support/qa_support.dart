// Shared helpers for the qa_* integration tests. They run against the real server
// through support/qa_proxy.py, which the tests switch into fault modes:
//   python3 integration_test/support/qa_proxy.py 8051 http://127.0.0.1:8050
//   flutter test integration_test/qa_network_test.dart -d <sim> \
//     --dart-define=API_BASE_URL=http://127.0.0.1:8051
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/ui/widgets/widgets.dart';

const qaProxy = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8051');

/// Switches the proxy into a fault mode (see qa_proxy.py).
Future<void> qaMode(String mode, {String path = '', int times = -1, double delay = 0}) async {
  final r = await http.get(Uri.parse('$qaProxy/__qa/mode?m=$mode&path=$path&times=$times&delay=$delay'));
  if (r.statusCode != 200) throw StateError('proxy mode failed: ${r.statusCode}');
}

Future<void> qaReset() async {
  final r = await http.get(Uri.parse('$qaProxy/__qa/reset'));
  if (r.statusCode != 200) throw StateError('proxy reset failed: ${r.statusCode}');
}

/// Onboarding actions the proxy forwarded (or faulted), in order.
Future<List<String>> qaTurnActions() async {
  final r = await http.get(Uri.parse('$qaProxy/__qa/log'));
  final log = (jsonDecode(r.body) as Map)['log'] as List;
  return [
    for (final e in log)
      if ((e as Map)['path'] == '/api/onboarding/turn') '${e['action']}',
  ];
}

Future<int> qaCount(String path) async {
  final r = await http.get(Uri.parse('$qaProxy/__qa/log'));
  return ((jsonDecode(r.body) as Map)['log'] as List).where((e) => (e as Map)['path'] == path).length;
}

/// Pumps frames until [finder] shows up. Pip animates forever, so pumpAndSettle never returns.
Future<void> waitFor(WidgetTester t, Finder finder, {int seconds = 30}) async {
  for (var i = 0; i < seconds * 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder. Screen: ${screenText()}');
}

/// Real time passes (network waits), frames keep coming.
Future<void> pumpFor(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await t.pump();
  }
}

/// Links that ignore taps for 0.7 s after a new question, so a double tap can't act twice.
const guardedLinks = {'Skip this question', 'Go back', 'Use my Health app'};

/// Taps that swoosh the conversation in from the Room (720 ms); its buttons move until then.
const swooshes = {'Talk', 'Go back to my answers'};

Future<void> tapText(WidgetTester t, String label, {int seconds = 30}) async {
  final f = find.text(label);
  await waitFor(t, f, seconds: seconds);
  if (guardedLinks.contains(label)) await pumpFor(t, const Duration(milliseconds: 750));
  await t.ensureVisible(f.first);
  await t.pump();
  await t.tap(f.first, warnIfMissed: false);
  await t.pump();
  if (swooshes.contains(label)) await pumpFor(t, const Duration(milliseconds: 1000));
}

/// Two taps on the same spot, 60 ms apart: a tremor or an impatient double tap.
/// A round window button by its spoken name ("Back", "Home"); it shows an icon, no words.
Finder roundButton(String label) => find.byWidgetPredicate((w) => w is RoundBackButton && w.label == label);

Future<void> tapRound(WidgetTester t, String label) async {
  final f = roundButton(label);
  await waitFor(t, f);
  await t.tap(f.first, warnIfMissed: false);
  await t.pump();
}

/// The fortune's ceremony comes first: its "Ask the ball" asks for the forecast.
Future<void> askTheBall(WidgetTester t) => tapText(t, 'Ask the ball');

/// From the Room: Fortune, then "Ask the ball".
Future<void> openFortune(WidgetTester t) async {
  await tapText(t, 'Fortune');
  await askTheBall(t);
}

Future<void> doubleTapText(WidgetTester t, String label, {Finder? finder}) async {
  final f = finder ?? find.text(label);
  await waitFor(t, f);
  await t.ensureVisible(f.first);
  await t.pump();
  final at = t.getCenter(f.first);
  await t.tapAt(at);
  await t.pump(const Duration(milliseconds: 60));
  await t.tapAt(at);
  await t.pump();
  if (swooshes.contains(label)) await pumpFor(t, const Duration(milliseconds: 1000));
}

String screenText() => find
    .byType(Text)
    .evaluate()
    .map((e) {
      final w = e.widget as Text;
      return w.data ?? w.textSpan?.toPlainText();
    })
    .whereType<String>()
    .where((s) => s.isNotEmpty)
    .join(' | ');

VoiceOnboardingController ctl(WidgetTester t) =>
    t.widget<VoiceOnboardingScreen>(find.byType(VoiceOnboardingScreen)).controller;

/// Waits until the controller is not waiting for the server.
Future<void> settled(WidgetTester t, {int seconds = 40}) async {
  final c = ctl(t);
  for (var i = 0; i < seconds * 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
    if (c.phase != VoicePhase.interpreting) return;
  }
  throw TestFailure('still waiting for the server. Screen: ${screenText()}');
}

/// Taps into the typing box (raising the keyboard, as a person would), types [text]
/// and taps Send once the keyboard has settled. Typing into a box that is not focused
/// is lost in the test harness after the keyboard was put away.
Future<void> typeAndSend(WidgetTester t, String text) async {
  await waitFor(t, find.byType(TextField));
  if (!(t.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus ?? false)) {
    await t.tap(find.byType(TextField));
    await pumpFor(t, const Duration(milliseconds: 700));
  }
  await t.enterText(find.byType(TextField), text);
  await pumpFor(t, const Duration(milliseconds: 300));
  await tapText(t, 'Send');
}

/// Types [answer], taps Send and waits for the mascot's words to contain [expect].
Future<void> say(WidgetTester t, String answer, String expect) async {
  await typeAndSend(t, answer);
  await waitFor(t, find.textContaining(expect));
  await settled(t);
}

Future<void> yes(WidgetTester t, String expectNext) async {
  await tapText(t, 'Yes');
  await waitFor(t, find.textContaining(expectNext));
  await settled(t);
}

/// The AI-helper question ignores taps for 0.7 s, so a double tap can't answer it.
Future<void> readQuestion(WidgetTester t) => pumpFor(t, const Duration(milliseconds: 800));

/// Opens the app, chooses typing, and waits for the first question.
Future<void> startTyped(WidgetTester t, {bool aiHelper = false, Widget? app}) async {
  await qaReset();
  await t.pumpWidget(app ?? const LifeTwinApp());
  await tapText(t, 'Talk');
  await tapText(t, "No, I'll type");
  await readQuestion(t);
  await tapText(t, aiHelper ? 'Yes, turn it on' : 'Not now');
  await waitFor(t, find.textContaining('How old are you?'));
  await settled(t);
}

/// Typed answers for a whole supported intake, each read back and confirmed.
const fullIntake = [
  ('71', 'you are 71', 'What sex'),
  ('female', 'female at birth', 'How tall'),
  ('5 foot 4', '5 feet 4 inches', 'How much do you weigh'),
  ('145 pounds', '145 pounds', 'How many hours'),
  ('7 hours', '7 hours', 'minutes do you exercise'),
  ('150 minutes', '150 minutes', 'Do you smoke'),
  ('never', 'never smoked', 'alcoholic drinks'),
  ('2 drinks', '2 drinks', 'diabetes'),
  ('no', 'not told you', 'blood pressure'),
  ('130 over 85', '130 over 85', 'All done'),
];

Future<void> answerAll(WidgetTester t, [List<(String, String, String)> steps = fullIntake]) async {
  for (final (answer, readBack, next) in steps) {
    await say(t, answer, readBack);
    await yes(t, next);
  }
  if (identical(steps, fullIntake)) await waitFor(t, find.text('Continue'));
}

/// Puts the keyboard away (with it up, progress and Settings are hidden to make room).
Future<void> hideKeyboard(WidgetTester t) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpFor(t, const Duration(milliseconds: 800));
}

/// Asks the shell watcher (support/qa_watch.sh, tailing this test's output) to act on the
/// simulator: `background` (Home, then back after 4 s), `settings` (screenshot the
/// Settings app, then back) or `shot <name>` (a screenshot). Then lets [wait] pass.
Future<void> qaAction(
  WidgetTester t,
  String verb, {
  String name = '',
  Duration wait = const Duration(seconds: 2),
}) async {
  debugPrint('QA-ACTION $verb $name');
  await pumpFor(t, wait);
}
