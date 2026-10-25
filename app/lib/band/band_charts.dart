import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'band_data.dart';

/// Charts for the band panel. Palette (app tokens only, no red/green judgement):
/// teal = today and the Steps chart (4.7:1 on paper), headBrown = Sitting chart (4.5:1),
/// container = other days (3.1:1). Nothing animates, so reduced motion needs no special case.
/// Every chart carries one screen-reader summary and ignores its drawn pieces.

const _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

String dayName(DateTime d) => _dayNames[d.weekday - 1];

String groupThousands(int v) => v.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

/// "7 h 20 m", "2 h 05 m", "45 m".
String durationText(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m m';
  return '$h h ${m.toString().padLeft(2, '0')} m';
}

/// "6 a.m." style label for spoken text.
String hourSpoken(int h) {
  final suffix = h < 12 ? 'a.m.' : 'p.m.';
  final n = h % 12 == 0 ? 12 : h % 12;
  return '$n $suffix';
}

String hourTick(int h) => '${h % 12 == 0 ? 12 : h % 12}${h < 12 ? 'a' : 'p'}';

/// Spoken summary for the 7-day steps strip.
String weekSummary(List<BandDay> days) {
  final counted = [
    for (final d in days)
      if (d.isValid) d,
  ];
  final today = days.last;
  final partial = [
    for (final d in days)
      if (d.isPartial) dayName(d.date),
  ];
  final b = StringBuffer();
  if (counted.length >= 2) {
    final hi = counted.reduce((a, b) => b.steps > a.steps ? b : a);
    final lo = counted.reduce((a, b) => b.steps < a.steps ? b : a);
    b.write(
      'Steps this week: highest ${dayName(hi.date)} ${groupThousands(hi.steps)}, '
      'lowest ${dayName(lo.date)} ${groupThousands(lo.steps)}. ',
    );
  } else {
    b.write('Steps this week: not enough worn days to compare. ');
  }
  b.write(
    today.isValid
        ? 'Today ${groupThousands(today.steps)}.'
        : 'Today: not enough wear time.',
  );
  if (partial.isNotEmpty) b.write(' Partial wear: ${partial.join(', ')}.');
  return b.toString();
}

/// Spoken summary for the hourly chart.
String hourlySummary(BandDay d, {required bool sitting}) {
  final values = sitting ? d.sittingByHour : d.stepsByHour;
  int? best;
  for (var h = 0; h < 24; h++) {
    final v = values[h];
    if (v != null && v > 0 && (best == null || v > values[best]!)) best = h;
  }
  if (best == null) {
    return sitting
        ? 'Sitting each hour: nothing recorded.'
        : 'Steps each hour: nothing recorded.';
  }
  final longest = d.longestSittingMinutes;
  if (sitting) {
    return 'Sitting each hour: most in the hour from ${hourSpoken(best)}, ${values[best]} minutes.'
        '${longest == null ? '' : ' Longest sitting stretch ${durationText(longest)}.'}';
  }
  return 'Steps each hour: busiest hour from ${hourSpoken(best)}, ${groupThousands(values[best]!)} steps.'
      '${longest == null ? '' : ' Longest sitting stretch ${durationText(longest)}.'}';
}

class _Bars extends CustomPainter {
  _Bars({
    required this.values,
    required this.colors,
    required this.hatched,
    required this.gap,
    required this.maxValue,
  });

  /// Null = nothing recorded: drawn as a thin baseline.
  final List<int?> values;
  final List<Color> colors;
  final List<bool> hatched;
  final double gap;
  final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final slot = size.width / n;
    final w = slot - gap;
    final base = Paint()
      ..color = LtColors.container
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(0, size.height - 0.75),
      Offset(size.width, size.height - 0.75),
      base,
    );
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null || v <= 0) continue;
      final h = (v / maxValue * (size.height - 4)).clamp(4.0, size.height - 2);
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(i * slot + gap / 2, size.height - h - 1.5, w, h),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      final color = colors[i];
      if (hatched[i]) {
        canvas.save();
        canvas.clipRRect(r);
        canvas.drawRRect(r, Paint()..color = LtColors.paper);
        final line = Paint()
          ..color = color
          ..strokeWidth = 2;
        for (var x = r.left - r.height; x < r.right; x += 6) {
          canvas.drawLine(
            Offset(x, r.bottom),
            Offset(x + r.height, r.top),
            line,
          );
        }
        canvas.restore();
        canvas.drawRRect(
          r.deflate(1),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      } else {
        canvas.drawRRect(r, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_Bars old) => true;
}

/// Seven small bars of steps per day, today highlighted, a part-worn day hatched and labelled "partial".
class BandWeekStrip extends StatelessWidget {
  const BandWeekStrip({super.key, required this.days});
  final List<BandDay> days;

  @override
  Widget build(BuildContext context) {
    final peak = days.fold<int>(1, (a, d) => d.steps > a ? d.steps : a);
    final label = LtText.body();
    final partialDays = [
      for (final d in days)
        if (d.isPartial) dayName(d.date).substring(0, 3),
    ];
    return Semantics(
      container: true,
      image: true,
      label: weekSummary(days),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 96,
            child: CustomPaint(
              painter: _Bars(
                values: [for (final d in days) d.steps > 0 ? d.steps : null],
                colors: [
                  for (var i = 0; i < days.length; i++)
                    i == days.length - 1 ? LtColors.teal : LtColors.container,
                ],
                hatched: [for (final d in days) d.isPartial],
                gap: 8,
                maxValue: peak.toDouble(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 28),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: i == days.length - 1
                          ? BoxDecoration(
                              color: LtColors.mintTint,
                              borderRadius: BorderRadius.circular(14),
                            )
                          : null,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _dayLetters[days[i].date.weekday - 1],
                          style: label.copyWith(
                            fontWeight: i == days.length - 1
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Active minutes', style: LtText.body(color: LtColors.secondary)),
          Row(
            children: [
              for (final d in days)
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        d.wornMinutes == 0 ? '–' : '${d.moderateMinutes}',
                        style: label,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (partialDays.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Partial wear (hatched): ${partialDays.join(', ')}',
              style: LtText.body(color: LtColors.secondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bars for each hour of the day, with ticks at 6a, 12p and 6p.
class BandHourlyChart extends StatelessWidget {
  const BandHourlyChart({super.key, required this.day, required this.sitting});
  final BandDay day;
  final bool sitting;

  @override
  Widget build(BuildContext context) {
    final values = sitting ? day.sittingByHour : day.stepsByHour;
    final peak = sitting
        ? 60.0
        : values
              .whereType<int>()
              .fold<int>(1, (a, b) => b > a ? b : a)
              .toDouble();
    final color = sitting ? LtColors.headBrown : LtColors.teal;
    return Semantics(
      container: true,
      image: true,
      label: hourlySummary(day, sitting: sitting),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 96,
              child: CustomPaint(
                painter: _Bars(
                  values: values,
                  colors: List.filled(24, color),
                  hatched: List.filled(24, false),
                  gap: 2,
                  maxValue: peak,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 28 * MediaQuery.textScalerOf(context).scale(1),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final h in const [6, 12, 18])
                    Positioned(
                      left: box.maxWidth * (h + 0.5) / 24,
                      top: 0,
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, 0),
                        child: Text(
                          hourTick(h),
                          style: LtText.body(color: LtColors.secondary),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
