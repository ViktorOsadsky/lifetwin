// The connected DEMO flow, end to end, with real widgets and the live server, starting from
// the demo seed (Rosa, 64, about two weeks of history; lib/demo/demo_seed.dart), at 390 x 844:
//   1. Home shows only Mochi, the compact score card (ring with a signed number, Higher risk /
//      Better health, "Healthier than X of 100", sparkline, the info icon to the drivers, the
//      "Your estimate" / "Around {year}" chip), ONE Check in, the "Today with Mochi" card, the
//      activity pill and the History, Settings and Add band icons; nothing scrolls.
//   2. The Today card: Why? and a source per row, the daily plan from the coach, and
//      "Not for me" on the workout revises the plan.
//   3. The quick check-in, typed: ONE read-back, Looks right, then the plan line and
//      "Here's today's plan".
//   4. The weekly check-in on demand (Settings): "not great", the care reply once, Stop, Yes.
//   5. History with sources; Health documents readings (BP, A1c); Mochi's notebook.
//   6. Every Settings hub row opens; AI and privacy names Meta, consent stays off.
//   7. The band: the recorded demo gives ONE "Demo data" suggestion, saved as wristband,
//      estimated; the copy says leg / Activity band, never wrist.
//   8. Experiment: one lever changed, a result.
//   9. Onboarding on a fresh store: the import control at question 1 (Not now collapses it to
//      a reachable icon), "Talk or type", the typed answers, save, the reveal with its caveat,
//      the reminder offer.
// The outside-AI consent ("Personal suggestions?") is always answered "No thanks".
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
import 'package:lifesim/band/band_screens.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/checkin/consent_screens.dart';
import 'package:lifesim/checkin/notebook_screen.dart';
import 'package:lifesim/experiment/room_pills.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifesim/wellness/daily_plan_screen.dart';
import 'package:lifesim/wellness/home_panel.dart';
import 'package:lifesim/wellness/today_card.dart';
import 'package:lifesim/wellness/widgets.dart' show WellnessCard;

import 'typed_device_test.dart' as typed;

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
  try {
    await t.ensureVisible(f.first);
    await t.pump();
  } catch (_) {}
  if (!shows(f)) return false;
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

/// The server's `personalize` capabilities.
Future<Map<String, dynamic>?> capabilities() async {
  try {
    final r = await _client
        .get(Uri.parse('${apiBase.split(',').first.trim()}/api/capabilities'))
        .timeout(const Duration(seconds: 5));
    return Map<String, dynamic>.from((jsonDecode(r.body) as Map)['personalize'] as Map);
  } catch (_) {
    return null;
  }
}

/// Text or rich text with exactly [s].
Finder txt(String s) => find.text(s, findRichText: true);

/// [f] inside a widget of type [T].
Finder inside<T>(Finder f) => find.descendant(of: find.byType(T), matching: f);

/// The top route's back button, whatever its label.
Future<bool> backAny(WidgetTester t) async {
  final ok = await tapFinder(t, find.byType(RoundBackButton), seconds: 5);
  await pumpFor(t, const Duration(milliseconds: 700));
  return ok;
}

/// Back to Home (the Room under every route): the UI's back buttons first, the navigator last.
Future<void> goHome(WidgetTester t) async {
  for (var i = 0; i < 5 && !shows(find.byType(HomeWellnessPanel)); i++) {
    if (!await backAny(t)) break;
  }
  if (!shows(find.byType(HomeWellnessPanel))) {
    t.state<NavigatorState>(find.byType(Navigator).first).popUntil((r) => r.isFirst);
    await pumpFor(t, const Duration(milliseconds: 900));
  }
}

/// The outside-AI consent ("Personal suggestions?") when the app asks it: always "No thanks".
Future<bool> declineConsentIfAsked(WidgetTester t, {int seconds = 8}) async {
  if (!await waitUntil(t, () => shows(find.byType(OutsideAiConsentScreen)), seconds: seconds)) return false;
  await pumpFor(t, const Duration(milliseconds: 600));
  await tapText(t, 'No thanks', seconds: 3);
  await waitUntil(t, () => !shows(find.byType(OutsideAiConsentScreen)), seconds: 5);
  await pumpFor(t, const Duration(milliseconds: 600));
  return true;
}

/// Settings (header icon), then [row].
Future<bool> openSettingsRow(WidgetTester t, String row) async {
  if (!shows(txt('Choices'))) {
    if (!await tapFinder(t, find.byTooltip('Settings'), seconds: 10)) return false;
    await pumpFor(t, const Duration(milliseconds: 800));
  }
  // The hub is a lazy list: bring the row into view first (down, then up).
  final target = txt(row);
  for (final delta in [200.0, -200.0]) {
    if (shows(target)) break;
    try {
      await t.scrollUntilVisible(target, delta, scrollable: find.byType(Scrollable).first, maxScrolls: 25);
    } catch (_) {}
  }
  final ok = await tapFinder(t, target, seconds: 5);
  await pumpFor(t, const Duration(milliseconds: 900));
  return ok;
}

/// Drags [scrollable] down step by step until [done] (or the end), calling [visit] at each stop.
Future<void> scrollThrough(WidgetTester t, Finder scrollable, bool Function() done, void Function() visit) async {
  for (var i = 0; i < 30; i++) {
    visit();
    if (done()) return;
    await t.drag(scrollable.first, const Offset(0, -250), warnIfMissed: false);
    await pumpFor(t, const Duration(milliseconds: 300));
  }
}

/// The Today card's rows (workout, food, habit, encouragement) by their icons.
const todayRows = {
  'workout': Icons.directions_walk_rounded,
  'food': Icons.restaurant_rounded,
  'habit': Icons.check_circle_outline_rounded,
  'encouragement': Icons.favorite_border_rounded,
};

