import 'package:flutter/material.dart';

import '../checkin/check_in.dart';
import '../twin/twin_repository.dart';
import '../twin/twin_state.dart';
import '../ui/theme.dart';
import '../widgets/whole_word_text.dart';

/// The Room's agentic pills ("Still learning N", "What I see", "Try a change"), built here so the Room
/// mounts them with one line: `...widget.extraPills`. Each listens to the repository itself, shows only
/// when it has something to say, and is a 48pt target.
List<Widget> roomPills({
  required TwinRepository? repository,
  required VoidCallback onExperiment,
  required VoidCallback onStillLearning,
  required VoidCallback onWellness,
}) {
  final repo = repository;
  if (repo == null) return const [];
  return [
    _Live(
      repo: repo,
      pill: (r) {
        final n = r.current?.missingInputs.length ?? 0;
        return n == 0
            ? null
            : RoomPill(
                icon: Icons.help_outline_rounded,
                label: 'Still learning $n',
                semantics: 'Still learning: $n answers to add',
                onTap: onStillLearning,
              );
      },
    ),
    _Live(
      repo: repo,
      pill: (r) => r.wellnessCards.isEmpty
          ? null
          : RoomPill(
              icon: Icons.star_border_rounded,
              label: 'What I see',
              semantics: 'What I see: wellness cards, each with its source',
              onTap: onWellness,
            ),
    ),
    _Live(
      repo: repo,
      pill: (r) => r.current == null
          ? null
          : RoomPill(
              icon: Icons.science_outlined,
              label: 'Try a change',
              semantics: 'Try a change with your twin',
              onTap: onExperiment,
            ),
    ),
  ];
}

class _Live extends StatelessWidget {
  const _Live({required this.repo, required this.pill});
  final TwinRepository repo;
  final Widget? Function(TwinRepository) pill;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: repo, builder: (context, _) => pill(repo) ?? const SizedBox.shrink());
}

/// The character's state for the Room scene, kept current: `RoomTwinState(builder: (state) => ...)`. The
/// state is null (a plain standing twin) when there is no [CheckInScope].
class RoomTwinState extends StatelessWidget {
  const RoomTwinState({super.key, required this.builder});
  final Widget Function(TwinState? state) builder;

  @override
  Widget build(BuildContext context) {
    final repo = CheckInScope.maybeOf(context)?.repository;
    if (repo == null) return builder(null);
    return ListenableBuilder(listenable: repo, builder: (context, _) => builder(repo.twinState()));
  }
}

/// A pill beside the status line.
class RoomPill extends StatelessWidget {
  const RoomPill({super.key, required this.icon, required this.label, required this.semantics, required this.onTap});
  final IconData icon;
  final String label;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semantics,
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(LtRadii.chip),
          border: Border.all(color: LtColors.control, width: LtBorders.control),
          boxShadow: LtShadows.small,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: LtColors.ink),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: WholeWordText(label, maxLines: 1, softWrap: false, style: LtText.body(weight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
