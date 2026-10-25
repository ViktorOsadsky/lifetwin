// The connected DEMO flow, end to end, with real widgets and the live server, starting from
// the demo seed (Rosa, 64, about two weeks of history; lib/demo/demo_seed.dart):
//   1. Home: the health score card above the outlook ("Healthier than … of 100"), and the
//      check-in entry.
//   2. The daily (quick) check-in, typed: ONE read-back at the end, then Looks right.
//   3. History: the new entry with its source.
//   4. The weekly check-in on demand (My data): mood "not great", the care reply once,
//      Stop for today, then Yes.
//   5. Experiment with your twin: one lever changed, a result.
//   6. My data -> AI and privacy: the training line naming the company when the server
//      reports `may_train_on_content: true`. Consent is never turned on.
//   7. The band pill: the recorded-demo flow saves a value with source wristband.
// A step whose screen is not on this branch is SKIP with the reason, never FAIL.
//
// Runs in the simulator or on a phone (as typed_device_test.dart):
//   flutter test integration_test/demo_flow_device_test.dart -d <device> \
//     --dart-define=API_BASE_URL=http://<mac>:8000 --dart-define=VOICE_HARNESS_URL=http://<mac>:8099
// Progress goes to the harness (/log) and to the console ("DEMO-E2E").
//
// The test keeps its data in memory (its own TwinRepository on a MemoryBackend, seeded the
// way the app seeds an empty store with DEMO_SEED=1), so it never reads or writes the
// owner's LifeTwin data. The test sets the answer box's text itself after tapping into it
// (in a Profile build `tester.enterText` is ignored).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_screen.dart';
import 'package:lifesim/demo/demo_seed.dart';
import 'package:lifesim/experiment/experiment_screen.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/widgets/widgets.dart';

const harnessUrl = String.fromEnvironment('VOICE_HARNESS_URL', defaultValue: 'http://127.0.0.1:8099');
const apiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

final _client = http.Client();

Future<void> log(String line) async {
  debugPrint('DEMO-E2E $line');
  try {
    await _client
        .post(
          Uri.parse('$harnessUrl/log'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'line': line}),
        )
        .timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('DEMO-E2E (log post failed: $e)');
  }
}

/// One real-time step. The Room animates for ever, so never pumpAndSettle.
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

String oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// Every piece of text on screen (each Text builds a RichText), whitespace collapsed.
String screenText() => oneLine(
  find
      .byType(RichText)
      .evaluate()
      .map((e) => (e.widget as RichText).text.toPlainText())
      .where((s) => s.trim().isNotEmpty)
      .join(' | '),
);

int occurrences(String needle) => RegExp(RegExp.escape(needle)).allMatches(screenText()).length;

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

Future<bool> tapText(WidgetTester t, String text, {int seconds = 20}) =>
    tapFinder(t, find.text(text), seconds: seconds);

Finder roundButton(String label) => find.byWidgetPredicate((w) => w is RoundBackButton && w.label == label);

Future<bool> back(WidgetTester t, String label) async {
  final ok = await tapFinder(t, roundButton(label), seconds: 5);
  await pumpFor(t, const Duration(milliseconds: 700));
  return ok;
}

CheckinController? checkin(WidgetTester t) {
  final f = find.byType(CheckInScreen);
  return shows(f) ? t.widget<CheckInScreen>(f).controller : null;
}

Future<bool> settled(WidgetTester t, CheckinController c, {int seconds = 40}) =>
    waitUntil(t, () => c.phase != CheckinPhase.interpreting && c.phase != CheckinPhase.notStarted, seconds: seconds);

/// Types [text] into the check-in box and sends it; returns the ms until the reply.
Future<int?> typeAnswer(WidgetTester t, CheckinController c, String text) async {
  if (!shows(find.byType(TextField)) && shows(find.bySemanticsLabel('Type instead'))) {
    await tapFinder(t, find.bySemanticsLabel('Type instead'), seconds: 2);
  }
  final box = find.descendant(of: find.byType(CheckInScreen), matching: find.byType(TextField));
  if (!await waitUntil(t, () => shows(box), seconds: 10)) return null;
  await t.ensureVisible(box);
  await t.tap(box, warnIfMissed: false);
  await pumpFor(t, const Duration(milliseconds: 300));
  final field = t.widget<TextField>(box);
  field.controller!.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  await tick(t);
  final before = c.turn;
  final started = DateTime.now();
  await tapFinder(t, find.byTooltip('Send'), seconds: 3);
  await waitUntil(t, () => !identical(c.turn, before) && c.phase != CheckinPhase.interpreting, seconds: 40);
  return DateTime.now().difference(started).inMilliseconds;
}

