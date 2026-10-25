// 2x text on a 320pt-wide phone: the Room, a check-in and the document screen lay out
// with no overflow.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/checkin/check_in.dart';
import 'package:lifesim/checkin/checkin_reminders.dart';
import 'package:lifesim/documents/document_screen.dart';
import 'package:lifesim/documents/document_upload.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/voice/fakes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'checkin/daily_checkin_test.dart' show profile;
import 'checkin_controller_test.dart' show FakePort;
import 'document_pdf_claude_test.dart' show FakeOcr, FakeText;
import 'forecast_screen_test.dart' show FakeForecastClient, supportedJson;
import 'support/app_fonts.dart';
import 'support/assessments.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async {
    await loadAppFonts();
    model = await TwinModelService.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('Room, check-in and documents at 320 wide, 2x text', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      reminders: CheckinReminders(FakePort()),
    );
    await repo.saveConversationProfile(profile);
    final controller = VoiceOnboardingController(
      guide: FakeConversationGuide(),
      input: FakeSpeechInput(),
      output: FakeSpeechOutput(),
    );
    final forecast = FakeForecastClient()..answers.addAll([forecastFrom(supportedJson()), forecastFrom(supportedJson())]);
    await t.pumpWidget(LifeTwinApp(controller: controller, forecastClient: forecast, twin: Future.value(repo)));
    await settle(t);
    expect(t.takeException(), isNull, reason: 'Room');

    final nav = Navigator.of(t.element(find.byType(Scaffold).first));
    openCheckIn(nav.context, kind: CheckInKind.quick).ignore();
    await settle(t);
    expect(t.takeException(), isNull, reason: 'check-in');
    nav.pop();
    await settle(t);

    final ocr = FakeOcr();
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentUploadScreen(
          service: DocumentUploadService(ocr: ocr, extractor: FakeText(), pdfPicker: ocr),
          onDone: (_) {},
        ),
      ),
    );
    await settle(t);
    expect(t.takeException(), isNull, reason: 'documents');
  });
}
