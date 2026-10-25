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

/// Apple Vision through `app/ios/Runner/DocumentScanner.swift`. The image and PDF bytes
/// stay on the native side; only text comes back.
class ChannelDocumentOcr implements DocumentOcr {
  const ChannelDocumentOcr();

  static const _channel = MethodChannel('lifetwin/documents');

  @override
  Future<RecognisedDocument> scan(DocumentSource source) => _call('scan', {'source': source.name});

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
