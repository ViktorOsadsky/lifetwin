import 'package:flutter/material.dart';

import '../checkin/consent_screens.dart' show TrainingLine;
import '../ui/theme.dart';
import '../ui/widgets/widgets.dart';
import '../widgets/whole_word_text.dart';
import 'document_extract.dart';

/// What the app adds to a whole-PDF read: nothing. The PDF itself may hold a name, so the claim
/// is only about what LifeTwin sends along with it.
const pdfSentLine = 'What’s sent: the whole PDF. We don’t add your name or contact details.';

/// The per-document question before a whole PDF goes to [reader]. `true` = send it,
/// `false` = read it on this phone, null = dismissed (nothing is read, nothing is sent).
Future<bool?> showPdfConsentSheet(BuildContext context, PdfReaderInfo reader) => showModalBottomSheet<bool>(
  context: context,
  backgroundColor: Colors.transparent,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _PdfConsentSheet(reader: reader),
);

class _PdfConsentSheet extends StatelessWidget {
  const _PdfConsentSheet({required this.reader});
  final PdfReaderInfo reader;

  @override
  Widget build(BuildContext context) {
    final name = reader.displayName;
    final title = 'Send this PDF to $name?';
    final training = reader.trainingLine;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(LtRadii.panel),
          border: Border.all(color: LtColors.container, width: LtBorders.container),
          boxShadow: LtShadows.soft,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Focus(
                autofocus: true,
                child: Semantics(
                  header: true,
                  focusable: true,
                  child: WholeWordText(title, style: LtText.display(24)),
                ),
              ),
              const SizedBox(height: 8),
              WholeWordText(
                '$name will read this whole document to find your numbers. It may see other details in it too. Just this document.',
                style: LtText.body(),
              ),
              const SizedBox(height: 12),
              Semantics(
                container: true,
                label: pdfSentLine,
                excludeSemantics: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.lock_outline_rounded, size: 20, color: LtColors.ink),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: WholeWordText(pdfSentLine, style: LtText.body(color: LtColors.secondary))),
                  ],
                ),
              ),
              if (training != null) ...[const SizedBox(height: 8), TrainingLine(training)],
              const SizedBox(height: 16),
              LipButton(label: 'Yes, send it', onTap: () => Navigator.of(context).pop(true)),
              const SizedBox(height: 12),
              LipButton(
                label: 'No, read it on this phone',
                kind: LipKind.secondary,
                height: 56,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
