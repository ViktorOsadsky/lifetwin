import 'package:flutter/material.dart';

import '../experiment/experiment_copy.dart';
import '../experiment/widgets/widgets.dart';
import '../twin/profile_mapping.dart';
import '../ui/theme.dart';
import '../ui/widgets/rough_guide_badge.dart';
import '../widgets/whole_word_text.dart';
import 'outlook_change.dart';

/// "Outlook updated" (Z-17, Z-33, Z-34): how the outlook moved after a confirmed week.
///
/// "Up a little" with "Less than 1 more in 100 still alive, at 5 years" and the contract caption
/// "Modeled difference between profiles"; from 1 in 100 the last-week and this-week bear arrays.
/// The one-decimal figures sit behind "Exact numbers". With no number for either week it shows
/// "No number yet" and what is still needed. "Linked, not proven." and "Why?" are always there.
class OutlookChangeCard extends StatefulWidget {
  const OutlookChangeCard({super.key, required this.change, this.onTellMochi});

  final OutlookChange change;

  /// "Tell Mochi", in the no-number state.
  final VoidCallback? onTellMochi;

  @override
  State<OutlookChangeCard> createState() => _OutlookChangeCardState();
}

class _OutlookChangeCardState extends State<OutlookChangeCard> {
  bool _caveat = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.change;
    final good = c.kind == OutlookChangeKind.up || c.kind == OutlookChangeKind.moreBig;
    if (!c.hasNumber) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NoNumberBox(icon: Icons.info_outline_rounded, title: c.headline, body: c.subline),
          if (widget.onTellMochi != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: widget.onTellMochi,
              child: Text('Tell Mochi', style: LtText.body(weight: FontWeight.w700)),
            ),
          ],
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: good ? LtColors.mintTint : LtColors.paper,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: LtColors.control, width: LtBorders.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Semantics(
                header: true,
                child: Text(
                  c.headline,
                  style: LtText.display(28, color: good ? const Color(0xFF17594A) : LtColors.ink),
                ),
              ),
              if (c.caveat != null)
                RoughGuideBadge(caveat: c.caveat!, expanded: _caveat, onTap: () => setState(() => _caveat = !_caveat)),
            ],
          ),
          if (_caveat && c.caveat != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: WholeWordText(c.caveat!, style: LtText.body()),
            ),
          WholeWordText(c.subline!, style: LtText.body()),
          if (c.weeksVary) WholeWordText('Weeks go up and down.', style: LtText.body(color: LtColors.secondary)),
          const SizedBox(height: 4),
          WholeWordText(ExperimentCopy.subtitle, style: LtText.body(color: LtColors.secondary)),
          if (c.showsArrays) ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 12,
              spacing: 8,
              children: [
                _Week(
                  label: 'Last week',
                  child: BearArray(today: c.lastWeek!, semanticLabel: 'Last week: about ${c.lastWeek} of 100.'),
                ),
                _Week(
                  label: 'This week',
                  child: BearArray(
                    today: c.lastWeek!,
                    gained: c.gap!,
                    mintGain: true,
                    semanticLabel: 'This week: about ${c.thisWeek} of 100, ${c.gap} more in mint.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            WholeWordText('${c.gap} more', style: LtText.body(weight: FontWeight.w700)),
            WholeWordText(
              'Each bear is 1 of 100 people like you. Brown or mint = still alive at 5 years. Outline = not.',
              style: LtText.body(color: LtColors.secondary),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(ExperimentCopy.linked, style: LtText.body(weight: FontWeight.w700)),
              ),
              InfoButton(
                label: 'Why linked, not proven?',
                onTap: () => showInfoSheet(
                  context,
                  title: 'Linked, not proven',
                  body: 'Difference between two model profiles, not the benefit of changing a habit.',
                ),
              ),
              Text(
                ExperimentCopy.why,
                style: LtText.body(weight: FontWeight.w700)
                    .copyWith(decoration: TextDecoration.underline, decorationThickness: 2),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => showInfoSheet(context, title: 'Exact numbers', body: c.exact!),
              child: Text(
                'Exact numbers',
                style: LtText.body(weight: FontWeight.w700)
                    .copyWith(decoration: TextDecoration.underline, decorationThickness: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Week extends StatelessWidget {
  const _Week({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: BearArray.side,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WholeWordText(label, style: LtText.body(weight: FontWeight.w700)),
        const SizedBox(height: 4),
        child,
      ],
    ),
  );
}

/// "Your confirmed week": each confirmed answer in words with where it came from. From the
/// phone's check-in these are all "You said".
class ConfirmedWeek extends StatelessWidget {
  const ConfirmedWeek({super.key, required this.confirmed});
  final Map<String, dynamic> confirmed;

  static String? line(String field, Object? v) {
    if (v is! num) return null;
    String n(num x) => x == x.roundToDouble() ? '${x.round()}' : x.toStringAsFixed(1);
    return switch (field) {
      'sleep_hours' => 'Sleep ${n(v)} hours',
      'exercise_minutes_weekly' => 'Exercise ${n(v)} min',
      'alcohol_drinks_weekly' => 'Drinks ${n(v)}',
      'weight_kg' => 'Weight ${n(v)} kg',
      'systolic_bp' => 'Blood pressure top number ${n(v)}',
      'diastolic_bp' => 'Blood pressure bottom number ${n(v)}',
      _ => modelInputLabels.containsKey(field) ? null : null,
    };
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final e in confirmed.entries)
        if (line(e.key, e.value) case final text?)
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE9DFD0))),
            ),
            child: WholeWordText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: text,
                    style: LtText.body(weight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' · You said',
                    style: LtText.body(color: LtColors.secondary),
                  ),
                ],
              ),
            ),
          ),
    ],
  );
}
