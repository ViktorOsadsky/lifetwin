import 'package:flutter/material.dart';

import '../health/readback.dart' show usesImperial;
import '../ui/theme.dart';
import '../widgets/whole_word_text.dart';
import '../ui/widgets/widgets.dart';
import 'forecast_client.dart';
import 'profile_labels.dart';

/// V-9 "See what shaped it": the person's own curve from the response, the
/// confirmed answers with their source, what the model assumed
/// (`filled_in`), and the limits. Every number comes from the response.
class OutlookDetailScreen extends StatelessWidget {
  const OutlookDetailScreen({
    super.key,
    required this.forecast,
    required this.profile,
    required this.onAddAnswer,
    this.healthKeys = const {},
  });

  final Forecast forecast;
  final Map<String, dynamic> profile;
  final Set<String> healthKeys;
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
                      : 'you told me',
                  health: healthKeys.contains(key),
                ),
            ],
          ),
          if (f.filledIn.isNotEmpty)
            _Section(
              title: 'We assumed',
              children: [for (final label in f.filledIn) _Assumed(label: label, onAddAnswer: onAddAnswer)],
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
  const _Row({required this.label, required this.source, required this.health});
  final String label;
  final String source;
  final bool health;

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
                health ? Icons.favorite_border_rounded : Icons.chat_bubble_outline_rounded,
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

class _Assumed extends StatelessWidget {
  const _Assumed({required this.label, required this.onAddAnswer});
  final String label;
  final VoidCallback onAddAnswer;

  @override
  Widget build(BuildContext context) {
    final text = label.isEmpty ? label : label[0].toUpperCase() + label.substring(1);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      decoration: ShapeDecoration(shape: _DashedBorder(color: LtColors.cream.withValues(alpha: 0.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WholeWordText(text, style: LtText.body(color: LtColors.cream)),
          LinkButton(label: 'Add an answer', icon: Icons.add_rounded, color: LtColors.gold, onTap: onAddAnswer),
        ],
      ),
    );
  }
}

/// A dashed 1.5px rounded outline ("we assumed", not confirmed).
class _DashedBorder extends ShapeBorder {
  const _DashedBorder({required this.color});
  final Color color;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  RRect _rrect(Rect rect) => RRect.fromRectAndRadius(rect.deflate(0.75), const Radius.circular(18));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final m in (Path()..addRRect(_rrect(rect))).computeMetrics()) {
      for (double d = 0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, (d + 6).clamp(0, m.length)), paint);
      }
    }
  }

  @override
  ShapeBorder scale(double t) => this;
}
