import '../health/readback.dart' show spokenDate, spokenHeight, spokenWeight;
import 'document_extract.dart';
import 'document_ocr.dart';

/// What reading a document came to.
enum DocumentReadStatus {
  found,
  nothingFound,
  unreadable,
  notEnglish,
  multiplePatients,
  cancelled,
  cameraUnavailable,
  tooLarge,
  unsupported,
  passwordProtected,
  serverUnavailable,
  rejected,
}

class DocumentReading {
  const DocumentReading(
    this.status, {
    this.candidates = const [],
    this.notices = const [],
    this.truncated = false,
    this.museCouldHelp = false,
    this.message,
  });

  final DocumentReadStatus status;
  final List<DocumentCandidate> candidates;
  final List<String> notices;

  /// The PDF had more than 10 pages; only the first 10 were read.
  final bool truncated;

  /// The server's outside AI (Claude by Anthropic) could read lines the parser could not, if the
  /// person agrees. The name shown comes from `/api/capabilities`.
  final bool museCouldHelp;

  /// The server's own words, for [DocumentReadStatus.rejected].
  final String? message;
}

/// Pick or capture → recognise on the phone → send only the text → candidates.
///
/// The recognised text is held in memory only: until the server answers, or, when the outside AI
/// could help, until the person answers that question. Then it is dropped.
class DocumentUploadService {
  DocumentUploadService({required this.ocr, required this.extractor, this.pdfPicker, this.pdfReader});

  final DocumentOcr ocr;
  final DocumentExtractor extractor;

  /// Both set: a PDF may go, whole, to the documents provider the server names, after the
  /// person's yes for that document. Otherwise PDFs are read on this phone as before.
  final PdfPicker? pdfPicker;
  final PdfDocumentReader? pdfReader;

  List<String>? _text;
  bool _truncated = false;
  int _generation = 0;
  PickedPdf? _pdf;

  /// True while text waits for the outside-AI question.
  bool get holdingText => _text != null;

  /// True while a picked PDF waits for the "send it?" question.
  bool get holdingPdf => _pdf != null;

  static DocumentReadStatus _failure(String code) => switch (code) {
    'cancelled' => DocumentReadStatus.cancelled,
    'camera_unavailable' => DocumentReadStatus.cameraUnavailable,
    'too_large' => DocumentReadStatus.tooLarge,
    'password_protected' => DocumentReadStatus.passwordProtected,
    'unsupported_type' => DocumentReadStatus.unsupported,
    _ => DocumentReadStatus.unreadable,
  };

  Future<DocumentReading> read(DocumentSource source) async {
    discard();
    final generation = _generation;
    final RecognisedDocument doc;
    try {
      doc = await ocr.scan(source);
    } on DocumentReadFailure catch (e) {
      return DocumentReading(_failure(e.code));
    }
    if (generation != _generation) return const DocumentReading(DocumentReadStatus.cancelled);
    return readText(doc);
  }

  /// The provider that may read whole PDFs, from `/api/capabilities`; null: the phone reads them.
  Future<PdfReaderInfo?> pdfProvider() async {
    final reader = pdfReader;
    if (pdfPicker == null || reader == null) return null;
    try {
      return await reader.info();
    } catch (_) {
      return null;
    }
  }

  /// Picks a PDF and holds it in memory for the question. Null: ask now. Otherwise the reading
  /// (cancelled, locked...), or the phone's own reading when the PDF is over [info]'s limits.
  Future<DocumentReading?> pickPdf(PdfReaderInfo info) async {
    discard();
    final generation = _generation;
    final PickedPdf picked;
    try {
      picked = await pdfPicker!.pickPdf();
    } on DocumentReadFailure catch (e) {
      return DocumentReading(_failure(e.code));
    }
    if (generation != _generation) return const DocumentReading(DocumentReadStatus.cancelled);
    _pdf = picked;
    if (picked.bytes.length > info.maxBytes || picked.pageCount > info.maxPages) return readPdfOnPhone();
    return null;
  }

