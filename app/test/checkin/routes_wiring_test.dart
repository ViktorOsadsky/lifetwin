import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/experiment/recommendations.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/checkin/check_in_entry.dart';
import 'package:lifesim/checkin/checkin_screen.dart' show CheckInScreen;
import 'package:lifesim/checkin/consents.dart';
import 'package:lifesim/health/health_sample.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';

import '../support/app_fonts.dart';
import '../support/fake_change_client.dart';
import '../health_screen_test.dart' show FakeReader;
import 'daily_checkin_test.dart' show profile;
import 'readback_flow_test.dart' show ContractGuide;

class FakeCapabilities implements CapabilitiesClient {
  FakeCapabilities(this.provider);
  final AiProvider? provider;
  int calls = 0;
  @override
  Future<AiProvider?> personalize() async {
    calls++;
    return provider;
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
  late AgenticRoutes routes;
  late BuildContext home;
  var deleted = 0;

  Future<void> pump(WidgetTester t, {AiProvider? provider}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    deleted = 0;
    repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
    await repo.saveConversationProfile(profile);
    final look = ValueNotifier(const TwinAppearance(name: 'Mochi'));
    addTearDown(look.dispose);
    final voice = VoiceOnboardingController(
      guide: FakeConversationGuide(),
      input: FakeSpeechInput(),
      output: FakeSpeechOutput(),
    );
    addTearDown(voice.dispose);
    routes = AgenticRoutes(
      look: look,
      api: ApiBase(),
      voice: () => voice,
      guide: ContractGuide(),
      changeClient: FakeChangeClient(),
      capabilities: FakeCapabilities(provider),
      onDeleted: () => deleted++,
    )..attach(repo);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: routes.wrap,
        home: Builder(
          builder: (c) {
            home = c;
            return const Scaffold(body: Text('room'));
          },
        ),
      ),
    );
  }

  const meta = AiProvider(id: 'muse', displayName: 'Meta Muse', configured: true);

  testWidgets('My data opens from the Room pills; deleting wipes the phone, tells the shell and returns', (t) async {
    await pump(t);
    // The temporary pill is offered by the routes' pills.
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: routes.wrap,
        home: Builder(
          builder: (c) => Scaffold(body: Column(children: routes.pills(c))),
        ),
      ),
    );
    await t.tap(find.text('My data & privacy'));
    await t.pumpAndSettle();
    expect(find.text('My data'), findsWidgets);
    await t.tap(find.text('Delete my data'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete everything'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yes, delete'));
    await t.pumpAndSettle();
    expect(deleted, 1);
    expect(repo.store.hasProfile, isFalse);
    expect(find.text('My data'), findsNothing, reason: 'back at the first route');
  });

  testWidgets('reminders, AI and privacy, memory, change and weekly are all reachable', (t) async {
    await pump(t, provider: meta);
    routes.reminders(home);
    await t.pumpAndSettle();
    expect(find.textContaining('eminder'), findsWidgets);
    Navigator.of(home).pop();
    await t.pumpAndSettle();

    routes.aiPrivacy(home);
    await t.pumpAndSettle();
    expect(find.text('AI and privacy'), findsWidgets);
    expect(find.textContaining('Meta Muse'), findsWidgets);
    Navigator.of(home).pop();
    await t.pumpAndSettle();

    routes.memoryChoice(home);
    await t.pumpAndSettle();
    await t.tap(find.text('Yes, remember'));
    await t.pumpAndSettle();
    expect(repo.store.memoryConsent, isTrue);

    routes.changeAnswer(home);
    await t.pumpAndSettle();
    expect(find.textContaining('What would you like to update?'), findsWidgets);
    Navigator.of(home).pop();
    await t.pumpAndSettle();

    routes.weeklyCheckIn(home);
    await t.pumpAndSettle();
    expect(find.byType(CheckInScreen), findsOneWidget);
  });

  testWidgets('the outside-AI consent is asked once before first use, and never when no provider is set up', (t) async {
    await pump(t, provider: meta);
    final first = routes.ensureOutsideAiConsent(home);
    await t.pumpAndSettle();
    expect(find.text('Yes, share'), findsOneWidget);
    expect(find.text('No thanks'), findsOneWidget);
    await t.tap(find.text('Yes, share'));
    await t.pumpAndSettle();
    expect(await first, isTrue);
    expect(repo.outsideAiConsent, isTrue);
    // Already answered: no screen, same answer.
    expect(await routes.ensureOutsideAiConsent(home), isTrue);
    await t.pumpAndSettle();
    expect(find.text('Yes, share'), findsNothing);
  });

  testWidgets('a no is remembered and nothing is shared; no provider means no screen', (t) async {
    await pump(t, provider: meta);
    final first = routes.ensureOutsideAiConsent(home);
    await t.pumpAndSettle();
    await t.tap(find.text('No thanks'));
    await t.pumpAndSettle();
    expect(await first, isFalse);
    expect(await routes.ensureOutsideAiConsent(home), isFalse);
    await t.pumpAndSettle();
    expect(find.text('No thanks'), findsNothing);

    await pump(t);
    expect(await routes.ensureOutsideAiConsent(home), isFalse);
    await t.pumpAndSettle();
    expect(find.text('No thanks'), findsNothing);
  });

  testWidgets('the weekly check-in opens on demand from My data and by long-press on the Room entry', (t) async {
    await pump(t);
    routes.myData(home);
    await t.pumpAndSettle();
    await t.tap(find.text('Weekly check-in'));
    await t.pumpAndSettle();
    expect(find.byType(CheckInScreen), findsOneWidget);
    Navigator.of(home).pop();
    await t.pumpAndSettle();
    Navigator.of(home).pop();
    await t.pumpAndSettle();

    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: routes.wrap,
        home: const Scaffold(body: CheckInEntry()),
      ),
    );
    await t.pump();
    final entry = find.byType(CheckInEntry);
    await t.longPress(entry);
    await t.pumpAndSettle();
    expect(find.byType(CheckInScreen), findsOneWidget);
  });

  testWidgets('the band: Room pill -> pair screen -> recorded demo -> panel -> settings; delete unpairs', (t) async {
    await pump(t);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: routes.wrap,
        home: Builder(
          builder: (c) => Scaffold(body: Column(children: routes.pills(c))),
        ),
      ),
    );
    expect(find.text('Add band'), findsOneWidget);
    await t.tap(find.text('Add band'));
    await t.pumpAndSettle();
    await t.tap(find.text('Find my band'));
    await t.pumpAndSettle();
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    await t.tap(find.text('Try a recorded demo').first);
    await t.pumpAndSettle();
    expect(routes.band.demo, isTrue);
    expect(find.textContaining('Recorded demo'), findsWidgets);
    await t.ensureVisible(find.text('Band settings'));
    await t.tap(find.text('Band settings'));
    await t.pumpAndSettle();
    expect(find.text('Recorded demo'), findsWidgets);
  });

  test('Apple Health samples are read for a check-in only once Apple Health is connected', () async {
    final sample = HealthSample(
      type: 'STEPS',
      start: DateTime(2026, 10, 23),
      end: DateTime(2026, 10, 23, 1),
      value: 100,
    );
    var connected = false;
    final read = connectedHealthSamples(FakeReader([sample]), () => connected, now: () => DateTime(2026, 10, 24));
    expect(await read(), isEmpty);
    connected = true;
    expect(await read(), [sample]);
  });

  group('Ideas for you, from /api/recommendations', () {
    final reply = {
      'status': 'ok',
      'recommendations': [
        {
          'id': 'walk',
          'lever': 'moderate_plus_90',
          'title': 'A longer dog walk',
          'message': 'A short walk is a great start.',
          'based_on': ['moderate_recreation_min_week', 'note:exercise'],
          'wellness_card': 'activity',
        },
        {
          'id': 'rest',
          'lever': 'short_sleep_plus_1h',
          'title': 'A little more rest',
          'message': 'A bit more sleep can help.',
          'based_on': ['sleep_hours'],
          'wellness_card': 'sleep',
        },
        {
          'id': 'keep',
          'lever': 'keep_it_up',
          'title': 'Keep it up',
          'message': 'Nice routine.',
          'based_on': [],
          'wellness_card': 'activity',
        },
      ],
    };

    Future<(List<Recommendation>, Map<String, dynamic>)> run(
      WidgetTester t, {
      String? provider,
      bool memory = false,
      Object? body,
      int status = 200,
    }) async {
      await pump(t);
      if (memory) {
        await repo.applyMemoryConsent(true);
        await repo.addHabitNote({'topic': 'exercise', 'text': 'I walk the dog after dinner'});
      }
      Map<String, dynamic>? sent;
      final client = MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(body ?? reply), status);
      });
      final source = HttpRecommendations(
        repository: repo,
        base: ApiBase('http://x'),
        outsideAiProvider: provider,
        client: client,
      );
      final ideas = await source.load();
      return (ideas, sent ?? <String, dynamic>{});
    }

    testWidgets('maps ideas to levers; sends no outside-AI consent and no notes unless allowed', (t) async {
      final (ideas, sent) = await run(t);
      expect(ideas.map((i) => i.id), ['walk', 'rest', 'keep']);
      expect(ideas[0].leverId, 'moderate_recreation_min_week');
      expect(ideas[0].leverValue, 180);
      expect(ideas[1].leverValue, 8);
      expect(ideas[2].leverId, isNull);
      expect(ideas[0].habitNoteQuote, isNull);
      expect(sent['outside_ai_consent'], isEmpty);
      expect(sent['habit_notes'], isEmpty);
    });

    testWidgets('with memory on and a yes for the provider: notes and consent go, the quote shows', (t) async {
      final (ideas, sent) = await run(t, provider: 'muse', memory: true);
      expect(sent['outside_ai_consent'], {'muse': true});
      expect(sent['habit_notes'], [
        {'topic': 'exercise'},
      ]);
      expect(ideas[0].habitNoteQuote, 'I walk the dog after dinner');
    });

    testWidgets('an unreachable or empty server falls back to the built-in ideas', (t) async {
      final (broken, _) = await run(t, status: 500);
      expect(broken, isA<List<Recommendation>>());
      final (none, _) = await run(t, body: {'status': 'not_enough_information', 'recommendations': []});
      expect(none, isA<List<Recommendation>>());
    });

    testWidgets('the Experiment offers Ideas for you; the consent is asked first, and a no still shows ideas', (
      t,
    ) async {
      await pump(t, provider: meta);
      String? usedProvider = 'unset';
      routes = AgenticRoutes(
        look: ValueNotifier(const TwinAppearance(name: 'Mochi')),
        api: ApiBase(),
        voice: () => VoiceOnboardingController(
          guide: FakeConversationGuide(),
          input: FakeSpeechInput(),
          output: FakeSpeechOutput(),
        ),
        guide: ContractGuide(),
        changeClient: FakeChangeClient(),
        capabilities: FakeCapabilities(meta),
        recommendations: (p) {
          usedProvider = p;
          return _Ideas();
        },
      )..attach(repo);
      await t.pumpWidget(
        MaterialApp(
          theme: lifeTwinTheme(),
          builder: routes.wrap,
          home: Builder(
            builder: (c) {
              home = c;
              return const Scaffold(body: Text('room'));
            },
          ),
        ),
      );
      routes.experiment(home);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Ideas for you'));
      await t.tap(find.text('Ideas for you'));
      await t.pumpAndSettle();
      expect(find.text('No thanks'), findsOneWidget);
      await t.tap(find.text('No thanks'));
      await t.pumpAndSettle();
      expect(usedProvider, isNull);
      expect(find.text('Go to my room'), findsOneWidget);
    });
  });
}

class _Ideas implements RecommendationsSource {
  @override
  Future<List<Recommendation>> load() async => const [
    Recommendation(id: 'rest', title: 'A little more rest', tip: 'A bit more sleep can help.', wellnessCardId: 'sleep'),
  ];
}
