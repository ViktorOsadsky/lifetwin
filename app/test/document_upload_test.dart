import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/documents/document_extract.dart';
import 'package:lifesim/documents/document_ocr.dart';
import 'package:lifesim/documents/document_screen.dart';
import 'package:lifesim/documents/document_upload.dart';
import 'package:lifesim/main.dart';
import 'package:lifesim/onboarding/voice_onboarding_controller.dart';
import 'package:lifesim/voice/api_base.dart';
import 'package:lifesim/voice/fakes.dart';

/// Synthetic, fake-patient text, as Vision would return it.
const visitText =
    'SYNTHETIC CLINIC - AFTER VISIT SUMMARY\n'
    'Patient: Testy McFakeface\n'
    'Date of service: 09/14/2026\n'
    'BP 138/86   Wt 182 lb   Ht 5\' 6"\n'
    'Problem List\nType 2 diabetes mellitus\nEssential hypertension';

class FakeOcr implements DocumentOcr {
  FakeOcr(this.next);
  Object next; // a RecognisedDocument, or a DocumentReadFailure to throw
  final sources = <DocumentSource>[];

  @override
  Future<RecognisedDocument> scan(DocumentSource source) async {
    sources.add(source);
    if (next case final DocumentReadFailure f) throw f;
    return next as RecognisedDocument;
  }

  @override
  Future<RecognisedDocument> recognize(Uint8List bytes, {bool pdf = false}) => scan(DocumentSource.photos);
}

Map<String, dynamic> candidate(
  String field,
  Object value, {
  String? unit,
  String use = 'model_input',
  String date = '2026-09-14',
}) => {
  'field': field,
  'use': use,
  'value': value,
  'unit': unit,
  'date': date,
  'date_basis': 'document',
  'source_text': 'BP 138/86   Wt 182 lb   Ht 5\' 6"',
  'page': 1,
  'section': 'Vitals',
  'confidence': 'high',
  'method': 'parser',
};

final foundBody = {
  'schema_version': '1.0',
  'status': 'found',
  'candidates': [
    candidate('weight_kg', 82.6, unit: 'kg'),
    candidate('diabetes_diagnosed', true),
    candidate('hypertension_diagnosed', true),
    candidate('blood_pressure', '138/86', unit: 'mmHg', use: 'information'),
  ],
  'notices': <String>[],
  'identifiers_removed': 1,
  'provider_status': 'not_requested',
  'limitations': <String>[],
};

/// A fake LifeTwin server: records every request body and answers with [reply].
class PendingOcr extends FakeOcr {
  PendingOcr() : super(visitDoc);
  final result = Completer<RecognisedDocument>();
  @override
  Future<RecognisedDocument> scan(DocumentSource source) => result.future;
}

class FakeServer {
  FakeServer(this.reply);
  http.Response Function(Map<String, dynamic> body) reply;
  final bodies = <Map<String, dynamic>>[];

  late final client = MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    bodies.add(body);
    return reply(body);
  });

  HttpDocumentExtractor get extractor => HttpDocumentExtractor(client: client, base: ApiBase('http://test', client));
}

http.Response ok(Map<String, dynamic> body) => http.Response(jsonEncode(body), 200);

DocumentUploadService serviceWith(FakeOcr ocr, FakeServer server) =>
    DocumentUploadService(ocr: ocr, extractor: server.extractor);

const visitDoc = RecognisedDocument(pages: [visitText], pageCount: 1);