  /// The person said yes for [provider] (its id from `/api/capabilities`): send the whole PDF,
  /// base64, with consent for that provider only. Not read there: read it on the phone instead.
  Future<DocumentReading> sendPdf(String provider) async {
    final pdf = _pdf;
    final reader = pdfReader;
    if (pdf == null || reader == null) return const DocumentReading(DocumentReadStatus.unreadable);
    final generation = _generation;
    DocumentExtraction? r;
    try {
      r = await reader.readPdf(pdf.bytes, outsideAiConsent: {provider: true});
    } catch (_) {
      r = null;
    }
    if (generation != _generation) return const DocumentReading(DocumentReadStatus.cancelled);
    if (r == null || r.providerStatus == 'consent_required' || r.providerStatus == 'unavailable') {
      return readPdfOnPhone();
    }
    discard();
    return _reading(r, truncated: false, museCouldHelp: false);
  }

  /// No (or the server could not read it): the existing on-device path for the same PDF.
  Future<DocumentReading> readPdfOnPhone() async {
    final pdf = _pdf;
    if (pdf == null) return const DocumentReading(DocumentReadStatus.unreadable);
    _pdf = null;
    final generation = _generation;
    final RecognisedDocument doc;
    try {
      doc = await ocr.recognize(pdf.bytes, pdf: true);
    } on DocumentReadFailure catch (e) {
      return DocumentReading(_failure(e.code));
    }
    if (generation != _generation) return const DocumentReading(DocumentReadStatus.cancelled);
    return readText(doc);
  }

  /// The text path on its own, for [read] and for tests.
  Future<DocumentReading> readText(RecognisedDocument doc) async {
    discard();
    // Nothing worth sending: say so without a network call.
    if (!doc.readable) return const DocumentReading(DocumentReadStatus.unreadable);
    _text = doc.pages;
    _truncated = doc.truncated;
    return _extract(const {});
  }

  /// The person said yes to the outside AI [provider] (its id from `/api/capabilities`):
  /// send the same text again with consent for that provider only.
  Future<DocumentReading> retryWithMuse(String provider) async {
    if (_text == null) return const DocumentReading(DocumentReadStatus.unreadable);
    return _extract({provider: true});
  }

  /// Drops the recognised text and any picked PDF.
  void discard() {
    _generation++;
    _text = null;
    _truncated = false;
    _pdf = null;
  }

  Future<DocumentReading> _extract(Map<String, bool> outsideAiConsent) async {
    final generation = _generation;
    final text = _text!;
    final truncated = _truncated;
    final DocumentExtraction r;
    try {
      r = await extractor.extract(text, outsideAiConsent: outsideAiConsent);
    } on DocumentExtractRejected catch (e) {
      if (generation != _generation) return const DocumentReading(DocumentReadStatus.cancelled);
      discard();
      return DocumentReading(DocumentReadStatus.rejected, message: e.message);
    } on DocumentExtractUnavailable {
      if (generation != _generation) return const DocumentReading(DocumentReadStatus.cancelled);
      // Keep nothing: a retry reads the document again.
      discard();
      return const DocumentReading(DocumentReadStatus.serverUnavailable);
    }
    if (generation != _generation) return const DocumentReading(DocumentReadStatus.cancelled);
    final museCouldHelp = outsideAiConsent.isEmpty && r.providerStatus == 'consent_required';
    if (!museCouldHelp) discard();
    return _reading(r, truncated: truncated, museCouldHelp: museCouldHelp);
  }

  static DocumentReading _reading(DocumentExtraction r, {required bool truncated, required bool museCouldHelp}) {
    final status = r.notices.contains('multiple_patients')
        ? DocumentReadStatus.multiplePatients
        : r.notices.contains('language_not_supported')
        ? DocumentReadStatus.notEnglish
        : switch (r.status) {
            'found' => DocumentReadStatus.found,
            'unreadable' => DocumentReadStatus.unreadable,
            _ => DocumentReadStatus.nothingFound,
          };
    return DocumentReading(
      status,
      candidates: r.candidates,
      notices: r.notices,
      truncated: truncated,
      museCouldHelp: museCouldHelp,
    );
  }
}

/// What the person confirmed. Only [confirmed] values may be used.
class DocumentImportResult {
  const DocumentImportResult({this.confirmed = const [], this.toAsk = const [], this.notices = const []});

