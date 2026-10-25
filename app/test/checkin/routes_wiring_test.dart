import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/agentic_routes.dart';
import 'package:lifesim/band/band_file_intake.dart';
import 'package:lifesim/band/band_file_session.dart';
import 'package:lifesim/band/band_screens.dart';
import 'package:lifesim/band/band_service.dart';
import 'package:lifesim/band/band_store.dart';
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

import '../band/band_file_test.dart' show FakeFiles, bytes, sample;
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
  tearDown(BandFileSession.disposeIfCreated);

  Future<void> pump(WidgetTester t, {AiProvider? provider, BandFilePicker? files}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    deleted = 0;
    // Joined 8 days ago, so the weekly check-in is open (see weekly_gate_test.dart for the gate itself).
    var clock = DateTime.now().subtract(const Duration(days: 8));
    repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()), clock: () => clock);
    await repo.saveConversationProfile(profile);
    clock = DateTime.now();
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
      bandClient: files == null ? null : StubBandClient(),
      bandFilePicker: files,
      onDeleted: () => deleted++,
    )..attach(repo);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        // The live voice look breathes while the microphone is open; keep these routing tests settled.
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true),
          child: routes.wrap(c, child),
        ),
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

  testWidgets('My data opens from the Settings hub route; deleting wipes the phone, tells the shell and returns', (
    t,
  ) async {
    await pump(t);
    routes.myData(home);
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
        // The live voice look breathes while the microphone is open; keep these routing tests settled.
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true),
          child: routes.wrap(c, child),
        ),
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
        // The live voice look breathes while the microphone is open; keep these routing tests settled.
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true),
          child: routes.wrap(c, child),
        ),
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

  testWidgets('Import band file: a lifetwin.band_day.v0 file feeds the band days; Unpair and Delete forget it', (
    t,
  ) async {
    final files = FakeFiles()..chosen = [bytes(sample())];
    await pump(t, files: files);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        // The live voice look breathes while the microphone is open; keep these routing tests settled.
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true),
          child: routes.wrap(c, child),
        ),
        home: Builder(
          builder: (c) => Scaffold(body: Column(children: routes.pills(c))),
        ),
      ),
    );
    await t.tap(find.text('Add band'));
    await t.pumpAndSettle();
    await t.tap(find.text('Import band file'));
    await t.pumpAndSettle();
    expect(routes.band.hasImportedFile, isTrue);
    expect(find.text('Added 1 day from the file.'), findsOneWidget);
    // The panel followed; settings has the row and Unpair forgets the files.
    await t.ensureVisible(find.text('Band settings'));
    // The page is longer now; let the "Added" snackbar leave before tapping near the bottom.
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Band settings'));
    await t.tap(find.text('Band settings'));
    await t.pumpAndSettle();
    expect(find.text('Import band file'), findsOneWidget);
    await t.ensureVisible(find.text('Unpair band'));
    await t.tap(find.text('Unpair band'));
    await t.pumpAndSettle();
    await t.tap(find.text('Unpair'));
    await t.pumpAndSettle();
    expect(files.clears, 1);
    expect(routes.band.hasImportedFile, isFalse);
    // Delete my data forgets them too.
    files.chosen = [bytes(sample())];
    await routes.intake.importFromFiles();
    expect(routes.band.hasImportedFile, isTrue);
    routes.myData(home);
    await t.pumpAndSettle();
    await t.tap(find.text('Delete my data'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete everything'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yes, delete'));
    await t.pumpAndSettle();
    expect(files.clears, 2);
    expect(routes.band.hasImportedFile, isFalse);
  });

  testWidgets('the band panel Today card fits at 390 and 320 wide, and at 1.6x text', (t) async {
    await pump(t);
    final files = FakeFiles()..chosen = [bytes(sample())];
    final store = BandStore(StubBandClient());
    await BandFileIntake(store: store, picker: files).importFromFiles();
    expect(store.hasImportedFile, isTrue);
    for (final (width, scale) in [(390.0, 1.0), (320.0, 1.0), (390.0, 1.6), (320.0, 1.6)]) {
      t.view.physicalSize = Size(width, 844);
      await t.pumpWidget(
        MaterialApp(
          theme: lifeTwinTheme(),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: BandPanelScreen(
            store: store,
            service: BandService(repository: repo),
            onBack: () {},
            onSettings: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '$width wide at $scale x');
      expect(find.text('Not enough wear time today'), findsOneWidget);
    }
  });
}
