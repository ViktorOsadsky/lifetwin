// Real Apple Vision OCR on the simulator, on a synthetic fake-patient document drawn at
// run time (no bundled image) and on a hand-built PDF. With a backend, the recognised
// text also goes through POST /api/documents/extract.
//   flutter test integration_test/document_ocr_sim_test.dart -d <sim> \
//     --dart-define=API_BASE_URL=http://127.0.0.1:8096
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lifesim/documents/document_extract.dart';
import 'package:lifesim/documents/document_ocr.dart';
import 'package:lifesim/documents/document_upload.dart';

const lines = [
  'SYNTHETIC CLINIC - AFTER VISIT SUMMARY',
  'Patient: Testy McFakeface    MRN: 00000001',
  'Date of service: 09/14/2026',
  'Vitals',
  'BP 138/86    Wt 182 lb    Ht 5 ft 6 in',
  'Problem List',
  'Type 2 diabetes mellitus',
  'Social History',
  'Former smoker, quit 2009',
];

/// A white page with black print, as a PNG, drawn with Flutter's own canvas.
Future<Uint8List> renderDocument() async {
  const width = 1240.0, height = 1754.0; // A4 at 150 dpi
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawRect(const Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);
  var y = 120.0;
  for (final line in lines) {
    final painter = TextPainter(
      text: TextSpan(
        text: line,
        style: const TextStyle(color: Colors.black, fontSize: 40, fontFamily: 'Helvetica'),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - 200);
    painter.paint(canvas, Offset(100, y));
    y += painter.height + 36;
  }
  final image = await recorder.endRecording().toImage(width.toInt(), height.toInt());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

/// A one-page PDF with little text, so the native side renders and recognises it.
Uint8List tinyPdf(String text) {
  final stream = 'BT /F1 36 Tf 72 700 Td ($text) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(out.toString()));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const ocr = ChannelDocumentOcr();

  testWidgets('Vision reads a synthetic visit summary photo, rows kept together', (t) async {
    final png = await renderDocument();
    final doc = await ocr.recognize(png);
    final text = doc.pages.single;
    expect(doc.readable, isTrue);
    expect(text, contains('Date of service: 09/14/2026'));
    expect(text, contains('Type 2 diabetes mellitus'));
    expect(text, contains('Former smoker'));
    // The vitals row stays on one line, so each label keeps its value. Vision may read
    // "lb" as "|b"; the server's parser accepts both.
    final vitals = text.split('\n').firstWhere((l) => l.contains('138/86'));
    expect(vitals, contains('Wt 182'));
    expect(vitals, contains('5 ft 6 in'));

    const api = String.fromEnvironment('API_BASE_URL');
    if (api.isEmpty) return;
    final reading = await DocumentUploadService(ocr: ocr, extractor: HttpDocumentExtractor()).readText(doc);
    expect(reading.status, DocumentReadStatus.found);
    final got = {for (final c in reading.candidates) c.field: c.value};
    expect(got['weight_kg'], 82.6);
    expect(got['height_cm'], 167.6);
    expect(got['smoking_status'], 'former');
    expect(got['diabetes_diagnosed'], true);
    expect(got['blood_pressure'], '138/86');
    expect(reading.candidates.map((c) => c.sourceText).join(' '), isNot(contains('McFakeface')));
  });

  testWidgets('Vision reads a PDF page that has no text layer to speak of', (t) async {
    final doc = await ocr.recognize(tinyPdf('Weight 182 lb'), pdf: true);
    expect(doc.pageCount, 1);
    expect(doc.pages.single, contains('182 lb'));
  });

  testWidgets('a locked or broken file is refused plainly', (t) async {
    Object? error;
    try {
      await ocr.recognize(Uint8List.fromList(utf8.encode('not a pdf')), pdf: true);
    } catch (e) {
      error = e;
    }
    expect(error, isA<DocumentReadFailure>().having((e) => e.code, 'code', 'unsupported_type'));
  });

  testWidgets('the document camera is not available on the simulator', (t) async {
    Object? error;
    try {
      await ocr.scan(DocumentSource.camera);
    } catch (e) {
      error = e;
    }
    expect(error, isA<DocumentReadFailure>().having((e) => e.code, 'code', 'camera_unavailable'));
  });
}
