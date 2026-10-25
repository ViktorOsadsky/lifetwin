// With no profile the conversation starts by itself: Mochi waves, then onboarding fades in.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/onboarding_autostart.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:lifesim/voice/speech.dart';

import 'checkin_controller_test.dart' show FakePort;
import 'forecast_screen_test.dart' show FakeForecastClient;
import 'support/app_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  late TwinRepository repo;
  late ValueNotifier<TwinAppearance> look;
  final flow = jsonDecode(File('test/fixtures/merged_flow.json').readAsStringSync()) as Map<String, dynamic>;

  Map<String, dynamic> copy(Object? v) => jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

  late VoiceOnboardingController intake;
  Future<void> pumpApp(WidgetTester t, {bool profile = false, ConversationGuide? guide}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      reminders: CheckinReminders(FakePort()),
    );
    if (profile) {
      final ready = copy(flow['onboarding_ready']);
      await repo.saveOnboarding(copy(ready['state']), modelInputs: copy(ready['model_inputs']));
    }
    look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(
      LifeTwinApp(
        autoStartOnboarding: true,
        controller: intake = VoiceOnboardingController(
          guide: guide ?? FakeConversationGuide(),
          input: FakeSpeechInput(),
          output: FakeSpeechOutput(),
        ),
        forecastClient: FakeForecastClient(),
        twin: Future.value(repo),
        appearance: look,
      ),
    );
    await t.pump();
    await t.pump();
  }

  final wave = find.byKey(const ValueKey('autostart-wave'));
  final onboarding = find.byType(VoiceOnboardingScreen);

  Future<void> pastWave(WidgetTester t) async {
    await t.pump(OnboardingAutoStart.wave + const Duration(milliseconds: 50));
    await t.pumpAndSettle();
  }

  testWidgets('a fresh app waves, then opens onboarding with no tap', (t) async {
    await pumpApp(t);
    expect(wave, findsOneWidget);
    expect(find.text("Hi! I'm Mochi."), findsOneWidget);
    expect(onboarding, findsNothing);
    await t.pump(const Duration(milliseconds: 700));
    expect(wave, findsOneWidget, reason: 'still waving, not yet onboarding');
    expect(onboarding, findsNothing);
    await pastWave(t);
    expect(onboarding, findsOneWidget);
    expect(wave, findsNothing);
    expect(find.text("No, I'll type"), findsOneWidget, reason: 'the voice question still comes first');
  });

  testWidgets('backing out of onboarding does not start it again', (t) async {
    await pumpApp(t);
    await pastWave(t);
    expect(onboarding, findsOneWidget);
    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(onboarding, findsNothing);
    expect(wave, findsNothing);
    expect(find.byType(RoomScreen), findsOneWidget);
    expect(find.text('Talk'), findsOneWidget, reason: 'the normal Talk entry');
  });

  testWidgets('with a profile there is no auto-start', (t) async {
    await pumpApp(t, profile: true);
    await t.pump(OnboardingAutoStart.wave + const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(wave, findsNothing);
    expect(onboarding, findsNothing);
    expect(find.byType(RoomScreen), findsOneWidget);
  });

  testWidgets('Reduce Motion: no wave, a quick crossfade into onboarding', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(t);
    expect(wave, findsNothing);
    await t.pump();
    await t.pump(const Duration(milliseconds: 160));
    await t.pumpAndSettle();
    expect(wave, findsNothing);
    expect(onboarding, findsOneWidget);
  });

  testWidgets('VoiceOver: the greeting is announced', (t) async {
    final sent = <String>[];
    t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (m) async {
      sent.add('$m');
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, null));
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(t);
    expect(sent.where((m) => m.contains(OnboardingAutoStart.announcement)), isNotEmpty);
    await pastWave(t);
    expect(onboarding, findsOneWidget);
  });

  testWidgets('after Delete my data it starts by itself again, once', (t) async {
    await pumpApp(t, profile: true);
    expect(wave, findsNothing);
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('See your data or delete it'), 200);
    await t.ensureVisible(find.text('See your data or delete it'));
    await t.tap(find.text('See your data or delete it'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Delete my data'));
    await t.tap(find.text('Delete my data'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete everything'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yes, delete'));
    await t.pump(const Duration(milliseconds: 700));
    await t.pump();
    await pastWave(t);
    expect(onboarding, findsOneWidget);
    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 3));
    expect(onboarding, findsNothing);
    expect(wave, findsNothing);
  });

  testWidgets('mid-wave frame', (t) async {
    await pumpApp(t);
    await t.pump(const Duration(milliseconds: 400));
    expect(wave, findsOneWidget);
    final dir = Platform.environment['EVIDENCE_SHOTS'];
    if (dir == null) return;
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.ancestor(of: wave, matching: find.byType(RepaintBoundary)).first,
    );
    await t.runAsync(() async {
      final ui.Image img = await boundary.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/autostart_wave.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });

  testWidgets('auto-start and the end-of-intake offer coexist: a skipped answer gives exactly one offer', (
    t,
  ) async {
    final guide = _SkipThenOffer();
    await pumpApp(t, guide: guide);
    await pastWave(t);
    expect(onboarding, findsOneWidget, reason: 'a fresh app starts onboarding by itself');
    await intake.answerConsent(false);
    await t.pumpAndSettle();
    await intake.skip(); // the last question, skipped: the server makes its one offer
    await t.pumpAndSettle();
    expect(intake.turn!.phase, 'missing');
    expect(find.textContaining('I still need 1 answer'), findsWidgets);
    await intake.submitQuick('not now');
    await t.pumpAndSettle();
    expect(intake.turn!.complete, isTrue);
    expect(guide.offers, 1);
    // Back out to the Room: onboarding does not start by itself again.
    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(guide.starts, 1);
  });
}

/// The server's end of an intake with one answer skipped: one offer, then "not now" finishes.
class _SkipThenOffer implements ConversationGuide {
  int offers = 0, starts = 0;

  @override
  Future<GuideTurn> turn({
    required String action,
    Map<String, dynamic>? state,
    String? text,
    bool fromTranscript = false,
    Map<String, Object>? values,
    bool aiHelper = false,
    String? importSource,
  }) async {
    if (action == 'start') {
      starts++;
      return const GuideTurn(
        state: {'phase': 'asking', 'current_field': 'vigorous_recreation_min_week', 'confirmed_profile': {}},
        message: 'How many minutes of vigorous exercise a week?',
        complete: false,
      );
    }
    if (action == 'skip') {
      offers++;
      return const GuideTurn(
        state: {'phase': 'missing', 'current_field': null, 'missing_offered': true, 'confirmed_profile': {}},
        message: 'I still need 1 answer for your estimate: your vigorous exercise. Want to answer it now?',
        complete: false,
      );
    }
    return const GuideTurn(
      state: {'phase': 'ready', 'current_field': null, 'missing_offered': true, 'confirmed_profile': {}},
      message: "That's okay. You can answer them any time from Home. All done.",
      complete: true,
    );
  }
}
