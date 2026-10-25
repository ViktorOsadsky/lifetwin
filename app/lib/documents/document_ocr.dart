import 'package:flutter/services.dart';

/// Where the document comes from. See docs/document-upload.md.
enum DocumentSource { camera, photos, pdf }

/// Text recognised on the phone, one string per page or photo. Never the image.
class RecognisedDocument {
  const RecognisedDocument({required this.pages, required this.pageCount, this.truncated = false});

  final List<String> pages;

  /// Pages in the original; only the first 10 are read.
  final int pageCount;
  final bool truncated;

  /// Too little text to be worth sending (a blank, dark or very blurry picture).
  bool get readable => pages.join().replaceAll(RegExp('[^A-Za-z]'), '').length >= 20;
}

/// Why nothing could be read. [code] is one of: cancelled, camera_unavailable,
/// unsupported_type, too_large, password_protected, busy, failed, unavailable.
class DocumentReadFailure implements Exception {
  const DocumentReadFailure(this.code);
  final String code;

  @override
  String toString() => 'DocumentReadFailure($code)';
}

/// On-device text recognition. Tests pass a fake.
abstract class DocumentOcr {
  /// Shows the picker or document camera, then recognises the text.
  Future<RecognisedDocument> scan(DocumentSource source);

  /// Recognises the text of bytes already in memory (tests and the simulator check).
  Future<RecognisedDocument> recognize(Uint8List bytes, {bool pdf = false});
}

/// A PDF the person picked, in memory only, for the "send it to be read?" question.
class PickedPdf {
  const PickedPdf({required this.bytes, required this.pageCount});
  final Uint8List bytes;
  final int pageCount;
}

/// Picks a PDF without reading it, so the person can choose who reads it.
abstract class PdfPicker {
  /// Throws [DocumentReadFailure] (cancelled, too_large, password_protected, ...).
  Future<PickedPdf> pickPdf();
}

/// Apple Vision through `app/ios/Runner/DocumentScanner.swift`. Image bytes stay on the
/// native side; only text comes back. [pickPdf] alone returns a PDF's bytes, held in memory
/// until the person answers whether to send it.
class ChannelDocumentOcr implements DocumentOcr, PdfPicker {
  const ChannelDocumentOcr();

  static const _channel = MethodChannel('lifetwin/documents');

  @override
  Future<RecognisedDocument> scan(DocumentSource source) => _call('scan', {'source': source.name});

  @override
  Future<PickedPdf> pickPdf() async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('pick_pdf');
      final bytes = r?['bytes'];
      if (bytes is! Uint8List) throw const DocumentReadFailure('failed');
      return PickedPdf(bytes: bytes, pageCount: (r?['page_count'] as int?) ?? 0);
    } on PlatformException catch (e) {
      throw DocumentReadFailure(e.code);
    } on MissingPluginException {
      throw const DocumentReadFailure('unavailable');
    }
  }

  @override
  Future<RecognisedDocument> recognize(Uint8List bytes, {bool pdf = false}) =>
      _call('recognize', {'bytes': bytes, 'type': pdf ? 'pdf' : 'image'});

  Future<RecognisedDocument> _call(String method, Map<String, Object> args) async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>(method, args);
      if (r == null) throw const DocumentReadFailure('failed');
      return RecognisedDocument(
        pages: [for (final p in (r['pages'] as List? ?? const [])) '$p'],
        pageCount: (r['page_count'] as int?) ?? 0,
        truncated: r['truncated'] == true,
      );
    } on PlatformException catch (e) {
      throw DocumentReadFailure(e.code);
    } on MissingPluginException {
      // Not on iOS (or a test without the channel).
      throw const DocumentReadFailure('unavailable');
    }
  }
}