/// The words for a check-in question, by the field the server is asking about.
String answerFor(String? field) {
  final f = field ?? '';
  if (f.contains('sleep')) return 'about 7 hours';
  if (f.contains('vigorous')) return 'a brisk walk uphill for about 20 minutes';
  if (f.contains('moderate')) return 'an easy walk for about 30 minutes';
  if (f.contains('sedentary') || f.contains('sitting')) return 'about 6 hours';
  if (f.contains('wellbeing') || f.contains('feeling') || f.contains('mood')) return 'good';
  return "I don't know";
}

const careQuestion = 'Would you like to keep going with the check-in, or stop here for today?';
const safetyPhrase = 'hurting yourself, please call 911.';
final resultHeadline = RegExp(r'About \d+ more in 100|Less than 1 more in 100|About the same|About \d+ fewer in 100');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connected demo flow', timeout: const Timeout(Duration(minutes: 15)), (t) async {
    var pass = 0;
    var fail = 0;
    var skip = 0;
    final results = <String>[];
    final timings = <String>[];
    // Errors the app throws outside any await of the test (for example in a dispose): each
    // one is a FAIL of the step it happened in, and the walk goes on.
    final uncaught = <String>[];

    Future<void> record(String name, bool ok, String detail, [String why = '']) async {
      ok ? pass++ : fail++;
      final line = 'RESULT ${ok ? 'PASS' : 'FAIL'} [$name] $detail${why.isEmpty ? '' : ' why="$why"'}';
      results.add(line);
      await log(line);
    }

    Future<void> skipped(String name, String reason) async {
      skip++;
      final line = 'RESULT SKIP [$name] $reason';
      results.add(line);
      await log(line);
    }

    /// Runs one numbered step, timing it; an exception fails that step only.
    Future<void> step(String name, Future<void> Function() body) async {
      final started = DateTime.now();
      final errorsBefore = uncaught.length;
      try {
        await body();
      } catch (e, s) {
        await record(name, false, 'exception', '$e ${s.toString().split('\n').take(4).join(' / ')}');
      }
      for (final e in uncaught.sublist(errorsBefore)) {
        await record('$name: no uncaught app error', false, 'uncaught', e);
      }
      timings.add('$name: ${DateTime.now().difference(started).inMilliseconds} ms');
    }

    // The test's own store, in memory, seeded like the app does with DEMO_SEED=1.
    final repo = await openTwin(backend: MemoryBackend(), demo: true);
    final seededHistory = repo.history().length;
    final seededIds = {for (final e in repo.history()) e.id};
    // History entries this run added (whatever order history() lists them in).
    List<HistoryEntry> fresh() => [
      for (final e in repo.history())
        if (!seededIds.contains(e.id)) e,
    ];
    HistoryEntry? freshOf(String kind) => fresh().where((e) => e.kind == kind).firstOrNull;

    final walked = Completer<void>();
    runZonedGuarded(
      () async {
        try {
          await log('START harness=$harnessUrl api=$apiBase seededHistory=$seededHistory');
          await t.pumpWidget(LifeTwinApp(twin: Future.value(repo)));
          await tick(t);

          // ---- 1. Home ----
          await step('1 home', () async {
            final entry = await waitUntil(t, () => shows(find.widgetWithText(LipButton, 'Check in')), seconds: 30);
            await pumpFor(t, const Duration(milliseconds: 800));
            final text = screenText();
            await log('  room: $text');
            if (!text.contains('Healthier than') && !text.toLowerCase().contains('health score')) {
              await skipped(
                '1 home: health score card above the outlook',
                'on #65 (codex/c-ui-finish), not this branch',
              );
            } else {
              final score = text.indexOf('Healthier than');
              final outlook = text.indexOf(RegExp(r'Your \d+-yr look|Ask the ball'));
              await record(
                '1 home: health score card above the outlook',
                score >= 0 && (outlook < 0 || score < outlook),
                'scoreAt=$score outlookAt=$outlook',
              );
            }
            await record('1 home: check-in entry', entry, 'checkIn=$entry', entry ? '' : 'screen: $text');
          });

          // ---- 2. Daily (quick) check-in, typed ----
          await step('2 quick check-in', () async {
            final opened = await tapButton(t, 'Check in', seconds: 5);
            await pumpFor(t, const Duration(milliseconds: 900));
            final c = checkin(t);
            if (!opened || c == null) {
              await record('2 quick: open', false, 'opened=$opened', 'screen: ${screenText()}');
              return;
            }
            await settled(t, c);
            await log('  quick first: kind=${c.turn?.kind} field=${c.turn?.currentField} "${oneLine(c.mascotLine)}"');
            final asked = <String>[];
            var readbacks = 0; // each time the screen asked to confirm before the end
            var finalSeen = false;
            for (var i = 0; i < 10 && !(c.turn?.complete ?? false); i++) {
              if (c.finalReadback) {
                finalSeen = true;
                break;
              }
              if (c.confirming) {
                // A read-back before the end (or an unusual-value check): not the one-at-the-end design.
                readbacks++;
                await log('  quick mid read-back: field=${c.turn?.currentField} "${oneLine(c.mascotLine)}"');
                await tapButton(t, 'Yes', seconds: 3);
                await settled(t, c);
                continue;
              }
              final field = c.turn?.currentField;
              final words = answerFor(field);
              final ms = await typeAnswer(t, c, words);
              asked.add('$field="$words"');
              timings.add('  quick send "$words" ($field): ${ms ?? 'no box'} ms');
              if (ms == null) break;
            }
            final headers = find.text('Here’s what I heard').evaluate().length;
            final heard = screenText();
            final ok = finalSeen && readbacks == 0 && headers == 1;
            await record(
              '2 quick: typed answers, ONE read-back at the end',
              ok,
              'asked=${asked.join(', ')} midReadbacks=$readbacks finalReadback=$finalSeen headers=$headers',
              ok ? '' : 'screen: $heard',
            );
            if (!finalSeen) return;
            await log('  quick read-back: $heard');
            final started = DateTime.now();
            await tapButton(t, 'Looks right', seconds: 3);
            final done = await waitUntil(t, () => shows(find.text('All done')), seconds: 40);
            timings.add('  quick confirm: ${DateTime.now().difference(started).inMilliseconds} ms');
            final last = repo.store.checkins.isEmpty ? null : repo.store.checkins.last;
            final entry = freshOf(HistoryKind.quick);
            final saved = done && last?.kind == 'quick' && entry?.kind == HistoryKind.quick;
            await record(
              '2 quick: confirm saves',
              saved,
              'allDone=$done checkin=${last?.kind}/${last?.date} history=${entry?.kind}/${entry?.source} '
                  'items=${entry?.items.map((i) => '${i.field}=${i.value}(${i.source})').join(',')}',
              saved ? '' : 'screen: ${screenText()}',
            );

            // ---- 3. History ----
            await skipped('3 history screen: new entry with its source', 'on #65 (codex/c-ui-finish), not this branch');
            final sourceOk =
                entry != null &&
                entry.source == HistorySource.said &&
                entry.items.every((i) => i.source == HistorySource.said);
            await record(
              '3 history data: new entry with its source',
              sourceOk,
              'source=${entry?.source} label="${entry == null ? '-' : HistorySource.label(entry.source)}"',
            );

            await tapButton(t, 'Back to my room', seconds: 5);
            await pumpFor(t, const Duration(milliseconds: 900));
          });

          // ---- 4. Weekly check-in on demand: "not great", the care reply once, Stop for today ----
          await step('4 weekly check-in', () async {
            final myData = await tapText(t, 'My data & privacy', seconds: 10);
            await pumpFor(t, const Duration(milliseconds: 800));
            final row = await tapText(t, 'Weekly check-in', seconds: 5);
            await pumpFor(t, const Duration(milliseconds: 900));
            final c = checkin(t);
            if (!myData || !row || c == null) {
              await record('4 weekly: open on demand', false, 'myData=$myData row=$row', 'screen: ${screenText()}');
              return;
            }
            await settled(t, c);
            final kind = c.turn?.kind;
            await log('  weekly first: kind=$kind field=${c.turn?.currentField} "${oneLine(c.mascotLine)}"');
            final skippedFields = <String>[];
            for (var i = 0; i < 14 && c.turn?.currentField != 'wellbeing' && !(c.turn?.complete ?? false); i++) {
              final before = c.turn;
              if (c.confirming) {
                await tapButton(t, 'Yes', seconds: 3);
              } else {
                skippedFields.add('${c.turn?.currentField}');
                await tapFinder(
                  t,
                  find.descendant(of: find.byType(CheckInScreen), matching: find.text('Skip')),
                  seconds: 5,
                );
              }
              await waitUntil(t, () => !identical(c.turn, before) && c.phase != CheckinPhase.interpreting, seconds: 40);
            }
            final onMood = c.turn?.currentField == 'wellbeing';
            await record(
              '4 weekly: open on demand, reach the mood question',
              kind == 'weekly' && onMood,
              'kind=$kind skipped=${skippedFields.join(',')} mood="${oneLine(c.mascotLine)}"',
            );
            if (!onMood) return;

            final ms = await typeAnswer(t, c, 'not great');
            timings.add('  weekly send "not great": ${ms ?? 'no box'} ms');
            final open = await waitUntil(t, () => c.careQuestionOpen, seconds: 10);
            await pumpFor(t, const Duration(milliseconds: 500));
            final care = screenText();
            final safety = occurrences(safetyPhrase);
            final question = occurrences(careQuestion);
            final keep = shows(find.widgetWithText(LipButton, 'Keep going'));
            final stop = shows(find.widgetWithText(LipButton, 'Stop for today'));
            final no911Button = !shows(find.text('Call 911'));
            final careOk = open && safety == 1 && question == 1 && keep && stop && no911Button;
            await record(
              '4 weekly: "not great" -> the care reply once',
              careOk,
              'careOpen=$open safetyPhrase×$safety careQuestion×$question keepGoing=$keep stopForToday=$stop noCall911=$no911Button',
              careOk ? '' : 'screen: $care',
            );
            if (!stop) return;

            final beforeStop = c.turn;
            await tapButton(t, 'Stop for today', seconds: 3);
            await waitUntil(
              t,
              () => !identical(c.turn, beforeStop) && c.phase != CheckinPhase.interpreting,
              seconds: 40,
            );
            await pumpFor(t, const Duration(milliseconds: 400));
            final afterStop = oneLine(c.mascotLine);
            final repeated = occurrences(safetyPhrase);
            final yes = c.confirming && shows(find.widgetWithText(LipButton, 'Yes'));
            if (yes) await tapButton(t, 'Yes', seconds: 3);
            final done = await waitUntil(t, () => shows(find.text('Outlook updated')), seconds: 40);
            final last = repo.store.checkins.isEmpty ? null : repo.store.checkins.last;
            final mood = last?.answers['wellbeing'];
            final stopOk =
                repeated == 0 &&
                yes &&
                done &&
                last?.kind == 'weekly' &&
                mood == 'not_great' &&
                freshOf(HistoryKind.weekly)?.source == HistorySource.said;
            await record(
              '4 weekly: Stop for today, then Yes',
              stopOk,
              'afterStop="$afterStop" careRepeated×$repeated yesShown=$yes outlookUpdated=$done '
                  'checkin=${last?.kind} wellbeing=$mood history=${freshOf(HistoryKind.weekly)?.kind}/${freshOf(HistoryKind.weekly)?.source}',
              stopOk ? '' : 'screen: ${screenText()}',
            );
            await tapButton(t, 'Back to my room', seconds: 5);
            final snack = await waitUntil(
              t,
              () => shows(find.text('That’s okay. I saved what you told me.')),
              seconds: 4,
            );
            await record('4 weekly: saved notice after stopping', snack, 'snackBar=$snack');
        // The notice outlives the route; let it go before the next screen's dock is tapped.
        await waitUntil(t, () => !shows(find.byType(SnackBar)), seconds: 10);
            await pumpFor(t, const Duration(milliseconds: 900));
            await back(t, 'Back to settings');
          });

          // ---- 5. Experiment with your twin: change one lever ----
          await step('5 experiment', () async {
            final opened = await tapText(t, 'Try a change', seconds: 10);
            final hub = await waitUntil(t, () => shows(find.byType(ExperimentScreen)), seconds: 10);
            await pumpFor(t, const Duration(milliseconds: 900));
            final sleep = find.descendant(of: find.byType(ExperimentScreen), matching: find.text('Sleep'));
            final lever = hub && await tapFinder(t, sleep, seconds: 5);
            await pumpFor(t, const Duration(milliseconds: 900));
            final started = DateTime.now();
            final plus = await tapFinder(t, find.byIcon(Icons.add_rounded), seconds: 5);
            final shown = await waitUntil(t, () => resultHeadline.hasMatch(screenText()), seconds: 10);
            timings.add('  experiment result after +: ${DateTime.now().difference(started).inMilliseconds} ms');
            final detail = screenText();
            final used = await tapButton(t, 'Use in my what-if', seconds: 3);
            await pumpFor(t, const Duration(milliseconds: 900));
            final hubText = screenText();
            final ok =
                opened &&
                lever &&
                plus &&
                shown &&
                used &&
                resultHeadline.hasMatch(hubText) &&
                hubText.contains('1 change');
            await record(
              '5 experiment: one lever changed, a result',
              ok,
              'opened=$opened lever=$lever plus=$plus detail="${resultHeadline.firstMatch(detail)?.group(0)}" '
                  'hub="${resultHeadline.firstMatch(hubText)?.group(0)}" oneChange=${hubText.contains('1 change')}',
              ok ? '' : 'detail: $detail || hub: $hubText',
            );
            await back(t, 'Back to room');
          });

          // ---- 6. My data -> AI and privacy: the training line ----
          await step('6 AI privacy', () async {
            Map<String, dynamic>? p;
            for (final base in apiBase.split(',')) {
              try {
                final r = await _client
                    .get(Uri.parse('${base.trim()}/api/capabilities'))
                    .timeout(const Duration(seconds: 5));
                p = Map<String, dynamic>.from((jsonDecode(r.body) as Map)['personalize'] as Map);
                break;
              } catch (_) {}
            }
            final mayTrain = p?['may_train_on_content'] == true;
            final company = p?['company'];
            final consentBefore = repo.outsideAiConsent;
            final myData = await tapText(t, 'My data & privacy', seconds: 10);
            await pumpFor(t, const Duration(milliseconds: 800));
            final row = await tapText(t, 'AI and privacy', seconds: 5);
            final loaded = await waitUntil(t, () => shows(find.text('AI helper')), seconds: 15);
            await pumpFor(t, const Duration(milliseconds: 800));
            final text = screenText();
            const line = 'Meta may use what you share to improve its AI.';
            final shown = text.contains(line);
            final anyTraining = text.contains('may use what you share to improve its AI');
            final ok =
                myData &&
                row &&
                loaded &&
                (mayTrain ? shown && company == 'Meta' : !anyTraining) &&
                !repo.outsideAiConsent;
            await record(
              '6 AI privacy: training line names Meta (may_train_on_content=$mayTrain)',
              ok,
              'server company=$company mayTrain=$mayTrain lineShown=$shown consent=${repo.outsideAiConsent} (before $consentBefore)',
              ok ? '' : 'screen: $text',
            );
            await back(t, 'Back to my data');
            await back(t, 'Back to settings');
          });

          // ---- 7. The band pill: the recorded demo saves a value with source wristband ----
          await step('7 band', () async {
            int wristbandEntries() =>
                fresh().where((e) => e.items.any((i) => i.source == HistorySource.wristband)).length;
            final before = wristbandEntries();
            final pill = await tapText(t, 'Add band', seconds: 10);
            final find_ = await tapButton(t, 'Find my band', seconds: 5);
            final demo = await tapText(t, 'Try a recorded demo', seconds: 15);
            final panel = await waitUntil(t, () => shows(find.text('Recorded demo')), seconds: 10);
            await pumpFor(t, const Duration(milliseconds: 800));
            await log('  band panel: ${screenText()}');
            final suggestion = await tapButton(t, 'Mochi has a suggestion', seconds: 5);
            var saved = false;
            if (suggestion) {
              await tapButton(t, 'Use this', seconds: 5);
              await tapButton(t, 'Yes, save', seconds: 5);
              saved = await waitUntil(t, () => shows(find.textContaining('From your band')), seconds: 10);
            }
            final after = wristbandEntries();
            final ok = pill && find_ && demo && panel && suggestion && saved && after == before + 1;
            await record(
              '7 band: recorded demo saves a wristband value',
              ok,
              'pill=$pill find=$find_ recordedDemo=$demo panel=$panel suggestion=$suggestion saved=$saved '
                  'new wristband entries $before->$after',
              ok ? '' : 'screen: ${screenText()}',
            );
          });
        } catch (e, s) {
          fail++;
          await log('EXCEPTION $e\n$s');
        } finally {
          await log('TIMINGS\n${timings.join('\n')}');
          await log('SUMMARY\n${results.join('\n')}');
          await log('DEMO-E2E DONE pass=$pass fail=$fail skip=$skip');
          walked.complete();
        }
      },
      (e, s) {
        uncaught.add('$e ${s.toString().split('\n').take(6).join(' / ')}');
        debugPrint('DEMO-E2E UNCAUGHT $e');
      },
    );
    await walked.future;
    expect(fail, 0, reason: results.where((r) => r.startsWith('RESULT FAIL')).join('\n'));
  });
}
