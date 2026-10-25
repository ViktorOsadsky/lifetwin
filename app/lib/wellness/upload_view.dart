import 'package:flutter/material.dart';

import '../widgets/whole_word_text.dart';

import '../ui/theme.dart';
import '../ui/widgets/widgets.dart';
import 'widgets.dart';

/// A view of PR #51's DocumentUploadService/DocumentConfirmation state. OCR,
/// extraction, consent scope and confirmation belong to that existing engine.
enum UploadStage {
  choose,
  reading,
  failed,
  museConsent,
  aboutYou,
  readBack,
  conflict,
  done,
}

class DocumentUploadView extends StatelessWidget {
  const DocumentUploadView({
    super.key,
    required this.stage,
    required this.onBack,
    required this.onScan,
    required this.onPhoto,
    required this.onPdf,
    required this.onSkip,
    required this.onYes,
    required this.onNo,
    this.readBack,
    this.source,
    this.sourceDate,
    this.failure,
  });
  final UploadStage stage;
  final VoidCallback onBack;
  final VoidCallback onScan;
  final VoidCallback onPhoto;
  final VoidCallback onPdf;
  final VoidCallback onSkip;

  /// For Muse this is one document only, independent of Personal suggestions.
  final VoidCallback onYes;
  final VoidCallback onNo;
  final String? readBack;
  final String? source;
  final String? sourceDate;
  final String? failure;

  @override
  Widget build(BuildContext context) => WellnessPage(
    title: switch (stage) {
      UploadStage.choose => 'Bring your health notes',
      UploadStage.reading => 'Finding your numbers',
      UploadStage.failed => 'Let’s try another way',
      UploadStage.museConsent => 'A little help?',
      UploadStage.aboutYou => 'Is this yours?',
      UploadStage.readBack => 'Is this right?',
      UploadStage.done => 'Ready to keep going',
      UploadStage.conflict => 'Two different answers',
    },
    onBack: onBack,
    children: switch (stage) {
      UploadStage.choose => [
        const MochiMessage(message: 'A document can save a few questions.'),
        WholeWordText(
          'Take a photo of a health document. The photo is read on your phone; only recognized words go to LifeTwin to find your numbers.',
          style: LtText.body(),
        ),
        const SizedBox(height: 18),
        LipButton(
          label: 'Scan a document',
          icon: Icons.document_scanner_outlined,
          onTap: onScan,
        ),
        const SizedBox(height: 12),
        LipButton(
          label: 'Choose a photo',
          kind: LipKind.secondary,
          icon: Icons.photo_outlined,
          onTap: onPhoto,
        ),
        LinkButton(label: 'Choose a PDF', onTap: onPdf),
        LinkButton(label: 'Tell Mochi instead', onTap: onSkip),
      ],
      UploadStage.reading => [
        const MochiMessage(
          message: 'One moment. Your photo stays on your phone.',
        ),
        const Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Reading your document',
          ),
        ),
        LinkButton(label: 'Stop reading', onTap: onNo),
      ],
      UploadStage.failed => [
        MochiMessage(
          message: failure ?? 'Those words were a little hard to read.',
        ),
        LipButton(label: 'Try another document', onTap: onScan),
        LinkButton(label: 'Tell Mochi instead', onTap: onSkip),
      ],
      UploadStage.museConsent => [
        const MochiMessage(message: 'Muse can help find your numbers.'),
        WellnessCard(
          child: WholeWordText(
            'Muse can help find your numbers. It gets the words, never the photo. Just this document.',
            style: LtText.body(size: 20),
          ),
        ),
        LipButton(label: 'Yes, just this document', onTap: onYes),
        LinkButton(label: 'No thanks', onTap: onNo),
      ],
      UploadStage.aboutYou => [
        const MochiMessage(message: 'Is this document about you?'),
        LipButton(label: 'Yes, it’s mine', onTap: onYes),
        LinkButton(label: 'No, it’s someone else’s', onTap: onNo),
      ],
      UploadStage.readBack => [
        WellnessCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WholeWordText(
                readBack ?? 'No value to confirm yet.',
                style: LtText.display(25),
              ),
              if (sourceDate != null) ...[
                const SizedBox(height: 10),
                WholeWordText(sourceDate!, style: LtText.body()),
              ],
              if (source != null) ...[
                const SizedBox(height: 12),
                WholeWordText(
                  'From your document',
                  style: LtText.body(weight: FontWeight.w700),
                ),
                WholeWordText(source!, style: LtText.body()),
              ],
            ],
          ),
        ),
        LipButton(
          label: 'Yes, that’s right',
          onTap: readBack == null ? null : onYes,
        ),
        LinkButton(label: 'No, ask me instead', onTap: onNo),
      ],
      UploadStage.conflict => [
        const MochiMessage(message: 'This is different from what you told me.'),
        WellnessCard(
          child: WholeWordText(
            readBack ?? 'Let’s check which answer is right for you today.',
            style: LtText.body(),
          ),
        ),
        LipButton(label: 'Talk it over with Mochi', onTap: onSkip),
        LinkButton(label: 'Keep what I said', onTap: onNo),
      ],
      UploadStage.done => [
        const MochiMessage(
          message: 'Only the answers you checked come with us.',
        ),
        LipButton(label: 'Continue', onTap: onSkip),
      ],
    },
  );
}
