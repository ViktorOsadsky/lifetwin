import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifesim/documents/document_extract.dart';
import 'package:lifesim/documents/document_ocr.dart';
import 'package:lifesim/documents/document_screen.dart';
import 'package:lifesim/documents/document_upload.dart';
import 'package:lifesim/voice/api_base.dart';

/// Synthetic, fake-patient text, as Vision would return it.
const visitText =
    'SYNTHETIC CLINIC - AFTER VISIT SUMMARY\n'
    'Patient: Testy McFakeface\n'
    'Date of service: 09/14/2026\n'
    'Wt 182 lb\n';
const visitDoc = RecognisedDocument(pages: [visitText], pageCount: 1);
final pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.4 synthetic test bytes'));

const sheetText =
    'Claude by Anthropic will read this whole document to find your numbers. It may see other details in it too.';

/// Records which on-device paths ran.
class FakeOcr implements DocumentOcr, PdfPicker {
  FakeOcr({this.picked});
  PickedPdf? picked;
  final scanned = <DocumentSource>[];
  final recognised = <Uint8List>[];

  @override
  Future<RecognisedDocument> scan(DocumentSource source) async {
    scanned.add(source);
    return visitDoc;
  }

  @override
  Future<RecognisedDocument> recognize(Uint8List bytes, {bool pdf = false}) async {
    recognised.add(bytes);
    return visitDoc;
  }

  @override
  Future<PickedPdf> pickPdf() async => picked ?? PickedPdf(bytes: pdfBytes, pageCount: 2);
}

class FakeText implements DocumentExtractor {
  final sent = <List<String>>[];

  @override
  Future<DocumentExtraction> extract(List<String> pages, {Map<String, bool> outsideAiConsent = const {}}) async {
    sent.add(pages);
    return DocumentExtraction.fromJson(found('parser'));
  }
}

class FakePdfReader implements PdfDocumentReader {
  FakePdfReader(this.provider, {this.answer});
  final PdfReaderInfo? provider;
  Map<String, dynamic>? answer;
  final sent = <(Uint8List, Map<String, bool>)>[];

  @override
  Future<PdfReaderInfo?> info() async => provider;

  @override
  Future<DocumentExtraction> readPdf(Uint8List pdf, {required Map<String, bool> outsideAiConsent}) async {
    sent.add((pdf, outsideAiConsent));
    final a = answer;
    if (a == null) throw const DocumentExtractUnavailable();
    return DocumentExtraction.fromJson(a);
  }
}

const claude = PdfReaderInfo(id: 'claude', displayName: 'Claude by Anthropic', company: 'Anthropic');

Map<String, dynamic> found(String method, {String providerStatus = 'not_requested'}) => {
  'schema_version': '1.0',
  'status': 'found',
  'candidates': [
    {
      'field': 'weight_kg',
      'use': 'model_input',
      'value': 82.6,
      'unit': 'kg',
      'date': '2026-09-14',
      'date_basis': 'document',
      'source_text': 'Wt 182 lb',
      'page': 1,
      'section': 'Vitals',
      'confidence': 'high',
      'method': method,
    },
  ],
  'notices': <String>[],
  'identifiers_removed': 1,
  'provider_status': providerStatus,
  'limitations': <String>[],
};

Map<String, dynamic> empty(String providerStatus) => {
  ...found('parser'),
  'status': 'nothing_found',
  'candidates': <Object>[],
  'provider_status': providerStatus,
};

void setPhone(WidgetTester t) {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Future<void> tap(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label));
  await t.pumpAndSettle();
  await t.tap(find.text(label));
  await t.pumpAndSettle();
  await t.pump(const Duration(milliseconds: 800));
}

