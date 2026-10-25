import 'package:flutter/material.dart';

import '../health/readback.dart' show usesImperial;
import '../ui/theme.dart';
import '../widgets/whole_word_text.dart';
import '../ui/widgets/widgets.dart';
import '../twin/twin_model.dart' show TwinAssessment;
import 'forecast_client.dart';
import 'profile_labels.dart';

/// V-9 "See what shaped it": the person's own curve from the on-device model, the
/// confirmed answers with their source, and the limits. Every number comes from the
/// model; nothing is filled in.
class OutlookDetailScreen extends StatelessWidget {
  const OutlookDetailScreen({
    super.key,
    required this.forecast,
    required this.profile,
    required this.onAddAnswer,
    this.healthKeys = const {},
    this.documentKeys = const {},
  });

  final Forecast forecast;
  final Map<String, dynamic> profile;
  final Set<String> healthKeys;
  final Set<String> documentKeys;
  final VoidCallback onAddAnswer;

  @override
  Widget build(BuildContext context) {
    final f = forecast;
    final imperial = usesImperial(WidgetsBinding.instance.platformDispatcher.locale.countryCode);
    final answers = profileLabels(profile, imperial: imperial);
    final years = f.maxHorizonYears;
    return ModeScaffold(
      mode: LtMode.fortune,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: RoundBackButton(label: 'Back to your look ahead', onTap: () => Navigator.of(context).pop()),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Semantics(
              header: true,
              child: WholeWordText('Your look ahead', style: LtText.display(32, color: LtColors.cream)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
            child: WholeWordText(
              'Your chances over the next $years ${years == 1 ? 'year' : 'years'}',
              style: LtText.body(color: LtColors.cream),
            ),
          ),
          _Section(
            title: TwinAssessment.survivalTitle,
            children: [
              SurvivalCurve(curve: f.curve, markers: f.survival, maxYears: years),
              const SizedBox(height: 8),
              WholeWordText('Out of 100 people with answers like yours', style: LtText.body(color: LtColors.cream)),
            ],
          ),
          _Section(
            title: 'Built from your answers',
            children: [
              if (answers.isEmpty) WholeWordText('No answers yet.', style: LtText.body(color: LtColors.cream)),
              for (final (key, label) in answers)
                _Row(
                  label: label,
                  source: healthKeys.contains(key) || (key == 'systolic_bp' && healthKeys.contains('diastolic_bp'))
                      ? 'Apple Health'
                      : documentKeys.contains(key)
                      ? 'From a document'
                      : 'you told me',
                  icon: healthKeys.contains(key)
                      ? Icons.favorite_border_rounded
                      : documentKeys.contains(key)
                      ? Icons.description_outlined
                      : Icons.chat_bubble_outline_rounded,
                ),
            ],
          ),
          _Section(
            title: 'Limits',
            children: [
              for (final (icon, line) in [
                (Icons.schedule_rounded, 'Looks $years ${years == 1 ? 'year' : 'years'} ahead at most'),
                (Icons.flag_outlined, 'A US health survey'),
                (Icons.link_rounded, 'Links, not causes'),
                (Icons.event_busy_rounded, 'Not a promise, not a date'),
                for (final l in f.limitations) (Icons.info_outline_rounded, l),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 22, color: LtColors.gold),
                      const SizedBox(width: 10),
                      Expanded(
                        child: WholeWordText(line, style: LtText.body(color: LtColors.cream)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              WholeWordText('Model ${f.modelVersion}', style: LtText.body(size: 15, color: LtColors.cream)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Sheet(
        night: true,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Semantics(
                header: true,
                child: WholeWordText(title!, style: LtText.display(22, color: LtColors.gold)),
              ),
              const SizedBox(height: 12),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.source, required this.icon});
  final String label;
  final String source;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: LtColors.cream.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LtColors.cream.withValues(alpha: 0.28), width: LtBorders.container),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        children: [
          WholeWordText(
            label,
            style: LtText.body(size: 18, color: LtColors.cream, weight: FontWeight.w700),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: LtColors.gold,
              ),
              const SizedBox(width: 6),
              WholeWordText(source, style: LtText.body(color: LtColors.gold)),
            ],
          ),
        ],
      ),
    );
  }
}
