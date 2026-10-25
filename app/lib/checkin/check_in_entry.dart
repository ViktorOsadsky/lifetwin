import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../ui/widgets/widgets.dart';
import 'check_in.dart';
import 'checkin_scheduler.dart';

/// The Room's check-in entry, self-contained: mount it with `const CheckInEntry()`.
///
/// It reads [CheckInScope] and the [CheckinScheduler] itself, and shows nothing without a scope.
/// Daily is the core loop: when one is due it is the most prominent control in the Room (a primary
/// button, 64pt); a due weekly one sits under it. When nothing is due it is a quiet "Checked in today".
/// It rebuilds when the repository changes, so finishing a check-in swaps the button for the quiet state.
class CheckInEntry extends StatelessWidget {
  const CheckInEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = CheckInScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: scope.repository,
      builder: (context, _) {
        final scheduler = CheckinScheduler(scope.repository, now: scope.now);
        final due = scheduler.dueKinds();
        if (due.isEmpty) {
          return scheduler.doneToday(CheckInKind.daily) ? const _CheckedInToday() : const SizedBox.shrink();
        }
        final first = due.first;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LipButton(
                label: first == CheckInKind.daily ? 'Daily check-in' : 'Weekly check-in',
                icon: first == CheckInKind.daily ? Icons.favorite_border_rounded : Icons.calendar_month_outlined,
                fontSize: 24,
                semanticLabel: first == CheckInKind.daily
                    ? 'Daily check-in. A 1-minute chat.'
                    : 'Weekly check-in. Ready now.',
                onTap: () => openCheckIn(context, kind: first),
              ),
              if (due.length > 1) ...[
                const SizedBox(height: 8),
                LipButton(
                  label: 'Weekly check-in',
                  kind: LipKind.secondary,
                  height: 56,
                  fontSize: 20,
                  onTap: () => openCheckIn(context, kind: due[1]),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CheckedInToday extends StatelessWidget {
  const _CheckedInToday();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Center(
      child: Semantics(
        label: 'Checked in today. See you tomorrow.',
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: LtColors.mintWash,
            borderRadius: BorderRadius.circular(LtRadii.chip),
            border: Border.all(color: LtColors.container, width: LtBorders.container),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline_rounded, size: 24, color: LtColors.ink),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Checked in today',
                    maxLines: 1,
                    softWrap: false,
                    style: LtText.body(weight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
