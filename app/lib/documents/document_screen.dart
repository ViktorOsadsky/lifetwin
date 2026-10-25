import 'package:flutter/material.dart';

import '../checkin/consents.dart' show AiProvider;
import '../health/readback.dart' show usesImperial;
import '../ui/theme.dart';
import '../twin/history_log.dart' show valueText;
import '../ui/widgets/widgets.dart';
import '../widgets/whole_word_text.dart';
import '../wellness/widgets.dart';
import 'document_extract.dart';
import 'document_ocr.dart';
import 'document_upload.dart';

/// Painted upload flow backed by the shared OCR and confirmation engine.
class DocumentUploadScreen extends StatefulWidget {
  const DocumentUploadScreen({
    super.key,
    required this.service,
    required this.onDone,
    this.now,
    this.confirmedValues = const {},
    this.provider,
  });

  final DocumentUploadService service;

  /// Called once with what was confirmed (possibly nothing). Values confirmed earlier,
  /// elsewhere, are never touched by this screen.
  final void Function(DocumentImportResult result) onDone;
  final DateTime Function()? now;
  final Map<String, dynamic> confirmedValues;

  /// The outside AI provider from `/api/capabilities`. Null or not configured: the question is never asked.
  final AiProvider? provider;

  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

enum _Step { intro, reading, failed, muse, aboutYou, confirm, done }

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  _Step _step = _Step.intro;
  DocumentReading? _reading;
  DocumentConfirmation? _confirm;
  bool _locked = false;
  bool _finished = false;
  int _request = 0;

  DateTime get _now => (widget.now ?? DateTime.now)();
  bool get _imperial => usesImperial(
    WidgetsBinding.instance.platformDispatcher.locale.countryCode,
  );

  @override
  void dispose() {
    widget.service.discard();
    super.dispose();
  }

  Future<void> _read(DocumentSource source) async {
    final request = ++_request;
    setState(() => _step = _Step.reading);
    final reading = await widget.service.read(source);
    if (request == _request) _show(reading);
  }

  Future<void> _museAnswer(bool yes) async {
    if (!yes) {
      widget.service.discard();
      return _show(_reading!, askedMuse: true);
    }
    final provider = widget.provider;
    if (provider == null) return;
    final request = ++_request;
    setState(() => _step = _Step.reading);
    final reading = await widget.service.retryWithMuse(provider.id);
    if (request == _request) _show(reading, askedMuse: true);
  }

