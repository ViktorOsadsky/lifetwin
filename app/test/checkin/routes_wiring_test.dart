import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/checkin/checkin_screen.dart' show CheckInScreen;
import 'package:lifesim/checkin/consents.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';

import '../support/app_fonts.dart';
import '../support/fake_change_client.dart';
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
}
