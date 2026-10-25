import 'package:flutter/material.dart';

import '../widgets/whole_word_text.dart';

import '../ui/theme.dart';
import '../ui/widgets/widgets.dart';
import 'models.dart';
import 'widgets.dart';

/// A read-only view of TwinRepository.history({from, to}) and dayLogs.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.days,
    required this.goodWeeks,
    required this.now,
    required this.onBack,
    required this.onTalk,
  });
  final List<WellnessDay> days;
  final int goodWeeks;
  final DateTime now;
  final VoidCallback onBack;
  final VoidCallback onTalk;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int? _range = 7;

  @override
  Widget build(BuildContext context) {
    final today = localDay(widget.now);
    final from = _range == null
        ? null
        : DateTime(today.year, today.month, today.day - _range! + 1);
    final days =
        widget.days
            .where(
              (d) =>
                  !localDay(d.date).isAfter(today) &&
                  (from == null || !localDay(d.date).isBefore(from)),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return WellnessPage(
      title: 'Your history',
      subtitle: 'The things you’ve shared with Mochi.',
      onBack: widget.onBack,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in [
              (7, '7 days'),
              (30, '30 days'),
              (null, 'All time'),
            ])
              ChoiceChip(
                label: WholeWordText(choice.$2),
                selected: _range == choice.$1,
                onSelected: (_) => setState(() => _range = choice.$1),
              ),
          ],
        ),
        const SizedBox(height: 16),
        WellnessCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WholeWordText(
                '${widget.goodWeeks} good ${widget.goodWeeks == 1 ? 'week' : 'weeks'}',
                style: LtText.display(25),
              ),
              const SizedBox(height: 6),
              WholeWordText(
                'Four or more days shared in a Monday–Sunday week. Yours to keep.',
                style: LtText.body(),
              ),
            ],
          ),
        ),
        if (days.isEmpty)
          const MochiMessage(message: 'A fresh page for the things you share.'),
        for (final day in days)
          WellnessCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WholeWordText(
                  MaterialLocalizations.of(context).formatMediumDate(day.date),
                  style: LtText.display(23),
                ),
                if (validHealthScore(day.healthScore) case final score?) ...[
                  const SizedBox(height: 8),
                  WholeWordText(
                    'Health score $score / 100',
                    style: LtText.body(),
                  ),
                ],
                for (final value in day.values)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WholeWordText(
                          '${value.label}: ${value.value}',
                          style: LtText.body(weight: FontWeight.w700),
                        ),
                        WholeWordText(
                          value.provenance,
                          style: LtText.body(size: 15),
                        ),
                        ..._metadata(value),
                      ],
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _detail(day),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const WholeWordText('See this day'),
                ),
              ],
            ),
          ),
        WholeWordText(
          'Need to change something? Talk it through with Mochi.',
          style: LtText.body(),
        ),
        const SizedBox(height: 12),
        LipButton(label: 'Talk with Mochi', onTap: widget.onTalk),
      ],
    );
  }

  Future<void> _detail(WellnessDay day) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (c) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WholeWordText(
            MaterialLocalizations.of(c).formatFullDate(day.date),
            style: LtText.display(26),
          ),
          const SizedBox(height: 16),
          for (final value in day.values)
            WellnessCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WholeWordText(
                    '${value.label}: ${value.value}',
                    style: LtText.body(weight: FontWeight.w700),
                  ),
                  WholeWordText(value.provenance, style: LtText.body(size: 15)),
                  ..._metadata(value),
                ],
              ),
            ),
          WholeWordText(
            'Something wrong? Tell Mochi. Past entries stay read-only.',
            style: LtText.body(),
          ),
          const SizedBox(height: 16),
          LipButton(
            label: 'Change with Mochi',
            onTap: () {
              Navigator.pop(c);
              widget.onTalk();
            },
          ),
          LinkButton(label: 'Back to history', onTap: () => Navigator.pop(c)),
        ],
      ),
    ),
  );
  List<Widget> _metadata(HistoryValue value) => [
    if (value.forDay != null)
      WholeWordText(
        'For ${MaterialLocalizations.of(context).formatMediumDate(value.forDay!)}',
        style: LtText.body(size: 15),
      ),
    if (value.previousValue != null)
      WholeWordText(
        'Previously: ${value.previousValue}',
        style: LtText.body(size: 15),
      ),
    if (value.recordedAt != null)
      WholeWordText(
        'Confirmed at ${value.recordedAt}',
        style: LtText.body(size: 15),
      ),
    if (value.status != null)
      WholeWordText(
        value.status!,
        style: LtText.body(size: 15, weight: FontWeight.w700),
      ),
  ];
}
