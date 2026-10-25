import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/customize/customize_screen.dart';
import 'package:lifesim/entry/guest_login_screen.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/onboarding_autostart.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifesim/voice/fakes.dart';

import 'forecast_screen_test.dart' show FakeForecastClient;
import 'support/app_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });

  void size(WidgetTester t, [Size value = const Size(390, 844)]) {
    t.view.physicalSize = value;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Future<void> app(WidgetTester t, TwinRepository repo, {bool autoStart = false}) async {
    await t.pumpWidget(
      LifeTwinApp(
        key: UniqueKey(),
        showGuestEntry: true,
        autoStartOnboarding: autoStart,
        twin: Future.value(repo),
        controller: VoiceOnboardingController(
          guide: FakeConversationGuide(),
          input: FakeSpeechInput(),
          output: FakeSpeechOutput(),
        ),
        forecastClient: FakeForecastClient(),
      ),
    );
    await t.pump();
    await t.pump();
  }

  Future<void> guest(WidgetTester t) async {
    await t.ensureVisible(find.text('Continue as guest'));
    await t.tap(find.text('Continue as guest'));
    await t.pumpAndSettle();
  }

  Future<void> editName(WidgetTester t, String name) async {
    await t.ensureVisible(find.text('Twin name'));
    await t.tap(find.text('Twin name'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('twin-name-field')), name);
    await t.tap(find.text('Use name'));
    await t.pumpAndSettle();
  }

  testWidgets('first-run guest entry waits before intake, remembers entry, grants no consent', (t) async {
    size(t);
    final backend = MemoryBackend();
    final repo = TwinRepository(model: model, store: await TwinStore.open(backend));
    await app(t, repo, autoStart: true);
    await t.pump(const Duration(seconds: 3));
    expect(find.byType(GuestLoginScreen), findsOneWidget);
    expect(find.byType(VoiceOnboardingScreen), findsNothing);
    expect(repo.store.hasProfile, isFalse);
    await guest(t);
    await t.pump(OnboardingAutoStart.wave + const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(find.byType(VoiceOnboardingScreen), findsOneWidget);
    expect(find.text("No, I'll type"), findsOneWidget);
    final reopened = await TwinStore.open(backend);
    expect(reopened.guestEntryAccepted, isTrue);
    expect(reopened.hasProfile, isFalse);
    expect(reopened.memoryConsent, isFalse);
    expect(reopened.outsideAiConsent, isFalse);
    expect(reopened.checkins, isEmpty);
    expect(reopened.historyEntries, isEmpty);
    await app(t, TwinRepository(model: model, store: reopened));
    expect(find.byType(GuestLoginScreen), findsNothing);
    expect(find.byType(RoomScreen), findsOneWidget);
  });

  testWidgets('existing saved twin bypasses entry without changing old data; deletion clears guest preference', (
    t,
  ) async {
    size(t);
    final backend = MemoryBackend()
      ..text = jsonEncode({
        'version': 1,
        'profile': {'age': 70, 'sex': 'female'},
        'twin': {'name': 'Biscuit', 'type': 'bear', 'look': 'cal_hat'},
        'outside_ai_consent': {'provider': 'claude', 'on': true},
      });
    final repo = TwinRepository(model: model, store: await TwinStore.open(backend));
    final before = backend.text;
    await app(t, repo);
    expect(find.byType(GuestLoginScreen), findsNothing);
    expect(find.bySemanticsLabel('Twin name: Biscuit'), findsOneWidget);
    expect(backend.text, before);
    await repo.continueAsGuest();
    expect(repo.store.profile, {'age': 70, 'sex': 'female'});
    expect(repo.store.outsideAiConsent, isTrue);
    await repo.deleteMyData();
    expect(repo.store.guestEntryAccepted, isFalse);
    expect(backend.text, isNull);
  });

  testWidgets('guest entry prevents repeated submits and lets a failed save retry', (t) async {
    size(t);
    final pending = Completer<void>();
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: GuestLoginScreen(
          onContinue: () {
            calls++;
            return calls == 1 ? pending.future : Future.value();
          },
        ),
      ),
    );
    await t.ensureVisible(find.text('Continue as guest'));
    await t.tap(find.text('Continue as guest'));
    await t.pump();
    expect(find.text('Opening your twin…'), findsOneWidget);
    final button = t.widget<LipButton>(find.byType(LipButton));
    expect(button.onTap, isNull);
    expect(calls, 1);
    pending.completeError(StateError('private store error'));
    await t.pumpAndSettle();
    expect(find.text('We couldn’t save your guest choice. Please try again.'), findsOneWidget);
    expect(find.textContaining('private store'), findsNothing);
    await guest(t);
    expect(calls, 2);
    expect(find.text('We couldn’t save your guest choice. Please try again.'), findsNothing);
  });

  testWidgets('room Customize saves the nickname and restores it on app relaunch', (t) async {
    size(t);
    final backend = MemoryBackend();
    final repo = TwinRepository(model: model, store: await TwinStore.open(backend));
    await repo.continueAsGuest();
    await app(t, repo);
    await t.tap(find.text('Customize'));
    await t.pumpAndSettle();
    await editName(t, '  Clover  ');
    await t.ensureVisible(find.text('Save look'));
    await t.tap(find.text('Save look'));
    await t.pumpAndSettle();
    expect(find.byType(RoomScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Twin name: Clover'), findsOneWidget);
    expect(repo.store.twin?['name'], 'Clover');
    expect(repo.profile, isEmpty);
    expect(repo.current, isNull);
    expect(repo.store.outsideAiConsent, isFalse);
    expect(repo.store.memoryConsent, isFalse);
    final reopened = TwinRepository(model: model, store: await TwinStore.open(backend));
    await app(t, reopened);
    expect(find.bySemanticsLabel('Twin name: Clover'), findsOneWidget);
    expect(find.byType(GuestLoginScreen), findsNothing);
  });

  testWidgets('rename is a cosmetic draft: cancel, trim, save, reopen and reset to default', (t) async {
    size(t);
    final backend = MemoryBackend();
    final repo = TwinRepository(model: model, store: await TwinStore.open(backend));
    final look = ValueNotifier(const TwinAppearance(name: 'Biscuit'));
    addTearDown(look.dispose);
    look.addListener(
      () => repo.saveTwinLook({'name': look.value.name, 'type': look.value.type.name, 'look': look.value.look.slug}),
    );
    var saved = 0;
    Future<void> open() async {
      await t.pumpWidget(
        MaterialApp(
          theme: lifeTwinTheme(),
          home: CustomizeScreen(key: UniqueKey(), appearance: look, onDone: () => saved++),
        ),
      );
    }

    await open();
    await t.tap(find.text('Twin name'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('twin-name-field')), 'Unsaved');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(look.value.name, 'Biscuit');
    expect(find.text('Unsaved'), findsNothing);
    await editName(t, '  Juniper  ');
    expect(look.value.name, 'Biscuit');
    expect(find.bySemanticsLabel('Twin name: Juniper'), findsOneWidget);
    await t.ensureVisible(find.text('Save look'));
    await t.tap(find.text('Save look'));
    await t.pumpAndSettle();
    expect(look.value.name, 'Juniper');
    expect(saved, 1);
    final reopened = await TwinStore.open(backend);
    expect(reopened.twin?['name'], 'Juniper');
    expect(reopened.profile, isEmpty);
    expect(reopened.checkins, isEmpty);
    expect(reopened.historyEntries, isEmpty);
    expect(repo.current, isNull);
    await open();
    await editName(t, '  ');
    await t.ensureVisible(find.text('Save look'));
    await t.tap(find.text('Save look'));
    await t.pump();
    expect(look.value.name, isNull);
    expect(find.bySemanticsLabel('Twin name: My twin'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('name length counts emoji characters and removes control characters', (t) async {
    size(t);
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        home: CustomizeScreen(appearance: look, onDone: () {}),
      ),
    );
    await editName(t, '🌱' * 30);
    await t.ensureVisible(find.text('Save look'));
    await t.tap(find.text('Save look'));
    await t.pump();
    expect(look.value.name, '🌱' * 24);
    await editName(t, 'Fern\n\t\u0000');
    await t.ensureVisible(find.text('Save look'));
    await t.tap(find.text('Save look'));
    await t.pump();
    expect(look.value.name, 'Fern');
    expect(t.takeException(), isNull);
  });

  testWidgets('rename stays usable above the keyboard with large text', (t) async {
    size(t, const Size(375, 667));
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: lifeTwinTheme(),
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 667),
            textScaler: TextScaler.linear(2),
            viewInsets: EdgeInsets.only(bottom: 300),
          ),
          child: child!,
        ),
        home: CustomizeScreen(appearance: look, onDone: () {}),
      ),
    );
    await t.ensureVisible(find.text('Twin name'));
    await t.tap(find.text('Twin name'));
    await t.pumpAndSettle();
    final field = find.byKey(const ValueKey('twin-name-field'));
    await t.ensureVisible(field);
    await t.enterText(field, 'Fern');
    await t.pump();
    await _capture(t, 'rename-keyboard-large', target: field);
    expect(t.getBottomRight(find.text('Use name')).dy, lessThanOrEqualTo(367));
    await t.tap(find.text('Use name'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(t.takeException(), isNull);
  });

  for (final (dimensions, scale, brightness) in [
    (const Size(375, 667), 1.0, Brightness.light),
    (const Size(375, 667), 3.0, Brightness.dark),
    (const Size(844, 390), 2.0, Brightness.light),
    (const Size(1024, 768), 1.0, Brightness.dark),
  ]) {
    testWidgets('guest and rename remain usable at $dimensions text $scale $brightness', (t) async {
      size(t, dimensions);
      t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final look = ValueNotifier(const TwinAppearance());
      addTearDown(look.dispose);
      Widget wrap(Widget child) => MaterialApp(
        theme: lifeTwinTheme(),
        builder: (_, route) => MediaQuery(
          data: MediaQueryData(
            size: dimensions,
            textScaler: TextScaler.linear(scale),
            platformBrightness: brightness,
            disableAnimations: true,
          ),
          child: route!,
        ),
        home: child,
      );
      await t.pumpWidget(wrap(GuestLoginScreen(onContinue: () async {})));
      await t.ensureVisible(find.text('Continue as guest'));
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(LipButton)).height, greaterThanOrEqualTo(48));
      expect(t.takeException(), isNull);
      await _capture(t, 'guest-${dimensions.width.toInt()}-scale$scale');
      await t.pumpWidget(wrap(CustomizeScreen(appearance: look, onDone: () {})));
      await editName(t, 'Willow');
      await t.ensureVisible(find.text('Save look'));
      await t.tap(find.text('Save look'));
      await t.pump();
      expect(look.value.name, 'Willow');
      expect(t.takeException(), isNull);
    });
  }
}

Future<void> _capture(WidgetTester t, String name, {Finder? target}) async {
  final directory = Platform.environment['EVIDENCE_SHOTS'];
  if (directory == null) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.ancestor(of: target ?? find.byType(GuestLoginScreen), matching: find.byType(RepaintBoundary)).last,
  );
  await t.runAsync(() async {
    final shot = await boundary.toImage(pixelRatio: 1);
    final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    shot.dispose();
  });
}
