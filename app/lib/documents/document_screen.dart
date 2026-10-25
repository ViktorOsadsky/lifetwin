import 'package:flutter/material.dart';

import '../health/readback.dart' show usesImperial;
import 'document_extract.dart';
import 'document_ocr.dart';
import 'document_upload.dart';

/// Barebones upload screen: the working flow and wording, not the final look
/// (a separate UI session draws it; see docs/document-upload.md).
class DocumentUploadScreen extends StatefulWidget {
  const DocumentUploadScreen({super.key, required this.service, required this.onDone, this.now});

  final DocumentUploadService service;

  /// Called once with what was confirmed (possibly nothing). Values confirmed earlier,
  /// elsewhere, are never touched by this screen.
  final void Function(DocumentImportResult result) onDone;
  final DateTime Function()? now;

  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

enum _Step { intro, reading, failed, muse, aboutYou, confirm, done }

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  _Step _step = _Step.intro;
  DocumentReading? _reading;
  DocumentConfirmation? _confirm;
  bool _locked = false;

  DateTime get _now => (widget.now ?? DateTime.now)();
  bool get _imperial => usesImperial(WidgetsBinding.instance.platformDispatcher.locale.countryCode);

  @override
  void dispose() {
    widget.service.discard();
    super.dispose();
  }

  Future<void> _read(DocumentSource source) async {
    setState(() => _step = _Step.reading);
    _show(await widget.service.read(source));
  }

  Future<void> _museAnswer(bool yes) async {
    if (!yes) {
      widget.service.discard();
      return _show(_reading!, askedMuse: true);
    }
    setState(() => _step = _Step.reading);
    _show(await widget.service.retryWithMuse(), askedMuse: true);
  }

  void _show(DocumentReading r, {bool askedMuse = false}) {
    if (!mounted) return;
    setState(() {
      _reading = r;
      if (r.status == DocumentReadStatus.cancelled) {
        _step = _Step.intro;
      } else if (r.museCouldHelp && !askedMuse) {
        _step = _Step.muse;
      } else if (r.candidates.isEmpty) {
        _step = _Step.failed;
      } else {
        _confirm = DocumentConfirmation(r.candidates);
        _step = _Step.aboutYou;
      }
    });
  }

  /// Ignores a second tap (a tremor double-tap) so it can't answer the next question.
  void _tap(VoidCallback action) {
    if (_locked) return;
    _locked = true;
    Future.delayed(const Duration(milliseconds: 700), () => _locked = false);
    setState(action);
  }

  void _finish() => widget.onDone(_confirm?.result ?? const DocumentImportResult());

  @override
  Widget build(BuildContext context) {
    final page = switch (_step) {
      _Step.intro => _page(
        'Upload a health document?',
        'A visit summary, hospital discharge paper, lab report or pharmacy list can answer some questions for you.\n\n'
            'The words are read on your phone. Only the words are sent to LifeTwin to find the numbers, then thrown away. '
            "Nothing is kept unless you say it's right.",
        [
          ('Scan a paper', () => _read(DocumentSource.camera)),
          ('Choose a photo', () => _read(DocumentSource.photos)),
          ('Choose a PDF', () => _read(DocumentSource.pdf)),
          ("No thanks, I'll tell you instead", _finish),
        ],
      ),
      _Step.reading => _page('Reading your document…', 'This takes a few seconds.', const [], busy: true),
      _Step.failed => _page(_failureTitle(_reading!), _failureBody(_reading!), [
        ('Try another document', () => setState(() => _step = _Step.intro)),
        ('Tell me instead', _finish),
      ]),
      _Step.muse => _page(
        'Some lines were hard to read',
        'May Muse by Meta, an AI service, read the words from your document to help? '
            'Names and other details that identify you are removed first. It is off unless you say yes.',
        [('Yes, let Muse by Meta help', () => _museAnswer(true)), ('No thanks', () => _museAnswer(false))],
      ),
      _Step.aboutYou => _page(
        'Is this document about you?',
        _reading!.truncated
            ? 'I read the first 10 pages. Is this your own document, not someone else\'s?'
            : "Is this your own document, not someone else's?",
        [
          ('Yes, it is mine', () => _tap(() => _confirm!.answerAboutYou(true))),
          ("No, it isn't", () => _tap(() => _confirm!.answerAboutYou(false))),
        ],
        after: () => _step = _confirm!.done ? _Step.done : _Step.confirm,
      ),
      _Step.confirm => _confirmPage(),
      _Step.done => _page('Thank you', _doneBody(), [('Continue', _finish)], back: _backFromDone),
    };
    return Scaffold(body: SafeArea(child: page));
  }

