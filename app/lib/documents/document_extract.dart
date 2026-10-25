import 'dart:convert';

import 'package:http/http.dart' as http;

import '../voice/api_base.dart';
import '../voice/backend_http_client.dart';

/// One suggested value from a document. Shapes match contracts/documents.extract.schema.json.
/// Nothing here is used until the person confirms it.
class DocumentCandidate {
  const DocumentCandidate({
    required this.field,
    required this.value,
    required this.sourceText,
    required this.page,
    this.modelInput = true,
    this.unit,
    this.date,
    this.dateFromLine = false,
    this.section,
    this.confidence = 'high',
    this.method = 'parser',
  });

  /// height_cm, weight_kg, smoking_status, diabetes_diagnosed, hypertension_diagnosed,
  /// blood_pressure, hba1c or ldl_cholesterol.
  final String field;

  /// num (cm, kg, %, mg/dL), String ("former", "138/86") or true.
  final Object value;
  final bool modelInput;
  final String? unit;
  final DateTime? date;

  /// The date was on the value's own line, not the document's date.
  final bool dateFromLine;

  /// The identifier-stripped line the value came from.
  final String sourceText;
  final int page;
  final String? section;
  final String confidence;

  /// parser, or muse (Muse by Meta, with the person's consent).
  final String method;

  static DocumentCandidate fromJson(Map<String, dynamic> j) => DocumentCandidate(
    field: j['field'] as String,
    value: j['value'] as Object,
    modelInput: j['use'] == 'model_input',
    unit: j['unit'] as String?,
    date: j['date'] == null ? null : DateTime.parse(j['date'] as String),
    dateFromLine: j['date_basis'] == 'line',
    sourceText: j['source_text'] as String,
    page: j['page'] as int,
    section: j['section'] as String?,
    confidence: j['confidence'] as String? ?? 'high',
    method: j['method'] as String? ?? 'parser',
  );
}

/// The server's answer for one document.
class DocumentExtraction {
  const DocumentExtraction({
    required this.status,
    this.candidates = const [],
    this.notices = const [],
    this.providerStatus = 'not_requested',
  });

  /// found, nothing_found or unreadable.
  final String status;
  final List<DocumentCandidate> candidates;

  /// other_person_skipped, multiple_patients, conflicting_values, language_not_supported,
  /// partly_unreadable.
  final List<String> notices;

  /// not_requested, consent_required, used or unavailable.
  final String providerStatus;

  static DocumentExtraction fromJson(Object? json) {
    if (json is! Map || json['status'] is! String || json['candidates'] is! List) {
      throw const DocumentExtractUnavailable();
    }
    return DocumentExtraction(
      status: json['status'] as String,
      candidates: [
        for (final c in json['candidates'] as List) DocumentCandidate.fromJson(Map<String, dynamic>.from(c as Map)),
      ],
      notices: [for (final n in (json['notices'] as List? ?? const [])) '$n'],
      providerStatus: json['provider_status'] as String? ?? 'not_requested',
    );
  }
}

/// The server could not be reached or answered unexpectedly: retry, or talk/type instead.
class DocumentExtractUnavailable implements Exception {
  const DocumentExtractUnavailable();
}

/// The server refused the text, with a plain reason to show.
class DocumentExtractRejected implements Exception {
  const DocumentExtractRejected(this.message);
  final String message;
}

abstract class DocumentExtractor {
  /// Sends only recognised text. [outsideAiConsent] is `{providerId: true}` after the person's yes
  /// to that provider for this document, else empty.
  Future<DocumentExtraction> extract(List<String> pages, {Map<String, bool> outsideAiConsent = const {}});
}

/// POST /api/documents/extract. Stateless: the server keeps nothing.
class HttpDocumentExtractor implements DocumentExtractor {
  HttpDocumentExtractor({http.Client? client, ApiBase? base})
    : _client = client ?? BackendHttpClient(),
      base = base ?? ApiBase(apiBaseUrl, client);

  final http.Client _client;
  final ApiBase base;

  @override
  Future<DocumentExtraction> extract(List<String> pages, {Map<String, bool> outsideAiConsent = const {}}) async {
    try {
      final url = await base.url();
      final r = await _client
          .post(
            Uri.parse('$url/api/documents/extract'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'pages': pages, 'outside_ai_consent': outsideAiConsent}),
          )
          .timeout(const Duration(seconds: 30));
      if (r.statusCode == 200) return DocumentExtraction.fromJson(jsonDecode(utf8.decode(r.bodyBytes)));
      final reason = _reason(r.bodyBytes);
      if (r.statusCode >= 400 && r.statusCode < 500 && r.statusCode != 429 && reason != null) {
        throw DocumentExtractRejected(reason);
      }
      throw const DocumentExtractUnavailable();
    } on DocumentExtractRejected {
      rethrow;
    } catch (_) {
      base.forget();
      throw const DocumentExtractUnavailable();
    }
  }

  static String? _reason(List<int> body) {
    try {
      final json = jsonDecode(utf8.decode(body));
      final message = json is Map ? json['message'] : null;
      return message is String && message.trim().isNotEmpty ? message.trim() : null;
    } catch (_) {
      return null;
    }
  }
}