void main() {
  group('service', () {
    test('sends only the recognised text and consent, then drops the text', () async {
      final server = FakeServer((_) => ok(foundBody));
      final service = serviceWith(FakeOcr(visitDoc), server);
      final r = await service.read(DocumentSource.photos);
      expect(r.status, DocumentReadStatus.found);
      expect(r.candidates.map((c) => c.field), [
        'weight_kg',
        'diabetes_diagnosed',
        'hypertension_diagnosed',
        'blood_pressure',
      ]);
      expect(server.bodies.single.keys.toSet(), {'pages', 'outside_ai_consent'});
      expect(server.bodies.single['pages'], [visitText]);
      expect(server.bodies.single['outside_ai_consent'], false);
      expect(service.holdingText, isFalse);
    });

    test('an unreadable picture never reaches the server', () async {
      final server = FakeServer((_) => ok(foundBody));
      final service = serviceWith(FakeOcr(const RecognisedDocument(pages: ['~ ;; 1?'], pageCount: 1)), server);
      expect((await service.read(DocumentSource.camera)).status, DocumentReadStatus.unreadable);
      expect(server.bodies, isEmpty);
    });

    test('picker results map to plain outcomes', () async {
      final server = FakeServer((_) => ok(foundBody));
      for (final (code, status) in [
        ('cancelled', DocumentReadStatus.cancelled),
        ('camera_unavailable', DocumentReadStatus.cameraUnavailable),
        ('too_large', DocumentReadStatus.tooLarge),
        ('password_protected', DocumentReadStatus.passwordProtected),
        ('unsupported_type', DocumentReadStatus.unsupported),
      ]) {
        final service = serviceWith(FakeOcr(DocumentReadFailure(code)), server);
        expect((await service.read(DocumentSource.pdf)).status, status);
      }
      expect(server.bodies, isEmpty);
    });

    test('Muse is asked only after a yes, with the same text, then the text is dropped', () async {
      final server = FakeServer(
        (body) => ok({
          ...foundBody,
          'candidates': body['outside_ai_consent'] == true ? foundBody['candidates'] : <Object>[],
          'status': body['outside_ai_consent'] == true ? 'found' : 'nothing_found',
          'provider_status': body['outside_ai_consent'] == true ? 'used' : 'consent_required',
        }),
      );
      final service = serviceWith(FakeOcr(visitDoc), server);
      final first = await service.read(DocumentSource.photos);
      expect(first.museCouldHelp, isTrue);
      expect(service.holdingText, isTrue, reason: 'kept in memory for the question only');
      final second = await service.retryWithMuse();
      expect(second.status, DocumentReadStatus.found);
      expect(server.bodies.map((b) => b['outside_ai_consent']), [false, true]);
      expect(server.bodies.last['pages'], server.bodies.first['pages']);
      expect(service.holdingText, isFalse);
    });

    test('server trouble keeps nothing and says so', () async {
      final down = serviceWith(FakeOcr(visitDoc), FakeServer((_) => http.Response('', 503)));
      expect((await down.read(DocumentSource.photos)).status, DocumentReadStatus.serverUnavailable);
      expect(down.holdingText, isFalse);
      final refused = serviceWith(
        FakeOcr(visitDoc),
        FakeServer((_) => http.Response(jsonEncode({'message': 'That document has too many pages.'}), 422)),
      );
      final r = await refused.read(DocumentSource.pdf);
      expect((r.status, r.message), (DocumentReadStatus.rejected, 'That document has too many pages.'));
    });

    test('two patients and other languages are their own outcomes', () async {
      for (final (notice, status) in [
        ('multiple_patients', DocumentReadStatus.multiplePatients),
        ('language_not_supported', DocumentReadStatus.notEnglish),
      ]) {
        final server = FakeServer(
          (_) => ok({
            ...foundBody,
            'status': 'nothing_found',
            'candidates': <Object>[],
            'notices': [notice],
          }),
        );
        expect((await serviceWith(FakeOcr(visitDoc), server).read(DocumentSource.photos)).status, status);
      }
    });
  });

  group('confirmation', () {
    final candidates = DocumentExtraction.fromJson(foundBody).candidates;

    test('only confirmed values are used; a no goes to Mochi; nothing is edited', () {
      final c = DocumentConfirmation(candidates)..answerAboutYou(true);
      c.answer(false); // weight: not right
      c.answer(true); // diabetes
      c.answer(true); // hypertension
      c.answer(true); // blood pressure note
      expect(c.done, isTrue);
      final r = c.result;
      expect(r.profileValues, {'diabetes': true, 'hypertension_diagnosed': true});
      expect(r.toAsk, ['weight_kg']);
      expect(r.notes.map((c) => c.field), ['blood_pressure']);
    });

    test('a document about someone else gives nothing', () {
      final c = DocumentConfirmation(candidates)..answerAboutYou(false);
      expect(c.done, isTrue);
      expect(c.result.confirmed, isEmpty);
      expect(c.result.profileValues, isEmpty);
    });

    test('go back undoes the last answer', () {
      final c = DocumentConfirmation(candidates)..answerAboutYou(true);
      c.answer(true);
      c.back();
      expect(c.index, 0);
      c.back();
      expect(c.aboutYou, isNull);
    });

    test('read-backs use everyday units and ask about old readings', () {
      final now = DateTime(2026, 10, 24);
      final weight = candidates.first;
      expect(
        documentReadBack(weight, imperial: true, now: now),
        'Your document says you weigh about 182 pounds. That was from September 14. Is this right?',
      );
      final old = DocumentCandidate.fromJson(candidate('height_cm', 167.6, unit: 'cm', date: '2019-03-02'));
      expect(documentReadBack(old, imperial: true, now: now), contains('Is it still right today?'));
      expect(documentReadBack(old, imperial: true, now: now), contains('5 feet 6 inches'));
      final bp = candidates.last;
      expect(
        documentReadBack(bp, imperial: true, now: now),
        contains("138 over 86. That was from September 14. This reading doesn't change your forecast"),
      );
    });
  });

  test('stopped native read cannot send its late text to extraction', () async {
    final ocr = PendingOcr();
    final server = FakeServer((_) => ok(foundBody));
    final service = serviceWith(ocr, server);
    final reading = service.read(DocumentSource.camera);
    service.discard();
    ocr.result.complete(visitDoc);
    expect((await reading).status, DocumentReadStatus.cancelled);
    expect(server.bodies, isEmpty);
    expect(service.holdingText, isFalse);
  });

  group('screen', () {
    void setPhone(WidgetTester t) {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
    }

    Future<void> tap(WidgetTester t, String label) async {
      await t.ensureVisible(find.text(label));
      await t.pumpAndSettle();
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 800)); // past the double-tap guard
    }

    testWidgets('upload, check it is mine, confirm one by one, continue', (t) async {
      setPhone(t);
      DocumentImportResult? done;
      final server = FakeServer((_) => ok(foundBody));
      await t.pumpWidget(
        MaterialApp(
          home: DocumentUploadScreen(
            service: serviceWith(FakeOcr(visitDoc), server),
            now: () => DateTime(2026, 10, 24),
            onDone: (r) => done = r,
          ),
        ),
      );
      expect(find.text('Upload a health document?'), findsOneWidget);
      await tap(t, 'Choose a photo');
      expect(find.text('Is this document about you?'), findsOneWidget);
      await tap(t, 'Yes, it is mine');
      expect(find.text('Question 1 of 4'), findsOneWidget);
      expect(find.textContaining('you weigh about'), findsOneWidget);
      expect(find.text('From your document:'), findsOneWidget);
      await tap(t, "No, that's not right");
      await tap(t, "Yes, that's right");
      await tap(t, 'Go back'); // undo the diabetes answer
      expect(find.text('Question 2 of 4'), findsOneWidget);
      await tap(t, "Yes, that's right");
      await tap(t, "No, that's not right");
      await tap(t, "No, that's not right");
      expect(find.text('Thank you'), findsOneWidget);
      await tap(t, 'Continue');
      expect(done!.profileValues, {'diabetes': true});
      expect(done!.toAsk, ['weight_kg', 'hypertension_diagnosed']);
    });

    testWidgets('a conflicting document cannot replace a saved answer', (t) async {
      setPhone(t);
      DocumentImportResult? result;
      await t.pumpWidget(MaterialApp(home: DocumentUploadScreen(
        service: serviceWith(FakeOcr(visitDoc), FakeServer((_) => ok(foundBody))),
        confirmedValues: const {'weight_kg': 70},
        onDone: (r) => result = r,
      )));
      await tap(t, 'Choose a photo');
      await tap(t, 'Yes, it is mine');
      expect(find.text('Two different answers'), findsOneWidget);
      expect(find.textContaining('70 kg'), findsOneWidget);
      expect(find.text("Yes, that's right"), findsNothing);
      await tap(t, 'Talk it over with Mochi');
      expect(result!.profileValues, isEmpty);
      expect(result!.toAsk, contains('weight_kg'));
    });

    testWidgets('declining upload changes nothing', (t) async {
      setPhone(t);
      DocumentImportResult? done;
      final server = FakeServer((_) => ok(foundBody));
      await t.pumpWidget(
        MaterialApp(
          home: DocumentUploadScreen(service: serviceWith(FakeOcr(visitDoc), server), onDone: (r) => done = r),
        ),
      );
      await tap(t, "No thanks, I'll tell you instead");
      expect(done!.confirmed, isEmpty);
      expect(server.bodies, isEmpty);
    });

    testWidgets('an unreadable photo offers another try or telling instead', (t) async {
      setPhone(t);
      DocumentImportResult? done;
      final ocr = FakeOcr(const RecognisedDocument(pages: [''], pageCount: 1));
      final server = FakeServer((_) => ok(foundBody));
      await t.pumpWidget(
        MaterialApp(
          home: DocumentUploadScreen(service: serviceWith(ocr, server), onDone: (r) => done = r),
        ),
      );
      await tap(t, 'Scan a paper');
      expect(find.text("I couldn't read that"), findsOneWidget);
      expect(find.textContaining('Handwriting'), findsOneWidget);
      await tap(t, 'Try another document');
      ocr.next = visitDoc;
      await tap(t, 'Choose a PDF');
      expect(find.text('Is this document about you?'), findsOneWidget);
      await tap(t, "No, it isn't");
      await tap(t, 'Continue');
      expect(done!.confirmed, isEmpty);
    });

    testWidgets('Muse by Meta is asked by name, and no keeps it off', (t) async {
      setPhone(t);
      final server = FakeServer(
        (_) => ok({
          ...foundBody,
          'status': 'nothing_found',
          'candidates': <Object>[],
          'provider_status': 'consent_required',
        }),
      );
      await t.pumpWidget(
        MaterialApp(
          home: DocumentUploadScreen(service: serviceWith(FakeOcr(visitDoc), server), onDone: (_) {}),
        ),
      );
      await tap(t, 'Choose a photo');
      expect(find.textContaining('Muse can help find your numbers. It gets the words, never the photo. Just this document.'), findsOneWidget);
      await tap(t, 'No thanks');
      expect(find.text("I didn't find any answers in it"), findsOneWidget);
      expect(server.bodies.map((b) => b['outside_ai_consent']), [false]);
    });
  });

  group('app', () {
    VoiceOnboardingController fakeController(FakeConversationGuide guide) =>
        VoiceOnboardingController(guide: guide, input: FakeSpeechInput(), output: FakeSpeechOutput());

    testWidgets('the Room offers upload; confirmed values wait for the talk, labelled as a document', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final guide = FakeConversationGuide();
      final c = fakeController(guide);
      final server = FakeServer((_) => ok(foundBody));
      await t.pumpWidget(LifeTwinApp(controller: c, documentService: serviceWith(FakeOcr(visitDoc), server)));
      await t.pump();
      await t.tap(find.text('Upload a document'));
      await t.pumpAndSettle();
      for (final label in [
        'Choose a photo',
        'Yes, it is mine',
        "Yes, that's right",
        "Yes, that's right",
        "No, that's not right",
        "No, that's not right",
        'Continue',
      ]) {
        await t.ensureVisible(find.text(label));
        await t.pumpAndSettle();
        await t.tap(find.text(label));
        await t.pumpAndSettle();
        await t.pump(const Duration(milliseconds: 800));
      }
      expect(c.hasPendingHealth, isTrue);
      expect(c.confirmedProfile, isEmpty, reason: 'nothing is used before the talk takes it');
      await c.answerConsent(false);
      final import = guide.calls.firstWhere((call) => call['action'] == 'import');
      expect(import['values'], {'weight_kg': 82.6, 'diabetes': true});
      expect(import['importSource'], 'document');
    });

    testWidgets('a failed upload keeps answers confirmed before', (t) async {
      final guide = FakeConversationGuide();
      final c = fakeController(guide);
      await c.importHealth({'height_cm': 160});
      final service = serviceWith(FakeOcr(visitDoc), FakeServer((_) => http.Response('', 503)));
      final r = await service.read(DocumentSource.photos);
      expect(r.status, DocumentReadStatus.serverUnavailable);
      await c.answerConsent(false);
      final import = guide.calls.firstWhere((call) => call['action'] == 'import');
      expect(import['values'], {'height_cm': 160});
      expect(import['importSource'], 'apple_health');
    });
  });
}
