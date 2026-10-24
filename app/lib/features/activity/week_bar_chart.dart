import 'package:flutter/material.dart';

import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';

/// Four weekly bars, oldest first. Schematic: bars scale to the largest week,
/// there are no axes and no targets.
class WeekBarChart extends StatelessWidget {
  const WeekBarChart({super.key, required this.weekly});

  final List<int> weekly;

  static const _labels = ['3 wks ago', '2 wks ago', 'Last wk', 'This wk'];
  static const _plot = 88.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxV = weekly.fold<int>(0, (a, b) => a > b ? a : b);
    return Semantics(
      label: 'Active minutes by week, oldest first: ${weekly.join(', ')}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < weekly.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: LtSpace.s8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${weekly[i]}', style: context.text.caption),
                    const SizedBox(height: LtSpace.s4),
                    SizedBox(
                      height: _plot,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: maxV == 0
                              ? 6
                              : (weekly[i] / maxV * _plot).clamp(6, _plot),
                          decoration: BoxDecoration(
                            color: i == weekly.length - 1
                                ? c.actionPrimary
                                : c.skyHighlight,
                            borderRadius: BorderRadius.circular(LtRadius.small),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: LtSpace.s8),
                    Text(
                      _labels[i],
                      style: context.text.caption,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
