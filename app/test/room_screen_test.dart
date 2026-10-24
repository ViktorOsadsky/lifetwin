import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/onboarding/voice_onboarding_screen.dart';
import 'package:lifesim/room/room_screen.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifesim/voice/fakes.dart';

VoiceOnboardingController fakeController() =>
    VoiceOnboardingController(guide: FakeConversationGuide(), input: FakeSpeechInput(), output: FakeSpeechOutput());

void setPhone(WidgetTester t, [Size size = const Size(390, 844)]) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('Room renders the twin on the plate, the bubble, the mood chip and the dock', (t) async {
    setPhone(t);
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: RoomScreen(appearance: look, onTalk: () {}, onCustomize: () {}, onFortune: () {}),
      ),
    );
    await t.pumpAndSettle();
    final sprite = t.widget<TwinSprite>(find.byType(TwinSprite));
    expect(sprite.appearance.sprite(), 'assets/twin/bear/pose/stand.png');
    expect(find.bySemanticsLabel('Your bear twin in the Cal hat'), findsOneWidget);
    expect(find.text('Hi! Want to chat?'), findsOneWidget);
    expect(find.bySemanticsLabel('Feeling cozy'), findsOneWidget);
    expect(find.bySemanticsLabel('Twin name: My twin'), findsOneWidget);
    for (final label in ['Customize', 'Talk', 'Fortune']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(t.getSize(find.byType(LipButton)).height, greaterThanOrEqualTo(56));
    expect(t.takeException(), isNull);
  });

  testWidgets('Room swaps to the human twin when the look changes', (t) async {
    setPhone(t);
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: RoomScreen(appearance: look, onTalk: () {}, onCustomize: () {}, onFortune: () {}),
      ),
    );
    look.value = look.value.copyWith(type: TwinType.human);
    await t.pumpAndSettle();
    expect(t.widget<TwinSprite>(find.byType(TwinSprite)).appearance.sprite(), 'assets/twin/human/base/cal_hat.png');
  });

  testWidgets('Talk swooshes to the conversation and Back returns to the Room', (t) async {
    setPhone(t);
    await t.pumpWidget(LifeTwinApp(controller: fakeController()));
    expect(find.byType(RoomScreen), findsOneWidget);
    await t.tap(find.text('Talk'));
    await t.pumpAndSettle();
    expect(find.byType(VoiceOnboardingScreen), findsOneWidget);
    expect(find.text('Talk with me?'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Back to room'));
    await t.pumpAndSettle();
    expect(find.byType(VoiceOnboardingScreen), findsNothing);
    expect(find.text('Hi! Want to chat?'), findsOneWidget);
  });

  testWidgets('reduced motion: Talk still opens the conversation, with no running animation after', (t) async {
    setPhone(t);
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
        child: LifeTwinApp(controller: fakeController()),
      ),
    );
    await t.tap(find.text('Talk'));
    await t.pumpAndSettle();
    expect(find.text('Talk with me?'), findsOneWidget);
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('Room does not overflow on a small phone at 1.3x text', (t) async {
    setPhone(t, const Size(375, 667));
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(375, 667), textScaler: TextScaler.linear(1.3)),
          child: RoomScreen(appearance: look, onTalk: () {}, onCustomize: () {}, onFortune: () {}),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
