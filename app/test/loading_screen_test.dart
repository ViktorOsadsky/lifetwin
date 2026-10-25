// The startup loading screen: Mochi waving on lavender until the model and the store open.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/ui/loading_screen.dart';
import 'package:lifesim/ui/theme.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/widgets/twin_sprite.dart';
import 'package:lifesim/voice/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async => model = await TwinModelService.load());

  VoiceOnboardingController controller() =>
      VoiceOnboardingController(guide: FakeConversationGuide(), input: FakeSpeechInput(), output: FakeSpeechOutput());

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('the loading screen is Mochi waving, centred on lavender', (t) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(const MaterialApp(home: LoadingScreen()));
    final box = t.widget<ColoredBox>(find.descendant(of: find.byType(LoadingScreen), matching: find.byType(ColoredBox)).first);
    expect(box.color, LtColors.lavender);
    final sprite = t.widget<TwinSprite>(find.byType(TwinSprite));
    expect(sprite.pose, TwinPose.wave);
    expect(find.ancestor(of: find.byType(TwinSprite), matching: find.byType(Center)), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('LifeTwin is loading')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the first frame waits until Mochi is decoded, then goes through', (t) async {
    // The prior rendering test may have decoded Mochi already. Exercise a cold
    // image load so a synchronous cache hit cannot release the frame immediately.
    t.binding.imageCache.clear();
    t.binding.imageCache.clearLiveImages();
    expect(t.binding.sendFramesToEngine, isTrue);
    await t.runAsync(() async {
      holdFirstFrameUntilMochi(t.binding, timeout: const Duration(seconds: 10));
      expect(t.binding.sendFramesToEngine, isFalse);
      for (var i = 0; i < 100 && !t.binding.sendFramesToEngine; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    // Released by the decoded sprite, well before the 10 s fallback.
    expect(t.binding.sendFramesToEngine, isTrue);
  });

  testWidgets('the app shows the loading screen until the store opens, then the Room', (t) async {
    phone(t);
    final opening = Completer<TwinRepository>();
    await t.pumpWidget(LifeTwinApp(controller: controller(), twin: opening.future, loadingScreen: true));
    await t.pump();
    expect(find.byType(LoadingScreen), findsOneWidget);
    expect(find.byType(RoomScreen), findsNothing);

    opening.complete(TwinRepository(model: model, store: await TwinStore.open(MemoryBackend())));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(LoadingScreen), findsNothing);
    expect(find.byType(RoomScreen), findsOneWidget);
  });

  testWidgets('if the store fails to open, the Room still appears', (t) async {
    phone(t);
    final opening = Completer<TwinRepository>();
    await t.pumpWidget(LifeTwinApp(controller: controller(), twin: opening.future, loadingScreen: true));
    opening.completeError(StateError('no store'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(LoadingScreen), findsNothing);
    expect(find.byType(RoomScreen), findsOneWidget);
  });

  testWidgets('without loadingScreen (the tests default) the Room shows at once', (t) async {
    phone(t);
    await t.pumpWidget(LifeTwinApp(controller: controller(), twin: Completer<TwinRepository>().future));
    expect(find.byType(LoadingScreen), findsNothing);
    expect(find.byType(RoomScreen), findsOneWidget);
  });
}
