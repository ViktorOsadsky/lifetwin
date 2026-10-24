import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/customize/customize_screen.dart';
import 'package:lifesim/forecast/forecast_client.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/ui/twin_appearance.dart';
import 'package:lifesim/ui/twin_assets.dart';
import 'package:lifesim/ui/widgets/widgets.dart';
import 'package:lifesim/voice/fakes.dart';

class NeverForecast implements ForecastClient {
  int calls = 0;
  @override
  Future<Forecast> predict(Map<String, dynamic> confirmedProfile) async {
    calls++;
    throw const ForecastFailure('not expected');
  }
}

void setPhone(WidgetTester t) {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('Customize shows Bear / Human, the tabs and the Cal hat selected; Save look keeps the change', (t) async {
    setPhone(t);
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    var done = 0;
    await t.pumpWidget(MaterialApp(home: CustomizeScreen(appearance: look, onDone: () => done++)));
    for (final label in ['Bear', 'Human', 'Hats', 'Tops', 'Glasses', 'Fur', 'Aids', 'Cal hat', 'Save look']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(t.getSemantics(find.text('Cal hat')), isSemantics(label: 'Cal hat', isChecked: true));

    await t.tap(find.text('Human'));
    await t.pump();
    expect(look.value.type, TwinType.bear); // nothing is saved until Save look
    await t.ensureVisible(find.text('Save look'));
    await t.tap(find.text('Save look'));
    await t.pump();
    expect(look.value, const TwinAppearance(type: TwinType.human, look: TwinLook.calHat));
    expect(done, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('Customize never touches the health profile, the conversation or the forecast', (t) async {
    setPhone(t);
    final guide = FakeConversationGuide();
    final c = VoiceOnboardingController(guide: guide, input: FakeSpeechInput(), output: FakeSpeechOutput());
    final forecast = NeverForecast();
    final look = ValueNotifier(const TwinAppearance());
    addTearDown(look.dispose);
    await t.pumpWidget(LifeTwinApp(controller: c, forecastClient: forecast, appearance: look));
    final before = Map<String, dynamic>.from(c.confirmedProfile);

    await t.tap(find.text('Customize'));
    await t.pumpAndSettle();
    expect(find.byType(CustomizeScreen), findsOneWidget);
    await t.tap(find.text('Human'));
    await t.tap(find.text('No hat'));
    await t.ensureVisible(find.text('Save look'));
    await t.tap(find.text('Save look'));
    await t.pumpAndSettle();

    // Back in the Room, with the new look.
    expect(find.byType(CustomizeScreen), findsNothing);
    expect(t.widget<TwinSprite>(find.byType(TwinSprite)).appearance.sprite(), 'assets/twin/human/pose_nohat/stand.png');
    // Nothing reached the server, the profile or the forecast.
    expect(guide.calls, isEmpty);
    expect(c.confirmedProfile, before);
    expect(c.turn, isNull);
    expect(forecast.calls, 0);
  });
}