void main() {
  group('capabilities and the HTTP reader', () {
    test('only a configured documents provider is offered, by the name the server gives', () {
      Map<String, dynamic> caps(Map<String, dynamic> pdf) => {
        'documents': {'text_extraction': true, 'pdf': pdf},
      };
      final info = PdfReaderInfo.fromCapabilities(
        caps({
          'provider': 'claude',
          'display_name': 'Claude by Anthropic',
          'company': 'Anthropic',
          'configured': true,
          'max_bytes': 10485760,
          'max_pages': 20,
        }),
      )!;
      expect((info.id, info.displayName, info.company, info.maxBytes, info.maxPages), (
        'claude',
        'Claude by Anthropic',
        'Anthropic',
        10485760,
        20,
      ));
      expect(
        PdfReaderInfo.fromCapabilities(caps({'provider': 'local', 'display_name': null, 'configured': false})),
        isNull,
      );
      expect(PdfReaderInfo.fromCapabilities({'documents': 'text_extraction'}), isNull);
    });

    test('yes sends the PDF as base64 with consent for that provider only', () async {
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        requests.add(r);
        return http.Response(jsonEncode(found('claude', providerStatus: 'used')), 200);
      });
      final reader = HttpPdfDocumentReader(client: client, base: ApiBase('http://test', client));
      final r = await reader.readPdf(pdfBytes, outsideAiConsent: {'claude': true});
      expect(r.providerStatus, 'used');
      expect(requests.single.url.path, '/api/documents/read');
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), {'pdf_base64', 'outside_ai_consent'});
      expect(base64Decode(body['pdf_base64'] as String), pdfBytes);
      expect(body['outside_ai_consent'], {'claude': true});
    });

    test('a refused or unreachable read is unavailable, never a crash', () async {
      for (final status in [413, 422, 500]) {
        final client = MockClient((_) async => http.Response('{"message": "That PDF is too big"}', status));
        final reader = HttpPdfDocumentReader(client: client, base: ApiBase('http://test', client));
        await expectLater(
          reader.readPdf(pdfBytes, outsideAiConsent: {'claude': true}),
          throwsA(isA<DocumentExtractUnavailable>()),
        );
      }
    });
  });

  group('screen', () {
    Future<(FakeOcr, FakeText, FakePdfReader)> open(
      WidgetTester t, {
      PdfReaderInfo? provider = claude,
      Map<String, dynamic>? answer,
      PickedPdf? picked,
    }) async {
      setPhone(t);
      final ocr = FakeOcr(picked: picked);
      final text = FakeText();
      final reader = FakePdfReader(provider, answer: answer);
      await t.pumpWidget(
        MaterialApp(
          home: DocumentUploadScreen(
            service: DocumentUploadService(ocr: ocr, extractor: text, pdfPicker: ocr, pdfReader: reader),
            now: () => DateTime(2026, 10, 24),
            onDone: (_) {},
          ),
        ),
      );
      await tap(t, 'Choose a PDF');
      return (ocr, text, reader);
    }

    testWidgets('the sheet appears when Claude reads documents, and yes sends the PDF', (t) async {
      final (ocr, text, reader) = await open(t, answer: found('claude', providerStatus: 'used'));
      expect(find.text(sheetText), findsOneWidget);
      expect(find.text('Yes, send it'), findsOneWidget);
      expect(find.text('No, read it on this phone'), findsOneWidget);
      expect(reader.sent, isEmpty); // nothing goes before the yes
      await tap(t, 'Yes, send it');
      expect(reader.sent.single.$1, pdfBytes);
      expect(reader.sent.single.$2, {'claude': true});
      expect(ocr.recognised, isEmpty);
      expect(text.sent, isEmpty);
      // The same read-back confirmation as every other document.
      expect(find.text('Is this document about you?'), findsOneWidget);
      await tap(t, 'Yes, it is mine');
      expect(find.text('Question 1 of 1'), findsOneWidget);
      expect(find.textContaining('you weigh about'), findsOneWidget);
    });

    testWidgets('the provider name comes from the server', (t) async {
      await open(t, provider: const PdfReaderInfo(id: 'other', displayName: 'Some Reader'));
      expect(
        find.text('Some Reader will read this whole document to find your numbers. It may see other details in it too.'),
        findsOneWidget,
      );
      expect(find.textContaining('Claude'), findsNothing);
    });

    testWidgets('no keeps it on the phone: recognised there, only text is sent', (t) async {
      final (ocr, text, reader) = await open(t, answer: found('claude', providerStatus: 'used'));
      await tap(t, 'No, read it on this phone');
      expect(reader.sent, isEmpty);
      expect(ocr.recognised.single, pdfBytes);
      expect(text.sent.single, [visitText]);
      expect(find.text('Is this document about you?'), findsOneWidget);
    });

    testWidgets('no documents provider: no sheet, the existing on-device path', (t) async {
      final (ocr, text, reader) = await open(t, provider: null);
      expect(find.text(sheetText), findsNothing);
      expect(ocr.scanned, [DocumentSource.pdf]);
      expect(reader.sent, isEmpty);
      expect(text.sent.single, [visitText]);
    });

    for (final status in ['consent_required', 'unavailable']) {
      testWidgets('a $status answer falls back to reading on the phone', (t) async {
        final (ocr, text, reader) = await open(t, answer: empty(status));
        await tap(t, 'Yes, send it');
        expect(reader.sent, hasLength(1));
        expect(ocr.recognised.single, pdfBytes);
        expect(text.sent.single, [visitText]);
        expect(find.text('Is this document about you?'), findsOneWidget);
      });
    }

    testWidgets('a server error also falls back to the phone', (t) async {
      final (ocr, text, _) = await open(t);
      await tap(t, 'Yes, send it');
      expect(ocr.recognised.single, pdfBytes);
      expect(text.sent, hasLength(1));
    });

    testWidgets('a PDF over the limits is never offered for sending', (t) async {
      final (ocr, _, reader) = await open(t, picked: PickedPdf(bytes: pdfBytes, pageCount: 21));
      expect(find.text(sheetText), findsNothing);
      expect(reader.sent, isEmpty);
      expect(ocr.recognised.single, pdfBytes);
    });

    testWidgets('leaving while the server is asked opens no picker and changes nothing', (t) async {
      setPhone(t);
      final ocr = FakeOcr();
      final asked = Completer<PdfReaderInfo?>();
      final slow = _SlowPdfReader(asked.future);
      final service = DocumentUploadService(
        ocr: ocr,
        extractor: FakeText(),
        pdfPicker: ocr,
        pdfReader: slow,
      );
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold(body: Text('room'))));
      nav.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => DocumentUploadScreen(service: service, onDone: (_) {})),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Choose a PDF'));
      await t.pumpAndSettle();
      await t.tap(find.text('Choose a PDF'));
      await t.pump();
      expect(slow.asked, 1);
      nav.currentState!.pop();
      await t.pumpAndSettle();
      asked.complete(null); // no provider: the old path would now open the phone's picker
      await t.pumpAndSettle();
      expect(ocr.scanned, isEmpty);
      expect(t.takeException(), isNull);
    });

    testWidgets('going back drops the picked PDF', (t) async {
      setPhone(t);
      final ocr = FakeOcr();
      final service = DocumentUploadService(
        ocr: ocr,
        extractor: FakeText(),
        pdfPicker: ocr,
        pdfReader: FakePdfReader(claude),
      );
      await t.pumpWidget(MaterialApp(home: DocumentUploadScreen(service: service, onDone: (_) {})));
      await tap(t, 'Choose a PDF');
      expect(service.holdingPdf, isTrue);
      await tap(t, 'Go back');
      expect(service.holdingPdf, isFalse);
      expect(find.text('Upload a health document?'), findsOneWidget);
    });
  });
}

class _SlowPdfReader extends FakePdfReader {
  _SlowPdfReader(this._info) : super(null);
  final Future<PdfReaderInfo?> _info;
  int asked = 0;

  @override
  Future<PdfReaderInfo?> info() {
    asked++;
    return _info;
  }
}
