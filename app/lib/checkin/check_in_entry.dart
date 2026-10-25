import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../ui/widgets/widgets.dart';
import 'check_in.dart';
import 'checkin_models.dart';
import 'checkin_scheduler.dart';

/// The Room's check-in entry, self-contained: mount it with `const CheckInEntry()`.
///
/// It reads [CheckInScope] and the engine's [CheckinScheduler] itself, and shows nothing without a scope or
/// a saved profile. The quick check-in is the core loop: when one is due it is the most prominent control
/// in the Room (a primary button, 64pt); a due weekly one sits under it (never instead of it). When
/// nothing is due it is a quiet "Checked in today". It rebuilds when the repository changes, so finishing a
/// check-in swaps the button for the quiet state.
class CheckInEntry extends StatelessWidget {
  const CheckInEntry({super.key, this.compact = false});

  /// One small button for a row on Home ("Check in", "Weekly" or "Done ✓"); the weekly one is also on
  /// long-press and in Settings.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scope = CheckInScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: scope.repository,
      builder: (context, _) {
        final repo = scope.repository;
        if (!repo.store.hasProfile) return const SizedBox.shrink();
        final now = (scope.now ?? DateTime.now)();
        final days = repo.dayLogs(from: now.subtract(const Duration(days: 30)), to: now);
        final due = const CheckinScheduler().due(
          localNow: now,
          history: repo.store.checkins,
          days: days,
          settings: repo.checkinSettings,
        );
        // Long-press: the weekly check-in on demand, whatever the schedule says (demo and "do it now").
        Widget onDemand(Widget child) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPress: () => openCheckIn(context, kind: CheckInKind.weekly),
          child: child,
        );
        if (compact) {
          final today = isoDay(dayOf(now));
          final done = repo.store.checkins.any((c) => c.kind != 'weekly' && c.date == today);
          if (!due.any) {
            return done
                ? onDemand(
                    Semantics(
                      label: 'Checked in today. See you tomorrow.',
                      excludeSemantics: true,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: LtColors.mintWash,
                          borderRadius: BorderRadius.circular(LtRadii.chip),
                          border: Border.all(color: LtColors.container, width: LtBorders.container),
                        ),
                        child: Text('Done ✓', maxLines: 1, softWrap: false, style: LtText.body(weight: FontWeight.w700)),
                      ),
                    ),
                  )
                : const SizedBox.shrink();
          }
          final quick = due.quick != null;
          return onDemand(
            LipButton(
              label: quick ? 'Check in' : 'Weekly',
              height: 48,
              fontSize: 18,
              expand: false,
              semanticLabel: quick ? 'Check in. A 1-minute chat.' : 'Weekly check-in. Ready now.',
              onTap: () => openCheckIn(context, kind: quick ? CheckInKind.quick : CheckInKind.weekly),
            ),
          );
        }
        if (!due.any) {
          final today = isoDay(dayOf(now));
          final done = repo.store.checkins.any((c) => c.kind != 'weekly' && c.date == today);
          return done ? onDemand(const _CheckedInToday()) : const SizedBox.shrink();
        }
        final firstQuick = due.quick != null;
        return onDemand(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LipButton(
                  label: firstQuick ? 'Check in' : 'Weekly check-in',
                  icon: firstQuick ? Icons.favorite_border_rounded : Icons.calendar_month_outlined,
                  fontSize: 24,
                  semanticLabel: firstQuick ? 'Check in. A 1-minute chat.' : 'Weekly check-in. Ready now.',
                  onTap: () => openCheckIn(context, kind: firstQuick ? CheckInKind.quick : CheckInKind.weekly),
                ),
                if (firstQuick && due.weekly) ...[
                  const SizedBox(height: 8),
                  LipButton(
                    label: 'Weekly check-in',
                    kind: LipKind.secondary,
                    height: 56,
                    fontSize: 20,
                    onTap: () => openCheckIn(context, kind: CheckInKind.weekly),
                  ),
                ],
              ],
            ),
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