  void _show(DocumentReading r, {bool askedMuse = false}) {
    if (!mounted) return;
    if (r.museCouldHelp && !askedMuse && widget.provider?.configured != true) {
      widget.service.discard();
    }
    setState(() {
      _reading = r;
      if (r.status == DocumentReadStatus.cancelled) {
        _step = _Step.intro;
      } else if (r.museCouldHelp &&
          !askedMuse &&
          widget.provider?.configured == true) {
        _step = _Step.muse;
      } else if (r.candidates.isEmpty) {
        _step = _Step.failed;
      } else {
        _confirm = DocumentConfirmation(r.candidates, notices: r.notices);
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

  void _stop() {
    _request++;
    widget.service.discard();
    setState(() => _step = _Step.intro);
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onDone(_confirm?.result ?? const DocumentImportResult());
  }

  @override
  Widget build(BuildContext context) {
    final page = switch (_step) {
      _Step.intro => _page(
        'Upload a health document?',
        'A document can save a few questions. The photo is read on your phone; only recognized words go to LifeTwin to find your numbers.',
        [
          ('Scan a paper', () => _read(DocumentSource.camera)),
          ('Choose a photo', () => _read(DocumentSource.photos)),
          ('Choose a PDF', () => _read(DocumentSource.pdf)),
          ("No thanks, I'll tell you instead", _finish),
        ],
      ),
      _Step.reading => _page(
        'Reading your document…',
        'One moment. Your photo stays on your phone.',
        [('Stop reading', _stop)],
        busy: true,
      ),
      _Step.failed => _page(_failureTitle(_reading!), _failureBody(_reading!), [
        ('Try another document', () => setState(() => _step = _Step.intro)),
        ('Tell me instead', _finish),
      ]),
      _Step.muse => _page(
        'Some lines were hard to read',
        '${widget.provider!.displayName} can help find your numbers. It gets the words, never the photo. Just this document.',
        [
          ('Yes, just this document', () => _museAnswer(true)),
          ('No thanks', () => _museAnswer(false)),
        ],
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
      _Step.done => _page('Thank you', _doneBody(), [
        ('Continue', _finish),
      ], back: _backFromDone),
    };
    return page;
  }

  Widget _confirmPage() {
    final c = _confirm!.current;
    if (c == null) {
      return _page('Thank you', _doneBody(), [('Continue', _finish)]);
    }
    final proposed = DocumentImportResult(confirmed: [c]).profileValues;
    final field = proposed.keys.firstOrNull;
    final saved = field == null ? null : widget.confirmedValues[field];
    if (saved != null && saved != proposed[field]) {
      return _page(
        'Two different answers',
        '${documentReadBack(c, imperial: _imperial, now: _now)}\n\nYou previously confirmed ${valueText(field!, saved)}. Keep that answer or talk it over with Mochi.',
        [
          (
            'Talk it over with Mochi',
            () {
              _confirm!.answer(false);
              _finish();
            },
          ),
          ('Keep what I said', () => _tap(() => _confirm!.answer(false))),
        ],
        quote: c.sourceText,
        after: () {
          if (_confirm!.done) _step = _Step.done;
        },
      );
    }
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
    if (_confirm!.aboutYou == false) {
      return "I won't use it. I'll ask you instead.";
    }
    if (r.confirmed.isEmpty) {
      return "I won't use any of it. I'll ask you instead.";
    }
    final n = r.confirmed.length;
    return 'You checked $n ${n == 1 ? 'answer' : 'answers'}. I will ask you about anything else I still need.'
        '${r.notes.isEmpty ? '' : ' Extra readings are saved in your history only.'}';
  }

  static String _failureTitle(DocumentReading r) => switch (r.status) {
    DocumentReadStatus.notEnglish =>
      'I can only read English documents for now',
    DocumentReadStatus.multiplePatients =>
      'This has more than one person in it',
    DocumentReadStatus.tooLarge => 'That file is too big',
    DocumentReadStatus.passwordProtected => 'That PDF is locked',
    DocumentReadStatus.unsupported => "I can't open that kind of file",
    DocumentReadStatus.cameraUnavailable => "The camera isn't available",
    DocumentReadStatus.serverUnavailable => "I couldn't read it right now",
    DocumentReadStatus.nothingFound => "I didn't find any answers in it",
    _ => "I couldn't read that",
  };

  static String _failureBody(DocumentReading r) => switch (r.status) {
    DocumentReadStatus.multiplePatients =>
      'Please choose a document with only your own records.',
    DocumentReadStatus.tooLarge =>
      'Please choose a file under 20 megabytes, or take a photo of the page.',
    DocumentReadStatus.passwordProtected =>
      'Please choose an unlocked copy, or take a photo of the page.',
    DocumentReadStatus.cameraUnavailable =>
      'You can choose a photo or a PDF instead.',
    DocumentReadStatus.serverUnavailable =>
      'Please try again in a moment, or tell me the answers yourself.',
    DocumentReadStatus.rejected => r.message ?? 'Please try another document.',
    DocumentReadStatus.unreadable => 'Try a photo on a flat surface in good light, with the whole page in view. Handwriting is hard for me to read.',
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
    return WellnessPage(
      key: ValueKey('document-${_step.name}-${_confirm?.index ?? 0}'),
      title: title,
      onBack: back ?? () => Navigator.of(context).maybePop(),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MochiMessage(message: body, compact: true),
            if (quote != null)
              WellnessCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WholeWordText(
                      'From your document:',
                      style: LtText.body(weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    WholeWordText(quote, style: LtText.body()),
                  ],
                ),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Reading your document',
                  ),
                ),
              ),
            for (var i = 0; i < buttons.length; i++) ...[
              const SizedBox(height: 12),
              if (i == 0 && !busy)
                LipButton(
                  label: buttons[i].$1,
                  onTap: () {
                    buttons[i].$2();
                    if (after != null) setState(after);
                  },
                )
              else
                LinkButton(
                  label: buttons[i].$1,
                  onTap: () {
                    buttons[i].$2();
                    if (after != null) setState(after);
                  },
                ),
            ],
            if (back != null) LinkButton(label: 'Go back', onTap: back),
          ],
        ),
      ],
    );
  }
}

/// The real service: Vision on the phone, the LifeTwin server for the text.
DocumentUploadService liveDocumentService({DocumentExtractor? extractor}) =>
    DocumentUploadService(
      ocr: const ChannelDocumentOcr(),
      extractor: extractor ?? HttpDocumentExtractor(),
    );
