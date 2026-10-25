import 'package:flutter/material.dart';

import '../widgets/whole_word_text.dart';

import '../ui/theme.dart';
import '../ui/widgets/widgets.dart';
import 'models.dart';
import 'widgets.dart';

class HomeWellnessPanel extends StatelessWidget {
  const HomeWellnessPanel({
    super.key,
    required this.snapshot,
    required this.now,
    required this.onEstimate,
    this.onCheckIn,
    this.onHistory,
    this.compact = false,
  });
  final bool compact;
  final WellnessSnapshot snapshot;
  final DateTime now;

  /// Existing openCheckIn / CheckinScheduler entry point; never a second flow.
  final VoidCallback? onCheckIn;
  final VoidCallback? onHistory;
  final VoidCallback onEstimate;

  @override
  Widget build(BuildContext context) => WellnessCard(
    padding: EdgeInsets.all(compact ? 14 : 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) ...[
          WholeWordText(
            'A little care, every day',
            style: LtText.body(size: 15),
          ),
          const SizedBox(height: 6),
        ],
        WholeWordText(
          'Your health score',
          style: LtText.display(compact ? 20 : 25),
        ),
        const SizedBox(height: 8),
        if (snapshot.displayScore case final score?)
          Semantics(
            label: 'Health score $score out of 100',
            child: WholeWordText('$score / 100', style: LtText.display(38)),
          )
        else
          WholeWordText(
            'Getting to know you',
            style: LtText.display(compact ? 24 : 26),
          ),
        SizedBox(height: compact ? 10 : 16),
        SevenDayTrend(
          days: lastSevenDays(snapshot.days, now),
          compact: compact,
        ),
        if (onCheckIn != null) ...[
          const SizedBox(height: 16),
          LipButton(
            label: 'Check in',
            icon: Icons.chat_bubble_outline_rounded,
            onTap: onCheckIn,
          ),
        ],
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (onHistory != null)
              TextButton(
                onPressed: onHistory,
                child: const WholeWordText('My history'),
              ),
            TextButton(
              onPressed: onEstimate,
              child: const WholeWordText('See your estimate'),
            ),
          ],
        ),
      ],
    ),
  );
}

class SevenDayTrend extends StatelessWidget {
  const SevenDayTrend({super.key, required this.days, this.compact = false});
  final List<WellnessDay> days;
  final bool compact;
  static const _weekday = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      WholeWordText(
        'Your last 7 days',
        style: LtText.body(size: compact ? 14 : 18, weight: FontWeight.w700),
      ),
      SizedBox(height: compact ? 4 : 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Semantics(
                label:
                    '${day.date.month}/${day.date.day}: ${switch (validHealthScore(day.healthScore)) {
                      final score? => 'score $score',
                      _ => day.values.isEmpty && !day.logged ? 'not recorded' : 'check-in recorded, no score yet',
                    }}',
                excludeSemantics: true,
                child: Column(
                  children: [
                    Container(
                      height: compact ? 22 : 48,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: switch (validHealthScore(day.healthScore)) {
                          final score? => 8 + (compact ? 14 : 40) * score / 100,
                          _ => 8,
                        },
                        width: 14,
                        decoration: BoxDecoration(
                          color:
                              validHealthScore(day.healthScore) != null ||
                                  (day.logged || day.values.isNotEmpty)
                              ? LtColors.mint
                              : LtColors.trackOff,
                          border: Border.all(color: LtColors.control),
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                    SizedBox(height: compact ? 3 : 7),
                    WholeWordText(
                      _weekday[day.date.weekday - 1],
                      style: LtText.body(size: 15),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (!compact)
        WholeWordText(
          'Missing days stay unknown.',
          style: LtText.body(size: 15),
        ),
    ],
  );
}