  Widget _confirmPage() {
    final c = _confirm!.current;
    if (c == null) return _page('Thank you', _doneBody(), [('Continue', _finish)]);
    return _page(
      'Question ${_confirm!.index + 1} of ${_confirm!.candidates.length}',
      documentReadBack(c, imperial: _imperial, now: _now),
      [
        ("Yes, that's right", () => _tap(() => _confirm!.answer(true))),
        ("No, that's not right", () => _tap(() => _confirm!.answer(false))),
      ],
      quote: c.sourceText,
      back: () => setState(() {
        _confirm!.back();
        if (_confirm!.aboutYou == null) _step = _Step.aboutYou;
      }),
      after: () {
        if (_confirm!.done) _step = _Step.done;
      },
    );
  }

  void _backFromDone() => setState(() {
    _confirm!.back();
    _step = _confirm!.aboutYou == null ? _Step.aboutYou : _Step.confirm;
  });

  String _doneBody() {
    final r = _confirm!.result;
    if (_confirm!.aboutYou == false) return "I won't use it. I'll ask you instead.";
    if (r.confirmed.isEmpty) return "I won't use any of it. I'll ask you instead.";
    final n = r.confirmed.length;
    return 'You checked $n ${n == 1 ? 'answer' : 'answers'}. I will ask you about anything else I still need.';
  }

  static String _failureTitle(DocumentReading r) => switch (r.status) {
    DocumentReadStatus.notEnglish => 'I can only read English documents for now',
    DocumentReadStatus.multiplePatients => 'This has more than one person in it',
    DocumentReadStatus.tooLarge => 'That file is too big',
    DocumentReadStatus.passwordProtected => 'That PDF is locked',
    DocumentReadStatus.unsupported => "I can't open that kind of file",
    DocumentReadStatus.cameraUnavailable => "The camera isn't available",
    DocumentReadStatus.serverUnavailable => "I couldn't read it right now",
    DocumentReadStatus.nothingFound => "I didn't find any answers in it",
    _ => "I couldn't read that",
  };

  static String _failureBody(DocumentReading r) => switch (r.status) {
    DocumentReadStatus.multiplePatients => 'Please choose a document with only your own records.',
    DocumentReadStatus.tooLarge => 'Please choose a file under 20 megabytes, or take a photo of the page.',
    DocumentReadStatus.passwordProtected => 'Please choose an unlocked copy, or take a photo of the page.',
    DocumentReadStatus.cameraUnavailable => 'You can choose a photo or a PDF instead.',
    DocumentReadStatus.serverUnavailable => 'Please try again in a moment, or tell me the answers yourself.',
    DocumentReadStatus.rejected => r.message ?? 'Please try another document.',
    DocumentReadStatus.unreadable =>
      'Try a photo on a flat surface in good light, with the whole page in view. Handwriting is hard for me to read.',
    _ => 'You can try another document, or tell me the answers yourself.',
  };

  Widget _page(
    String title,
    String body,
    List<(String, VoidCallback)> buttons, {
    bool busy = false,
    String? quote,
    VoidCallback? back,
    VoidCallback? after,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text(title, style: theme.textTheme.headlineMedium)),
                  const SizedBox(height: 16),
                  Semantics(liveRegion: true, child: Text(body, style: const TextStyle(fontSize: 24, height: 1.3))),
                  if (quote != null) ...[
                    const SizedBox(height: 16),
                    Text('From your document:', style: theme.textTheme.titleMedium),
                    Text(quote, style: const TextStyle(fontSize: 22, fontStyle: FontStyle.italic)),
                  ],
                  if (busy) const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
                ],
              ),
            ),
          ),
          for (final (label, onTap) in buttons)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                height: 72,
                child: FilledButton(
                  onPressed: () {
                    onTap();
                    if (after != null) setState(after);
                  },
                  child: Text(label, style: const TextStyle(fontSize: 22), textAlign: TextAlign.center),
                ),
              ),
            ),
          if (back != null)
            TextButton.icon(
              onPressed: back,
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Go back', style: TextStyle(fontSize: 20)),
            ),
        ],
      ),
    );
  }
}

/// The real service: Vision on the phone, the LifeTwin server for the text.
DocumentUploadService liveDocumentService({DocumentExtractor? extractor}) =>
    DocumentUploadService(ocr: const ChannelDocumentOcr(), extractor: extractor ?? HttpDocumentExtractor());
