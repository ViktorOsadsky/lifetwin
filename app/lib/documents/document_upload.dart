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

  /// Muse by Meta could read lines the parser could not, if the person agrees.
  final bool museCouldHelp;

  /// The server's own words, for [DocumentReadStatus.rejected].
  final String? message;
}

/// Pick or capture → recognise on the phone → send only the text → candidates.
///
/// The recognised text is held in memory only: until the server answers, or, when Muse
/// could help, until the person answers that question. Then it is dropped.
class DocumentUploadService {
  DocumentUploadService({required this.ocr, required this.extractor});

  final DocumentOcr ocr;
  final DocumentExtractor extractor;

  List<String>? _text;
  bool _truncated = false;
  int _generation = 0;

  /// True while text waits for the Muse question.
  bool get holdingText => _text != null;

  Future<DocumentReading> read(DocumentSource source) async {
    discard();
    final generation = _generation;
    final RecognisedDocument doc;
    try {
      doc = await ocr.scan(source);
    } on DocumentReadFailure catch (e) {
      return DocumentReading(switch (e.code) {
        'cancelled' => DocumentReadStatus.cancelled,
        'camera_unavailable' => DocumentReadStatus.cameraUnavailable,
        'too_large' => DocumentReadStatus.tooLarge,
        'password_protected' => DocumentReadStatus.passwordProtected,
        'unsupported_type' => DocumentReadStatus.unsupported,
        _ => DocumentReadStatus.unreadable,
      });
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
    return _extract(outsideAi: false);
  }

  /// The person said yes to Muse by Meta: send the same text again with consent.
  Future<DocumentReading> retryWithMuse() async {
    if (_text == null) return const DocumentReading(DocumentReadStatus.unreadable);
    return _extract(outsideAi: true);
  }

  /// Drops the recognised text.
  void discard() {
    _generation++;
    _text = null;
    _truncated = false;
  }

  Future<DocumentReading> _extract({required bool outsideAi}) async {
    final generation = _generation;
    final text = _text!;
    final truncated = _truncated;
    final DocumentExtraction r;
    try {
      r = await extractor.extract(text, outsideAi: outsideAi);
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
    final museCouldHelp = !outsideAi && r.providerStatus == 'consent_required';
    if (!museCouldHelp) discard();
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
