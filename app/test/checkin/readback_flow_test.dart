import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/checkin/checkin_client.dart';
import 'package:lifesim/checkin/checkin_controller.dart';
import 'package:lifesim/checkin/checkin_models.dart';
import 'package:lifesim/checkin/checkin_screen.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/twin/twin_checkin_store.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';

import '../support/app_fonts.dart';
import 'daily_checkin_test.dart' show profile;

const questions = ['sleep_hours_last_night', 'sedentary_min_day'];

/// A server that follows the read-back contract (`app/lib/checkin/README.md`): answers are heard (`asking` +
/// `pending`), a very unusual value gets one gentle check (`confirming` + `checking`), and the one read-back
/// comes at the end (`confirming`, `current_field: null`). Within one answer the last number wins.
class ContractGuide implements CheckinGuide {
  ContractGuide({this.health = false});
  final bool health;
  final calls = <(String, String?)>[];
  int starts = 0;

  Map<String, dynamic> _raw(Map<String, dynamic> state, String message, {bool complete = false}) => {
    'message': message,
    'complete': complete,
    'emergency': false,
    'mascot_events': [
      {'state': 'asking', 'caption': message},
    ],
    'daily_logs': [
      if (complete)
        {
          'date': '2026-10-24',
          'sleep_hours': (state['confirmed'] as Map)['sleep_hours_last_night'],
          'vigorous_recreation_min': null,
          'moderate_recreation_min': null,
          'sedentary_min_day': (state['confirmed'] as Map)['sedentary_min_day'],
        },
    ],
    'profile_update': {},
    'state': state,
  };

  Map<String, dynamic> _state(
    String phase,
    String? field, {
    Map<String, dynamic> pending = const {},
    Map<String, dynamic> confirmed = const {},
    List<String> checking = const [],
    Map<String, dynamic> suggested = const {},
    bool fromHealth = false,
  }) => {
    'kind': 'quick',
    'phase': phase,
    'questions': questions,
    'current_field': field,
    'pending': pending,
    'confirmed': confirmed,
    'suggested': suggested,
    'from_health': fromHealth,
    'checking': checking,
    'skipped_fields': <String>[],
    'local_date': '2026-10-24',
    'activity_day': 'yesterday',
  };

  @override
  Future<CheckinTurn> start({
    required String kind,
    required String localDate,
    Map<String, dynamic> previous = const {},
    QuickPlan? quick,
  }) async {
    starts++;
    return CheckinTurn(
      health
          ? _raw(
              _state('asking', questions.first, suggested: {'sleep_hours_last_night': 7.5}, fromHealth: true),
              'Apple Health says you slept about 7.5 hours last night. Does that sound right?',
            )
          : _raw(_state('asking', questions.first), 'How did you sleep last night?'),
    );
  }

  static num _last(String text) =>
      num.parse(RegExp(r'\d+(\.\d+)?').allMatches(text).last.group(0)!); // "20, no wait 25" is 25

  @override
  Future<CheckinTurn> turn({
    required String action,
    required Map<String, dynamic> state,
    String? text,
    bool fromTranscript = false,
  }) async {
    calls.add((action, text));
    final pending = Map<String, dynamic>.from(state['pending'] as Map);
    final field = state['current_field'] as String?;
    // A clearly low answer gets one warm reply and "keep going or stop?" (not the emergency pause).
    if (action == 'reply' && text == 'awful' && state['care_line_shown'] != true) {
      return CheckinTurn(
        _raw(
          {..._state('asking', field, pending: pending), 'care_line_shown': true, 'care_question_open': true},
          'I’m sorry it’s been hard. If you’re ever thinking about hurting yourself, please call 911. Keep going, or stop here for today?',
        ),
      );
    }
    if (state['care_question_open'] == true && action == 'reply') {
      if (text == 'stop') {
        return CheckinTurn(
          _raw(_state('confirming', null, pending: pending), 'Before I save anything... Is that right?'),
        );
      }
      return _next(pending);
    }
    if (action == 'confirm' && state['phase'] == 'confirming' && field == null) {
      return CheckinTurn(_raw(_state('ready', null, confirmed: pending), 'All saved.', complete: true));
    }
    if (action == 'confirm' && state['phase'] == 'confirming') {
      // Yes to the check on an unusual value: it stays heard, and the questions go on.
      return _next(pending);
    }
    if (action == 'skip' && state['phase'] == 'confirming') {
      pending.remove(field);
      return _next(pending);
    }
    if (action == 'confirm') {
      pending[field!] = (state['suggested'] as Map)[field]; // Apple Health's value, heard
      return _next(pending);
    }
    if (field == null) {
      // "no, my sleep was 6 hours" at the read-back changes that answer.
      pending[questions.first] = _last(text!);
      return CheckinTurn(
        _raw(_state('confirming', null, pending: pending), 'Before I save anything... Is that right?'),
      );
    }
    pending[field] = field == 'sedentary_min_day' && text!.contains('hour') ? _last(text) * 60 : _last(text!);
    if (field == 'sleep_hours_last_night' && (pending[field] as num) > 14) {
      return CheckinTurn(
        _raw(
          _state('confirming', field, pending: pending, checking: [field]),
          'Did I hear ${pending[field]} hours of sleep? That\'s a lot for one night, so I just want to check. Is that right?',
        ),
      );
    }
    return _next(pending);
  }

