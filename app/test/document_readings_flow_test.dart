// Information readings from a confirmed document are saved to History through the app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/twin/twin_model.dart' show TwinModelService;
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/voice/fakes.dart';

import 'document_upload_test.dart' show FakeOcr, FakeServer, foundBody, ok, serviceWith, visitDoc;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async => model = await TwinModelService.load());

  testWidgets('confirmed information readings are saved to History; no "not saved yet"', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = TwinRepository(model: model, store: await TwinStore.open(MemoryBackend()));
    await t.pumpWidget(
      LifeTwinApp(
        controller: VoiceOnboardingController(
          guide: FakeConversationGuide(),
          input: FakeSpeechInput(),
          output: FakeSpeechOutput(),
        ),
        twin: Future.value(repo),
        documentService: serviceWith(FakeOcr(visitDoc), FakeServer((_) => ok(foundBody))),
      ),
    );
    await t.pump();
    await t.pump();
    await t.tap(find.text('Upload a document'));
    await t.pumpAndSettle();
    for (final label in [
      'Choose a photo',
      'Yes, it is mine',
      "Yes, that's right",
      "Yes, that's right",
      "Yes, that's right",
      "Yes, that's right",
    ]) {
      await t.ensureVisible(find.text(label));
      await t.pumpAndSettle();
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 800));
    }
    expect(find.textContaining('not saved yet'), findsNothing);
    await t.ensureVisible(find.text('Continue'));
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect([for (final e in repo.readings()) ...e.items].map((i) => i.field), ['systolic_bp', 'diastolic_bp']);
  });
}