String todayCardText() => oneLine(
  inside<TodayWithMochiCard>(find.byType(RichText))
      .evaluate()
      .map((e) => (e.widget as RichText).text.toPlainText())
      .where((s) => s.trim().isNotEmpty)
      .join(' | '),
);

// The health index (#126): about 1.0 for an average person, two decimals, may be above 2 or below 0.
final signedScore = RegExp(r'^[+\-−]?\d+\.\d\d$');
final aroundYear = RegExp(r'Around (20|21)\d\d');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('connected demo flow', timeout: const Timeout(Duration(minutes: 20)), (t) async {
    var pass = 0;
    var fail = 0;
    const skip = 0; // every step runs on main now
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

    // The phone size the demo is judged at: 390 x 844 points.
    const screen = Size(390, 844);
    final dpr = t.view.devicePixelRatio;
    t.view.physicalSize = screen * dpr;
    addTearDown(t.view.resetPhysicalSize);

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
          await log(
            'START harness=$harnessUrl api=$apiBase seededHistory=$seededHistory view=${screen.width}x${screen.height}',
          );
          await t.pumpWidget(LifeTwinApp(twin: Future.value(repo)));
          await tick(t);
          // What the server says when the app first asks (the app keeps the provider it got then).
          final capsAtLaunch = await capabilities();
          await log('  capabilities at launch: $capsAtLaunch');

          // ---- 1. Home: only the listed parts, fitting 390 x 844 ----
          await step('1 home', () async {
            final started = DateTime.now();
            final consentAsked = await declineConsentIfAsked(t, seconds: 20);
            final loaded = await waitUntil(
              t,
              () => shows(inside<TodayWithMochiCard>(find.textContaining('Today: '))),
              seconds: 40,
            );
            timings.add('  home: Today card loaded after ${DateTime.now().difference(started).inMilliseconds} ms');
            await pumpFor(t, const Duration(milliseconds: 800));
            final text = screenText();
            await log('  home: $text');

            final mochi = find.byKey(const ValueKey('room-twin'));
            final ring = find.byType(ScoreRing);
            final panelTexts = inside<HomeWellnessPanel>(find.byType(RichText))
                .evaluate()
                .map((e) => (e.widget as RichText).text.toPlainText().trim())
                .toList();
            final signed = panelTexts.firstWhere(signedScore.hasMatch, orElse: () => '');
            final higherBetter = shows(
              find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').contains('Higher is better')),
            );
            final labels = shows(find.textContaining('Higher risk')) && shows(find.textContaining('Better health'));
            final percentile = RegExp(r'Healthier than \d+ of 100 people your age').hasMatch(text);
            final spark = find.byType(ScoreSparkline);
            final info = find.byTooltip('What moves your score');
            final revealSeen = repo.lifespanRevealSeen;
            final chip = revealSeen ? find.textContaining(aroundYear) : txt('Your estimate');
            final checkIn = find.widgetWithText(LipButton, 'Check in');
            final checkIns = checkIn.evaluate().length;
            final otherCheckIn = shows(find.widgetWithText(LipButton, 'Weekly check-in'));
            final card = find.byType(TodayWithMochiCard);
            // The compact card (#127): "Today: workout · food · habit", the plan titles from the coach.
            final cardTitle = shows(inside<TodayWithMochiCard>(find.textContaining('Today: ')));
            final cardLine = todayCardText();
            final cardRect = shows(card) ? t.getRect(card.first) : Rect.zero;
            await log('  TODAY-CARD height=${cardRect.height.toStringAsFixed(1)} pt width=${cardRect.width.toStringAsFixed(1)} line="$cardLine"');
            final cardTitles = cardLine.split(' · ').length >= 3;
            final activity = find.byKey(const ValueKey('room-activity'));
            final activityIcon = shows(find.descendant(of: activity, matching: find.byType(Icon)));
            final header = {
              for (final tip in ['My history', 'Settings', 'Add band']) tip: find.byTooltip(tip),
            };
            final headerTopRight = header.values.every(
              (f) => shows(f) && t.getCenter(f.first).dx > screen.width / 2 && t.getCenter(f.first).dy < 160,
            );
            final pillTypes = {
              'RoomPill': find.byType(RoomPill),
              'BandPill': find.byType(BandPill),
              'StatusPill': find.byType(StatusPill),
              'ImportControl': find.byType(ImportControl),
            };
            final pills = [
              for (final e in pillTypes.entries)
                if (shows(e.value)) e.key,
              for (final s in ['Health', 'Apple Health', 'Upload', 'Upload a document', 'My data', 'My data & privacy'])
                if (shows(txt(s))) '"$s"',
            ];
            final parts = {
              'mochi': shows(mochi),
              'ring': shows(ring),
              'signed($signed)': signed.isNotEmpty,
              'higherIsBetter': higherBetter,
              'riskBetterLabels': labels,
              'percentile': percentile,
              'sparkline': shows(spark),
              'info': shows(info),
              'chip(${revealSeen ? 'Around' : 'Your estimate'})': shows(chip),
              'oneCheckIn($checkIns)': checkIns == 1 && !otherCheckIn,
              'todayCard': shows(card) && cardTitle && loaded && cardTitles,
              'activityPill+icon': shows(activity) && activityIcon,
              'headerTopRight': headerTopRight,
            };
            final missing = [
              for (final e in parts.entries)
                if (!e.value) e.key,
            ];
            final ok = missing.isEmpty && pills.isEmpty;
            await record(
              '1 home: only Mochi, score card, one Check in, Today card, activity pill, header icons',
              ok,
              'consentAsked=$consentAsked ${parts.entries.map((e) => '${e.key}=${e.value}').join(' ')} '
                  'otherPills=$pills alsoOnHome=[${[
                    for (final s in ['Exercise', 'Sleep', 'Customize', 'Talk', 'Quiz'])
                      if (shows(txt(s))) s,
                    if (RegExp(r'Still learning \d+').hasMatch(text)) RegExp(r'Still learning \d+').firstMatch(text)![0],
                  ].join(', ')}]',
              ok ? '' : 'missing=$missing screen: $text',
            );

            // Everything fits at 390 x 844 without scrolling.
            final view = Offset.zero & screen;
            final targets = <String, Finder>{
              'mochi': mochi,
              'ring': ring,
              'sparkline': spark,
              'info': info,
              'chip': chip,
              'checkIn': checkIn,
              'todayCard': card,
              'activity': activity,
              for (final e in header.entries) e.key: e.value,
            };
            final outside = <String>[];
            for (final e in targets.entries) {
              if (!shows(e.value)) {
                outside.add('${e.key}:absent');
                continue;
              }
              final r = t.getRect(e.value.first);
              if (r.left < -0.5 || r.top < -0.5 || r.right > view.right + 0.5 || r.bottom > view.bottom + 0.5) {
                outside.add('${e.key}:${r.toString().replaceAll('Rect.fromLTRB', '')}');
              }
            }
            final scrolls = <String>[];
            for (final e in find.byType(Scrollable).evaluate()) {
              final s = (e as StatefulElement).state as ScrollableState;
              if (s.axisDirection == AxisDirection.down &&
                  s.position.hasContentDimensions &&
                  s.position.maxScrollExtent > 0.5) {
                scrolls.add('maxScroll=${s.position.maxScrollExtent.toStringAsFixed(0)}');
              }
            }
            final fits = outside.isEmpty && scrolls.isEmpty;
            await record(
              '1 home: fits 390x844 without scrolling',
              fits,
              'outside=$outside verticalScroll=$scrolls',
              fits ? '' : 'card=${shows(card) ? t.getRect(card.first) : '-'}',
            );

            // The info icon opens the drivers sheet.
            final opened = await tapFinder(t, info, seconds: 3);
            final drivers = await waitUntil(t, () => shows(txt('What moves it')), seconds: 8);
            await pumpFor(t, const Duration(milliseconds: 600));
            final dText = screenText();
            final hasDriver = RegExp(
              'Linked with a higher modeled outlook|Linked with a lower modeled outlook|Little modeled difference|Not enough support to compare|We need a few more answers',
            ).hasMatch(dText);
            await backAny(t);
            final home = await waitUntil(t, () => shows(find.byType(HomeWellnessPanel)) && shows(info), seconds: 5);
            final dOk = opened && drivers && hasDriver && home;
            await record(
              '1 home: ⓘ opens the drivers sheet',
              dOk,
              'opened=$opened drivers=$drivers driverLine=$hasDriver backHome=$home',
              dOk ? '' : 'screen: $dText',
            );
          });

          // ---- 2. The Today card (compact, #127): a tap opens the plan; each item has why + source;
          //         skipping / "Not done" on the workout revises the plan ----
          await step('2 today plan', () async {
            // The card opens the daily plan from the coach. The outside-AI consent comes from this tap.
            final started = DateTime.now();
            final opened = await tapFinder(t, inside<TodayWithMochiCard>(find.textContaining('Today: ')), seconds: 3);
            final consentOnTap = await declineConsentIfAsked(t, seconds: 6);
            final screenUp = await waitUntil(t, () => shows(find.byType(DailyPlanScreen)), seconds: 8);
            final ready = await waitUntil(
              t,
              () => shows(txt('Awaiting professional review')) && !shows(find.bySemanticsLabel('Preparing your plan')),
              seconds: 40,
            );
            timings.add('  plan screen ready: ${DateTime.now().difference(started).inMilliseconds} ms');
            await pumpFor(t, const Duration(milliseconds: 600));
            final planText = screenText();
            // The plan is a lazy list: visit every item card on the way down. Per item: slot, title,
            // message, why, source (a link) and the review line.
            final perItem = <String, bool>{};
            final planScroll = inside<DailyPlanScreen>(find.byType(Scrollable));
            var whyPlan = false;
            await scrollThrough(t, planScroll, () => shows(find.textContaining('Habit ideas, not medical advice')), () {
              whyPlan = whyPlan || shows(txt('Why this plan?'));
              for (final e
                  in find
                      .ancestor(of: txt('Awaiting professional review'), matching: find.byType(WellnessCard))
                      .evaluate()) {
                final card = find.byElementPredicate((x) => x == e);
                final texts = find
                    .descendant(of: card, matching: find.byType(RichText))
                    .evaluate()
                    .map((x) => (x.widget as RichText).text.toPlainText().trim())
                    .where((x) => x.length > 1) // icons are one-glyph texts
                    .toList();
                final link = shows(find.descendant(of: card, matching: find.byIcon(Icons.open_in_new_rounded)));
                // slot, title, message, why, source title, review line
                if (texts.length >= 2) perItem[texts[1]] = texts.length >= 6 && link;
              }
            });
            final items = perItem.length;
            final sources = perItem.values.where((v) => v).length;
            final errors = RegExp(
              'The planner needs a moment|couldn’t connect|A lot is happening|Your plan has moved on',
            ).hasMatch(planText);
            // Each item carries its reason and a source link (they were Why? chips on the old Home card).
            final pOk = opened && screenUp && ready && items >= 3 && sources == items && !errors && whyPlan;
            await record(
              '2 today card opens the daily plan; each item has a reason and a source',
              pOk,
              'opened=$opened consentOnTap=$consentOnTap ready=$ready items=$items withWhyAndSource=$sources errors=$errors whyThisPlan=$whyPlan $perItem '
                  'general=${planText.contains('A general plan while Mochi gets to know you.')}',
              pOk ? '' : 'screen: $planText',
            );

            // Changing the workout: the coach revises the plan. The workout is the first item card.
            await t.drag(planScroll.first, const Offset(0, 4000), warnIfMissed: false);
            await pumpFor(t, const Duration(milliseconds: 600));
            String firstTitle() {
              final card = find.ancestor(of: txt('Awaiting professional review'), matching: find.byType(WellnessCard));
              if (!shows(card)) return '';
              final texts = find
                  .descendant(of: card.first, matching: find.byType(RichText))
                  .evaluate()
                  .map((x) => (x.widget as RichText).text.toPlainText().trim())
                  .where((x) => x.length > 1)
                  .toList();
              return texts.length > 2 ? '${texts[1]} / ${texts[2]}' : (texts.length > 1 ? texts[1] : '');
            }

            // Skip (the old thumbs-down), then "Not done" with a reason (the old "Not for me").
            for (final name in ['Skip', 'Not done']) {
              final before = firstTitle();
              final reviseStart = DateTime.now();
              final tapped = await tapFinder(
                t,
                inside<DailyPlanScreen>(find.widgetWithText(OutlinedButton, name)),
                seconds: 5,
              );
              var sent = tapped;
              if (name == 'Not done' && tapped) {
                sent =
                    await tapFinder(t, find.widgetWithText(ChoiceChip, 'No time'), seconds: 5) &&
                    await tapButton(t, 'Tell Mochi', seconds: 5);
              }
              final revised =
                  sent && await waitUntil(t, () => firstTitle() != before && firstTitle().isNotEmpty, seconds: 25);
              timings.add('  $name revision: ${DateTime.now().difference(reviseStart).inMilliseconds} ms');
              await pumpFor(t, const Duration(milliseconds: 500));
              await t.drag(planScroll.first, const Offset(0, 4000), warnIfMissed: false);
              await pumpFor(t, const Duration(milliseconds: 400));
              await record(
                '2 plan: "$name" on the workout gives a revised plan',
                tapped && revised,
                'tapped=$tapped sent=$sent before="$before" after="${firstTitle()}"',
                revised ? '' : 'workout unchanged',
              );
            }
            await goHome(t);
          });

          // ---- 3. Quick check-in: one read-back, confirm, then the plan line and "Here's today's plan" ----
          await step('3 quick check-in', () async {
            final opened = await tapButton(t, 'Check in', seconds: 5);
            await pumpFor(t, const Duration(milliseconds: 900));
            final c = checkin(t);
            if (!opened || c == null) {
              await record('3 quick: open', false, 'opened=$opened', 'screen: ${screenText()}');
              return;
            }
            await settled(t, c);
            final asked = <String>[];
            var readbacks = 0;
            var finalSeen = false;
            for (var i = 0; i < 10 && !(c.turn?.complete ?? false); i++) {
              if (c.finalReadback) {
                finalSeen = true;
                break;
              }
              if (c.confirming) {
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
            final ok = finalSeen && readbacks == 0 && headers == 1;
            await record(
              '3 quick: typed answers, ONE read-back at the end',
              ok,
              'asked=${asked.join(', ')} midReadbacks=$readbacks finalReadback=$finalSeen headers=$headers',
              ok ? '' : 'screen: ${screenText()}',
            );
            if (!finalSeen) return;
            final started = DateTime.now();
            await tapButton(t, 'Looks right', seconds: 3);
            final done = await waitUntil(t, () => shows(find.text('All done')), seconds: 40);
            timings.add('  quick confirm: ${DateTime.now().difference(started).inMilliseconds} ms');
            final last = repo.store.checkins.isEmpty ? null : repo.store.checkins.last;
            final entry = freshOf(HistoryKind.quick);
            final saved = done && last?.kind == 'quick' && entry?.kind == HistoryKind.quick;
            await record(
              '3 quick: confirm saves',
              saved,
              'allDone=$done checkin=${last?.kind}/${last?.date} history=${entry?.kind}/${entry?.source} '
                  'items=${entry?.items.map((i) => '${i.field}=${i.value}(${i.source})').join(',')}',
              saved ? '' : 'screen: ${screenText()}',
            );
            final planLine = await waitUntil(
              t,
              () =>
                  shows(find.textContaining('Mochi updated your plan')) ||
                  shows(find.textContaining('Your plan stays the same today')),
              seconds: 40,
            );
            timings.add('  quick plan line: ${DateTime.now().difference(started).inMilliseconds} ms');
            final which = shows(find.textContaining('Mochi updated your plan'))
                ? 'updated'
                : (planLine ? 'same' : 'none');
            final planButton = find.widgetWithText(LipButton, 'Here’s today’s plan');
            final hasButton = await waitUntil(t, () => shows(planButton), seconds: 5);
            final doneText = screenText();
            final tapped = hasButton && await tapFinder(t, planButton, seconds: 3);
            await declineConsentIfAsked(t, seconds: 6);
            final planUp = tapped && await waitUntil(t, () => shows(find.byType(DailyPlanScreen)), seconds: 8);
            final pOk = planLine && hasButton && planUp;
            await record(
              '3 quick: plan line, then "Here’s today’s plan"',
              pOk,
              'planLine=$which button=$hasButton opensPlan=$planUp',
              pOk ? '' : 'screen: $doneText',
            );
            await pumpFor(t, const Duration(milliseconds: 800));
            await goHome(t);
          });

          // ---- 4. Weekly check-in on demand (Settings): "not great", the care reply once, Stop, save ----
          await step('4 weekly check-in', () async {
            final row = await openSettingsRow(t, 'Weekly check-in');
            final c = checkin(t);
            if (!row || c == null) {
              await record('4 weekly: open on demand', false, 'row=$row', 'screen: ${screenText()}');
              return;
            }
            await settled(t, c);
            final kind = c.turn?.kind;
            final skippedFields = <String>[];
            for (var i = 0; i < 14 && c.turn?.currentField != 'wellbeing' && !(c.turn?.complete ?? false); i++) {
              final before = c.turn;
              if (c.confirming) {
                await tapButton(t, 'Yes', seconds: 3);
              } else {
                skippedFields.add('${c.turn?.currentField}');
                await tapFinder(t, inside<CheckInScreen>(find.text('Skip')), seconds: 5);
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
            final weekly = freshOf(HistoryKind.weekly);
            final stopOk =
                repeated == 0 &&
                yes &&
                done &&
                last?.kind == 'weekly' &&
                mood == 'not_great' &&
                weekly?.source == HistorySource.said;
            await record(
              '4 weekly: Stop for today, then Yes saves',
              stopOk,
              'afterStop="$afterStop" careRepeated×$repeated yesShown=$yes outlookUpdated=$done '
                  'checkin=${last?.kind} wellbeing=$mood history=${weekly?.kind}/${weekly?.source}',
              stopOk ? '' : 'screen: ${screenText()}',
            );
            await tapButton(t, 'Back to my room', seconds: 5);
            final snack = await waitUntil(
              t,
              () => shows(find.text('That’s okay. I saved what you told me.')),
              seconds: 4,
            );
            await record('4 weekly: saved notice after stopping', snack, 'snackBar=$snack');
            await waitUntil(t, () => !shows(find.byType(SnackBar)), seconds: 10);
            await goHome(t);
          });

          // ---- 5. History with sources, Health documents readings, Mochi's notebook ----
          await step('5 history, documents, notebook', () async {
            final opened = await tapFinder(t, find.byTooltip('My history'), seconds: 5);
            final up = await waitUntil(t, () => shows(txt('Your history')), seconds: 8);
            await pumpFor(t, const Duration(milliseconds: 900));
            final h = screenText();
            final quick = freshOf(HistoryKind.quick);
            final weekly = freshOf(HistoryKind.weekly);
            final saidCount = RegExp('You said').allMatches(h).length;
            final quickShown =
                quick != null && quick.items.isNotEmpty && quick.items.every((i) => i.source == HistorySource.said);
            final hOk =
                opened && up && quickShown && weekly != null && saidCount >= 2 && !h.contains('Source not recorded');
            await record(
              '5 history: new entries with sources',
              hOk,
              'opened=$up quick=${quick?.items.map((i) => '${i.field}(${i.source})').join(',')} weekly=${weekly?.source} '
                  '"You said"×$saidCount sourceNotRecorded=${h.contains('Source not recorded')}',
              hOk ? '' : 'screen: $h',
            );
            await goHome(t);

            final docs = await openSettingsRow(t, 'Health documents');
            final docsUp = await waitUntil(t, () => shows(txt('Readings')), seconds: 8);
            await pumpFor(t, const Duration(milliseconds: 600));
            final d = screenText();
            final bp = d.contains('Blood pressure') && d.contains('138/86 mmHg');
            final a1c = d.contains('A1c') && d.contains('5.8%');
            await record(
              '5 health documents: readings (BP, A1c)',
              docs && docsUp && bp && a1c,
              'row=$docs readings=$docsUp bp=$bp a1c=$a1c',
              bp && a1c ? '' : 'screen: $d',
            );
            await backAny(t);

            final nb = await openSettingsRow(t, 'Memory & notebook');
            final nbUp = await waitUntil(t, () => shows(txt('Mochi’s notebook')), seconds: 8);
            await pumpFor(t, const Duration(milliseconds: 600));
            final n = screenText();
            final notes =
                n.contains('walks the dog in the morning') && n.contains('sits a lot watching TV in the evening');
            await record(
              '5 notebook: shows the seed’s notes',
              nb && nbUp && notes,
              'row=$nb notebook=$nbUp seedNotes=$notes',
              notes ? '' : 'screen: $n',
            );
            // Forget ONE note: a per-note control (a delete/forget button or a swipe) on a note card.
            final perNote =
                shows(find.byType(Dismissible)) ||
                shows(inside<NotebookScreen>(find.byIcon(Icons.delete_outline_rounded))) ||
                shows(inside<NotebookScreen>(find.byIcon(Icons.close_rounded))) ||
                shows(inside<NotebookScreen>(find.textContaining(RegExp(r'^Forget( this)?( note)?$'))));
            await record(
              '5 notebook: can forget one note',
              perNote,
              'perNoteControl=$perNote notes=${repo.store.habitNotes.length}',
              perNote
                  ? ''
                  : 'no per-note forget; the only forget is the Memory switch, which clears all notes. screen: $n',
            );
            await goHome(t);
          });

          // ---- 6. Settings hub rows all open (AI privacy: the Meta line, consent stays off) ----
          await step('6 settings hub', () async {
            final p = capsAtLaunch;
            final now = await capabilities();
            await log('  capabilities now: $now');
            final mayTrain = p?['may_train_on_content'] == true;
            final company = p?['company'];
            // row -> what the opened screen shows
            final rows = <String, bool Function()>{
              'My data': () => shows(txt('Saved on this phone')),
              'Reminders': () =>
                  shows(find.byWidgetPredicate((w) => w is RoundBackButton && w.label == 'Back to settings')) &&
                  screenText().contains('Reminders'),
              'Personal suggestions': () => shows(txt('AI and privacy')) && shows(txt('AI helper')),
              'Change an answer': () => shows(txt('Update with Mochi')),
              'Weekly check-in': () => checkin(t)?.turn?.kind == 'weekly',
              'Apple Health': () => shows(txt('Use Apple Health?')),
              'Health documents': () => shows(txt('Health documents')) && shows(find.byType(RoundBackButton)),
              'Activity band': () => shows(txt('Find my band')) || shows(txt('Your band')),
            };
            final opened = <String>[];
            final notOpened = <String>[];
            for (final e in rows.entries) {
              final started = DateTime.now();
              final tapped = await openSettingsRow(t, e.key);
              final ok = tapped && await waitUntil(t, e.value, seconds: 12);
              timings.add('  settings "${e.key}": ${DateTime.now().difference(started).inMilliseconds} ms');
              (ok ? opened : notOpened).add(e.key);
              if (!ok) await log('  settings "${e.key}" did not open: ${screenText()}');
              if (e.key == 'Personal suggestions' && ok) {
                await pumpFor(t, const Duration(milliseconds: 800));
                final text = screenText();
                const line = 'Meta may use what you share to improve its AI.';
                final shown = text.contains(line);
                final anyTraining = text.contains('may use what you share to improve its AI');
                final switchOff = shows(
                  find.byWidgetPredicate(
                    (w) =>
                        w is Semantics &&
                        (w.properties.label ?? '').startsWith('Personal suggestions.') &&
                        w.properties.toggled == false,
                  ),
                );
                final aiOk =
                    (mayTrain ? shown && company == 'Meta' : !anyTraining) && !repo.outsideAiConsent && switchOff;
                await record(
                  '6 AI privacy: the Meta training line, consent stays off',
                  aiOk,
                  'server company=$company mayTrain=$mayTrain lineShown=$shown consent=${repo.outsideAiConsent} switchOff=$switchOff',
                  aiOk ? '' : 'screen: $text',
                );
              }
              if (e.key == 'Weekly check-in' && ok) {
                // Leave the check-in without answering.
                await pumpFor(t, const Duration(milliseconds: 600));
              }
              await goHome(t);
            }
            await record(
              '6 settings hub: every row opens',
              notOpened.isEmpty,
              'opened=[${opened.join(', ')}] notOpened=[${notOpened.join(', ')}]',
            );
          });

          // ---- 7. Band: the recorded demo gives ONE Demo data suggestion; it saves wristband, estimated ----
          await step('7 band', () async {
            int wristbandEntries() =>
                fresh().where((e) => e.items.any((i) => i.source == HistorySource.wristband)).length;
            final before = wristbandEntries();
            final copy = <String>[];
            final pill = await tapFinder(t, find.byTooltip('Add band'), seconds: 10);
            await pumpFor(t, const Duration(milliseconds: 700));
            copy.add(screenText());
            final find_ = await tapButton(t, 'Find my band', seconds: 5);
            final demo = await tapText(t, 'Try a recorded demo', seconds: 15);
            copy.add(screenText());
            final panel = await waitUntil(t, () => shows(find.text('Recorded demo')), seconds: 10);
            await pumpFor(t, const Duration(milliseconds: 800));
            copy.add(screenText());
            // The weekly number and Mochi's suggestion are on the Week tab.
            final week = await tapFinder(t, txt('Week'), seconds: 3);
            await pumpFor(t, const Duration(milliseconds: 800));
            final suggestButton = find.widgetWithText(LipButton, 'Mochi has a suggestion');
            try {
              await t.scrollUntilVisible(suggestButton, 200, scrollable: find.byType(Scrollable).first, maxScrolls: 15);
            } catch (_) {}
            copy.add(screenText());
            await log('  band week: ${screenText()}');
            final suggestions = find.widgetWithText(LipButton, 'Mochi has a suggestion').evaluate().length;
            final suggestion = await tapButton(t, 'Mochi has a suggestion', seconds: 5);
            await pumpFor(t, const Duration(milliseconds: 700));
            final suggestText = screenText();
            copy.add(suggestText);
            final demoTag = suggestText.contains('Demo data');
            var saved = false;
            if (suggestion) {
              await tapButton(t, 'Use this', seconds: 5);
              await pumpFor(t, const Duration(milliseconds: 600));
              copy.add(screenText());
              await tapButton(t, 'Yes, save', seconds: 5);
              saved = await waitUntil(t, () => shows(find.text('Saved.')), seconds: 10);
              copy.add(screenText());
            }
            final after = wristbandEntries();
            final meta = repo.store.profileMeta['moderate_recreation_min_week'];
            final stored = meta?.source == HistorySource.wristband && meta?.estimated == true;
            final ok =
                pill &&
                find_ &&
                demo &&
                panel &&
                suggestions == 1 &&
                suggestion &&
                demoTag &&
                saved &&
                after == before + 1 &&
                stored;
            await record(
              '7 band: recorded demo gives ONE Demo data suggestion; saves wristband, estimated',
              ok,
              'pill=$pill find=$find_ recordedDemo=$demo panel=$panel week=$week suggestions=$suggestions demoTag=$demoTag saved=$saved '
                  'new wristband entries $before->$after meta=${meta?.source}/estimated=${meta?.estimated}',
              ok ? '' : 'suggest: $suggestText || screen: ${screenText()}',
            );
            // Back on the panel: the one-time demo suggestion is not offered again.
            await tapFinder(t, find.widgetWithText(LipButton, 'Close'), seconds: 3);
            await pumpFor(t, const Duration(milliseconds: 900));
            final again = shows(find.widgetWithText(LipButton, 'Mochi has a suggestion'));
            final panelAfter = screenText();
            copy.add(panelAfter);
            await record(
              '7 band: after saving, the suggestion is not offered again',
              !again,
              'suggestionAgain=$again profile=${repo.profile['moderate_recreation_min_week']}',
              again ? 'panel after Close: $panelAfter' : '',
            );
            final all = copy.join(' || ');
            final wrist = RegExp(r'wrist', caseSensitive: false).allMatches(all).map((m) => m[0]).toList();
            final leg = all.contains('leg') || all.contains('Activity band');
            await record(
              '7 band: copy says leg / Activity band, never wrist',
              wrist.isEmpty && leg,
              'wrist×${wrist.length} legOrActivityBand=$leg',
              wrist.isEmpty ? '' : 'copy: $all',
            );
            await goHome(t);
            // History lists it with its source and the estimate mark.
            await tapFinder(t, find.byTooltip('My history'), seconds: 5);
            await waitUntil(t, () => shows(txt('Your history')), seconds: 8);
            await pumpFor(t, const Duration(milliseconds: 800));
            final h = screenText();
            final shown = h.contains('Activity band · Estimated');
            await record(
              '7 band: History shows "Activity band · Estimated"',
              shown,
              'shown=$shown',
              shown ? '' : 'screen: $h',
            );
            await goHome(t);
          });

          // ---- 8. Experiment: change one lever, get a result ----
          await step('8 experiment', () async {
            final opened = await openSettingsRow(t, 'Try a change');
            final hub = await waitUntil(t, () => shows(find.byType(ExperimentScreen)), seconds: 10);
            await pumpFor(t, const Duration(milliseconds: 900));
            final lever = hub && await tapFinder(t, inside<ExperimentScreen>(find.text('Sleep')), seconds: 5);
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
              '8 experiment: one lever changed, a result',
              ok,
              'opened=$opened lever=$lever plus=$plus detail="${resultHeadline.firstMatch(detail)?.group(0)}" '
                  'hub="${resultHeadline.firstMatch(hubText)?.group(0)}" oneChange=${hubText.contains('1 change')}',
              ok ? '' : 'detail: $detail || hub: $hubText',
            );
            await goHome(t);
          });

          // ---- 9. Onboarding on a fresh store ----
          await step('9 onboarding', () async {
            // As the app opens it (reminders included, so the one-time offer can come), without the seed.
            final repo2 = await openTwin(
              backend: MemoryBackend(),
              demo: false,
              reminders: CheckinReminders(LocalNotificationPort()),
            );
            await t.pumpWidget(const SizedBox());
            await tick(t);
            await t.pumpWidget(LifeTwinApp(twin: Future.value(repo2)));
            await tick(t);
            final room = await waitUntil(t, () => shows(find.widgetWithText(LipButton, 'Talk')), seconds: 20);
            await tapButton(t, 'Talk');
            await pumpFor(t, const Duration(milliseconds: 1000));
            final typedOk = await tapButton(t, "No, I'll type");
            await pumpFor(t, const Duration(milliseconds: 800));
            await tapButton(t, 'Not now');
            final c = typed.ctl(t);
            final first = await waitUntil(t, () => c.turn != null && c.phase != VoicePhase.interpreting, seconds: 40);
            await pumpFor(t, const Duration(milliseconds: 600));
            final q1 = shows(find.text('Question 1 of 12'));
            final control = find.byType(ImportControl);
            final visible = shows(control) && !t.widget<ImportControl>(control).collapsed;
            final sheet =
                await tapFinder(t, control, seconds: 3) &&
                await waitUntil(
                  t,
                  () => shows(find.text('Mochi asks fewer questions when you add health data.')),
                  seconds: 5,
                );
            await pumpFor(t, const Duration(milliseconds: 800));
            final notNow = await tapFinder(
              t,
              find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(LipButton, 'Not now')),
              seconds: 3,
            );
            await pumpFor(t, const Duration(milliseconds: 800));
            final collapsed = shows(control) && t.widget<ImportControl>(control).collapsed;
            final collapsedRect = collapsed ? t.getRect(control.first) : Rect.zero;
            final reachable =
                collapsed &&
                await tapFinder(t, control, seconds: 3) &&
                await waitUntil(
                  t,
                  () => shows(find.text('Mochi asks fewer questions when you add health data.')),
                  seconds: 5,
                );
            await pumpFor(t, const Duration(milliseconds: 800));
            if (reachable) {
              await tapFinder(
                t,
                find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(LipButton, 'Not now')),
                seconds: 3,
              );
              await pumpFor(t, const Duration(milliseconds: 800));
            }
            final ctlOk = room && typedOk && first && q1 && visible && sheet && notNow && collapsed && reachable;
            await record(
              '9 onboarding: Q1 shows "Fill from Apple Health or a document"; Not now collapses it to a reachable icon',
              ctlOk,
              'q1=$q1 visible=$visible sheet=$sheet notNow=$notNow collapsed=$collapsed '
                  'icon=${collapsedRect.size.width.round()}x${collapsedRect.size.height.round()} reopens=$reachable',
              ctlOk ? '' : 'screen: ${screenText()}',
            );
            // "Talk or type": the opening button, with typing switched back to talking.
            // Talking needs its own yes ("Talk with me?"); typing comes back with "Type instead".
            final talk = await tapFinder(t, find.widgetWithText(LinkButton, 'Talk instead'), seconds: 3);
            await pumpFor(t, const Duration(milliseconds: 700));
            final talkYes = await tapButton(t, "Yes, I'll talk", seconds: 3);
            final talkOrType = await waitUntil(t, () => shows(find.text('Talk or type')), seconds: 5);
            final talkText = screenText();
            final backToTyping = await tapFinder(t, find.widgetWithText(LinkButton, 'Type instead'), seconds: 3);
            await pumpFor(t, const Duration(milliseconds: 700));
            if (shows(find.text('Talk with me?'))) await tapButton(t, 'Keep typing', seconds: 3);
            final typingAgain = await waitUntil(t, () => shows(find.byKey(const ValueKey('answer-field'))), seconds: 5);
            await record(
              '9 onboarding: "Talk or type" is there',
              talkOrType,
              'talkInstead=$talk yesTalk=$talkYes talkOrType=$talkOrType typeInstead=$backToTyping typingAgain=$typingAgain',
              talkOrType ? '' : 'screen: $talkText',
            );

            // The typed answers.
            String words(String field) => switch (field) {
              'age' => "I'm 64",
              'sex' => 'female',
              'smoking_status' => 'never',
              'height_cm' => 'five foot four',
              'weight_kg' => 'a hundred and forty five pounds',
              'sleep_hours' => 'about seven hours',
              'general_health' => 'good',
              'hypertension_diagnosed' => 'no',
              'diabetes' => 'no',
              'sedentary_min_day' => 'about six hours',
              'moderate_recreation_min_week' => 'I walk thirty minutes five days a week',
              'vigorous_recreation_min_week' => 'none',
              _ => 'Sure',
            };
            final started = DateTime.now();
            final answered = <String>[];
            for (var i = 0; i < 45 && c.phase != VoicePhase.done; i++) {
              await waitUntil(t, () => c.phase != VoicePhase.interpreting, seconds: 30);
              if (c.phase == VoicePhase.done) break;
              if (c.confirming) {
                await typed.tapAndWait(t, 'Yes');
                continue;
              }
              final phase = typed.serverPhase(c);
              final field = typed.fieldOf(c);
              final say = phase == 'offering' ? 'No thanks' : (phase == 'probing' ? "let's move on" : words(field));
              final r = await typed.type(t, say);
              answered.add('$field=${r.error ?? 'ok'}');
              if (r.error != null) await typed.recover(t);
            }
            final done = c.phase == VoicePhase.done;
            timings.add('  onboarding typed answers: ${DateTime.now().difference(started).inMilliseconds} ms');
            await pumpFor(t, const Duration(milliseconds: 800));
            final consentOverDone = shows(find.byType(OutsideAiConsentScreen));
            final doneText = screenText();
            await record(
              '9 onboarding: done screen after the typed answers (not covered)',
              done && !consentOverDone && shows(find.widgetWithText(LipButton, 'Continue')),
              'done=$done answers=${answered.length} consentScreenOverDone=$consentOverDone',
              done && !consentOverDone ? '' : 'answers=$answered screen: $doneText',
            );
            if (consentOverDone) await declineConsentIfAsked(t, seconds: 1);

            // Save, then the reveal, then the reminder offer.
            final cont = await tapButton(t, 'Continue', seconds: 5);
            final savedProfile = await waitUntil(t, () => repo2.store.hasProfile, seconds: 10);
            final peek = await waitUntil(t, () => shows(find.text('Want to peek ahead?')), seconds: 15);
            await pumpFor(t, const Duration(milliseconds: 2000)); // the ceremony settles before its button counts
            final ball = peek && await tapButton(t, 'Ask the ball', seconds: 5);
            final revealStart = DateTime.now();
            final reveal = await waitUntil(t, () => shows(find.textContaining(aroundYear)), seconds: 30);
            timings.add('  reveal: ${DateTime.now().difference(revealStart).inMilliseconds} ms');
            await pumpFor(t, const Duration(milliseconds: 900));
            final rText = screenText();
            final score = rText.contains('Health score') && RegExp(r'Healthier than \d+ of 100').hasMatch(rText);
            final age = RegExp(r'about age \d+, most likely \d+–\d+').hasMatch(rText);
            final caveatBtn = await tapFinder(t, find.byTooltip('About this estimate'), seconds: 3);
            final caveat = await waitUntil(
              t,
              () => shows(find.textContaining('Proof of concept: a rough estimate')),
              seconds: 4,
            );
            await tapFinder(t, find.descendant(of: find.byType(AlertDialog), matching: find.text('Close')), seconds: 3);
            await pumpFor(t, const Duration(milliseconds: 600));
            final rOk = cont && savedProfile && ball && reveal && score && age && caveatBtn && caveat;
            await record(
              '9 onboarding: save, then the reveal (score + "around {year}" with a caveat)',
              rOk,
              'continue=$cont saved=$savedProfile ball=$ball around="${aroundYear.firstMatch(rText)?.group(0)}" score=$score '
                  'ageRange=$age caveat=$caveat revealSeen=${repo2.lifespanRevealSeen}',
              rOk ? '' : 'screen: $rText',
            );
            final toRoom = await tapButton(t, 'Back to room', seconds: 5) || await backAny(t);
            final offer = await waitUntil(
              t,
              () => shows(find.textContaining('Would you like a gentle reminder each day?')),
              seconds: 10,
            );
            final offerButtons =
                shows(find.widgetWithText(LipButton, 'Not now')) && shows(find.widgetWithText(LipButton, 'Yes'));
            final offerText = screenText();
            if (offer) await tapButton(t, 'Not now', seconds: 3);
            await pumpFor(t, const Duration(milliseconds: 900));
            await declineConsentIfAsked(t, seconds: 5);
            final chip = await waitUntil(
              t,
              () => shows(find.textContaining(aroundYear)) && shows(find.byType(HomeWellnessPanel)),
              seconds: 10,
            );
            await record(
              '9 onboarding: then the reminder offer; Home chip says "Around {year}"',
              toRoom && offer && offerButtons && chip,
              'toRoom=$toRoom offer=$offer buttons=$offerButtons homeChip=$chip',
              offer ? '' : 'screen: $offerText',
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