  CheckinTurn _next(Map<String, dynamic> heard) {
    final next = questions.where((q) => !heard.containsKey(q)).firstOrNull;
    if (next == null) {
      return CheckinTurn(_raw(_state('confirming', null, pending: heard), 'Before I save anything... Is that right?'));
    }
    return CheckinTurn(_raw(_state('asking', next, pending: heard), 'Got it. About how many hours did you sit?'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  late TwinRepository repo;
  late ContractGuide guide;
  late FakeSpeechInput speech;

  Future<void> pumpScreen(WidgetTester t, {bool voice = false}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => DateTime(2026, 10, 24, 10),
    );
    await repo.saveConversationProfile(profile);
    speech = FakeSpeechInput();
    final controller = CheckinController(
      guide: guide,
      input: speech,
      output: FakeSpeechOutput(),
      store: TwinCheckinStore(repo),
      clock: () => DateTime(2026, 10, 24, 10),
      voiceUsable: voice,
    );
    addTearDown(controller.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: CheckInScreen(
          controller: controller,
          kind: CheckInKind.quick,
          repository: repo,
          appearance: const TwinAppearance(),
          onDone: () {},
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> typeAnswer(WidgetTester t, String text) async {
    await t.enterText(find.byType(TextField), text);
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pumpAndSettle();
  }

  testWidgets('one read-back for spoken, typed and tapped answers; nothing recorded before "Looks right"', (t) async {
    guide = ContractGuide();
    await pumpScreen(t, voice: true);
    expect(find.text('Tap to talk'), findsOneWidget);
    // Spoken.
    speech.transcript = 'about 7 hours';
    await t.tap(find.text('Tap to talk'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tap when done'));
    await t.pumpAndSettle();
    expect(find.text('Not quite'), findsNothing, reason: 'no read-back after one answer');
    expect(find.text('Yes'), findsNothing);
    expect(find.text('So far'), findsOneWidget);
    expect(find.text('7 hours a night'), findsOneWidget);
    // Tapped.
    await t.tap(find.text('About 6 hours'));
    await t.pumpAndSettle();
    expect(guide.calls.where((c) => c.$1 == 'confirm'), isEmpty, reason: 'the app never confirms for the person');
    // The one read-back lists every answer.
    expect(find.text('Here’s what I heard'), findsOneWidget);
    expect(find.text('7 hours a night'), findsOneWidget);
    expect(find.text('6 hours a day'), findsOneWidget);
    expect(find.text('Looks right'), findsOneWidget);
    expect(find.text('Change with Mochi'), findsOneWidget);
    expect(repo.store.checkins, isEmpty, reason: 'nothing is recorded before the yes');
    await t.tap(find.text('Looks right'));
    await t.pumpAndSettle();
    expect(repo.store.checkins, hasLength(1));
    expect(repo.store.checkins.single.answers, {'sleep_hours_last_night': 7, 'sedentary_min_day': 360});
    expect(guide.calls.where((c) => c.$1 == 'confirm'), hasLength(1));
  });

  testWidgets(
    'typed answers too; "Change with Mochi" sends "no, ..." and the new value shows; still nothing recorded',
    (t) async {
      guide = ContractGuide();
      await pumpScreen(t);
      await typeAnswer(t, '7 hours');
      await t.tap(find.text('About 8 hours'));
      await t.pumpAndSettle();
      expect(find.text('Here’s what I heard'), findsOneWidget);
      await t.tap(find.text('Change with Mochi'));
      await t.pumpAndSettle();
      expect(find.text('Keep it'), findsOneWidget);
      expect(find.text('Looks right'), findsNothing);
      await typeAnswer(t, 'my sleep was 6 hours');
      expect(guide.calls.last, ('reply', 'no, my sleep was 6 hours'));
      expect(find.text('6 hours a night'), findsOneWidget);
      expect(find.text('7 hours a night'), findsNothing);
      expect(repo.store.checkins, isEmpty);
      await t.tap(find.text('Looks right'));
      await t.pumpAndSettle();
      expect(repo.store.checkins.single.answers['sleep_hours_last_night'], 6);
    },
  );

  testWidgets('within one answer the last value wins: "20, no wait 25" shows 25', (t) async {
    guide = ContractGuide();
    await pumpScreen(t);
    await typeAnswer(t, '5 hours, no wait 6');
    expect(find.text('6 hours a night'), findsOneWidget);
    expect(find.text('5 hours a night'), findsNothing);
    await typeAnswer(t, 'about 9 hours, no wait 4 hours');
    expect(find.text('4 hours a day'), findsOneWidget);
    expect(find.text('9 hours a day'), findsNothing);
  });

  testWidgets('an unusual value gets one gentle check; Yes keeps it, and it is still read back once at the end', (
    t,
  ) async {
    guide = ContractGuide();
    await pumpScreen(t);
    await typeAnswer(t, '15 hours');
    expect(find.textContaining('That\'s a lot for one night'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('Not quite'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Looks right'), findsNothing, reason: 'this is a check, not the read-back');
    expect(repo.store.checkins, isEmpty);
    await t.tap(find.text('Yes'));
    await t.pumpAndSettle();
    await t.tap(find.text('About 6 hours'));
    await t.pumpAndSettle();
    expect(find.text('Here’s what I heard'), findsOneWidget);
    expect(find.text('15 hours a night'), findsOneWidget);
    await t.tap(find.text('Looks right'));
    await t.pumpAndSettle();
    expect(repo.store.checkins.single.answers['sleep_hours_last_night'], 15);
  });

  testWidgets('skipping the unusual value drops it', (t) async {
    guide = ContractGuide();
    await pumpScreen(t);
    await typeAnswer(t, '15 hours');
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    // Dropped: not heard, and not read back.
    expect(find.text('15 hours a night'), findsNothing);
    expect(find.text('So far'), findsNothing);
  });

  testWidgets("Apple Health's value is offered inside the question; Looks right is heard, not read back separately", (
    t,
  ) async {
    guide = ContractGuide(health: true);
    await pumpScreen(t);
    expect(find.textContaining('Apple Health says you slept about 7.5 hours'), findsOneWidget);
    expect(find.text('Looks right'), findsOneWidget);
    expect(find.text('Not quite'), findsOneWidget);
    await t.tap(find.text('Looks right'));
    await t.pumpAndSettle();
    expect(find.text('So far'), findsOneWidget);
    expect(find.text('7.5 hours a night'), findsOneWidget);
    expect(repo.store.checkins, isEmpty);
    await t.tap(find.text('About 6 hours'));
    await t.pumpAndSettle();
    expect(find.text('Here’s what I heard'), findsOneWidget);
    await t.tap(find.text('Looks right'));
    await t.pumpAndSettle();
    expect(repo.store.checkins, hasLength(1));
    expect(repo.store.checkins.single.answers['sleep_hours_last_night'], 7.5);
  });

  test('the start request carries the profile age, and only a valid one', () async {
    final bodies = <Map<String, dynamic>>[];
    http.Client fake() => MockClient((req) async {
      bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode({
          'message': 'Hi',
          'complete': false,
          'emergency': false,
          'mascot_events': [
            {'state': 'asking'},
          ],
          'state': {'kind': 'quick', 'phase': 'asking', 'questions': questions, 'current_field': questions.first},
        }),
        200,
      );
    });
    for (final (age, sent) in [(62, 62), (62.0, 62), (17, null), (null, null), ('x', null), (121, null)]) {
      bodies.clear();
      final c = HttpCheckinClient(client: fake(), base: ApiBase('http://x'), age: () => age);
      await c.start(kind: 'quick', localDate: '2026-10-24');
      expect(bodies.single['age'], sent, reason: '$age');
    }
  });
}
