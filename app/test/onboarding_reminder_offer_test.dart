import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/voice/fakes.dart';

import 'checkin_controller_test.dart' show FakePort;
import 'forecast_screen_test.dart' show FakeForecastClient, supportedJson;
import 'support/assessments.dart';

void main() {
  testWidgets('the reminder offer comes once, after the reveal, once', (t) async {
    final model = await TwinModelService.load();
    final port = FakePort();
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      reminders: CheckinReminders(port),
    );
    final c = VoiceOnboardingController(
      guide: FakeConversationGuide(),
      input: FakeSpeechInput(),
      output: FakeSpeechOutput(),
    );
    final forecast = FakeForecastClient()..answers.add(forecastFrom(supportedJson()));
    await t.pumpWidget(LifeTwinApp(controller: c, forecastClient: forecast, twin: Future.value(repo)));
    await t.tap(find.text('Talk'));
    await t.pumpAndSettle();
    await t.tap(find.text("No, I'll type"));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 700));
    await t.ensureVisible(find.text('Not now'));
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '70');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yes'));
    await t.pumpAndSettle();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('Would you like a gentle reminder each day?'), findsNothing, reason: 'the reveal comes first');
    await t.tap(find.text('Ask the ball'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Back'));
    await t.pumpAndSettle();
    expect(find.text('Would you like a gentle reminder each day?'), findsOneWidget, reason: 'then the offer, on the Room');
    await t.tap(find.text('Yes').last);
    await t.pumpAndSettle();
    expect(port.asks, 1);
    expect(repo.checkinSettings.reminderOffered, isTrue);
    expect(repo.shouldOfferReminders, isFalse, reason: 'so the first check-in does not offer it again');
    expect(find.text('Would you like a gentle reminder each day?'), findsNothing);
  });
}