  /// The server's notices for this document (for example `conflicting_values`).
  final List<String> notices;

  final List<DocumentCandidate> confirmed;

  /// Model inputs the person said were not right: Mochi asks for them.
  final List<String> toAsk;

  /// Confirmed answers in the conversation profile's names, for the `import` action.
  Map<String, Object> get profileValues => {
    for (final c in confirmed) ?_profileKey[c.field]: c.value,
  };

  /// Confirmed information notes (blood pressure readings, A1c, LDL): never model inputs.
  List<DocumentCandidate> get notes => [
    for (final c in confirmed)
      if (!c.modelInput) c,
  ];

  static const _profileKey = {
    'height_cm': 'height_cm',
    'weight_kg': 'weight_kg',
    'smoking_status': 'smoking_status',
    'hypertension_diagnosed': 'hypertension_diagnosed',
    // Only ever true from a document; absence never becomes false.
    'diabetes_diagnosed': 'diabetes',
  };
}

/// One question at a time: "Is this document about you?", then each candidate.
/// No edits: "No" drops a value and Mochi asks for it instead.
class DocumentConfirmation {
  DocumentConfirmation(this.candidates, {this.notices = const []});

  final List<String> notices;

  final List<DocumentCandidate> candidates;
  bool? aboutYou;
  final _answers = <bool>[];

  int get index => _answers.length;
  bool get done => aboutYou == false || (aboutYou == true && index >= candidates.length);
  DocumentCandidate? get current => aboutYou == true && !done ? candidates[index] : null;

  void answerAboutYou(bool yes) => aboutYou = yes;

  void answer(bool right) {
    if (current == null) return;
    _answers.add(right);
  }

  /// Undoes the last answer, so a mistaken tap is never final.
  void back() {
    if (_answers.isNotEmpty) {
      _answers.removeLast();
    } else {
      aboutYou = null;
    }
  }

  DocumentImportResult get result {
    if (aboutYou != true) return DocumentImportResult(notices: notices);
    final confirmed = <DocumentCandidate>[];
    final toAsk = <String>[];
    for (var i = 0; i < _answers.length; i++) {
      final c = candidates[i];
      if (_answers[i]) {
        confirmed.add(c);
      } else if (c.modelInput && !toAsk.contains(c.field)) {
        toAsk.add(c.field);
      }
    }
    return DocumentImportResult(confirmed: confirmed, toAsk: toAsk, notices: notices);
  }
}

/// The read-back sentence. Old or undated model inputs ask whether they are still right.
String documentReadBack(DocumentCandidate c, {required bool imperial, required DateTime now}) {
  final v = c.value;
  final said = switch (c.field) {
    'height_cm' => 'you are ${spokenHeight(v as num, imperial: imperial)} tall',
    'weight_kg' => 'you weigh about ${spokenWeight(v as num, imperial: imperial)}',
    'smoking_status' => switch (v) {
      'former' => 'you used to smoke and have quit',
      'never' => 'you have never smoked',
      _ => 'you smoke now',
    },
    'diabetes_diagnosed' => 'you have been diagnosed with diabetes',
    'hypertension_diagnosed' => 'you have been diagnosed with high blood pressure',
    'blood_pressure' => 'a blood pressure reading of ${'$v'.replaceFirst('/', ' over ')}',
    'hba1c' => 'an A1c of ${_num(v)} percent. A1c is your average blood sugar over about 3 months',
    'ldl_cholesterol' =>
      'an LDL cholesterol of ${_num(v)} ${c.unit == 'mmol/L' ? 'millimoles per litre' : 'milligrams per decilitre'}',
    _ => '$v',
  };
  final date = c.date;
  final when = date == null ? '' : ' That was ${c.dateFromLine ? 'on' : 'from'} ${spokenDate(date, now)}.';
  if (!c.modelInput) {
    return "Your document shows $said.$when This reading doesn't change your forecast. It is saved in your history only. Is this right?";
  }
  final old = date == null || now.difference(date).inDays > 365;
  return 'Your document says $said.$when ${old ? 'Is it still right today?' : 'Is this right?'}';
}

String _num(Object v) => v is num && v == v.roundToDouble() ? '${v.round()}' : '$v';
