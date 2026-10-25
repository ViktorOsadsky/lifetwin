import 'package:flutter/material.dart';

import '../experiment/ideas_hub.dart';
import '../experiment/widgets/source_link.dart';
import '../ui/theme.dart';
import '../widgets/whole_word_text.dart';
import 'coach_client.dart';
import 'plan_acceptance.dart';
import 'widgets.dart';

/// Mochi's line when there is no plan to show (loading, offline, or an error): the card is never empty.
const todayFallbackLine = 'Hi! I’m here. A small step today counts.';

/// Home's "Today with Mochi": today's plan in four short rows (a workout, a food idea, a habit and Mochi's
/// encouragement), each with "Why?" (the item's reason and source) and feedback (👍, 👎, "Not for me")
/// that goes back to the coach as a revision. Tapping the card opens the full plan ([onOpen]).
///
/// The plan comes from the existing [CoachClient] (`POST /api/coach/plan`). [confirmedContext] is the same
/// context the plan screen sends. [beforeFirstPlan] runs once before the first request (the outside-AI
/// consent when the coach may use it); with no consent the coach still returns template plans.
class TodayWithMochiCard extends StatefulWidget {
  const TodayWithMochiCard({
    super.key,
    required this.client,
    required this.confirmedContext,
    required this.onOpen,
    this.beforeFirstPlan,
    this.onPlan,
    this.condensed = false,
    this.trailing,
    this.onIdeas,
    this.ideas,
    this.openUrl = defaultOpenUrl,
    this.acceptance,
    this.initialPlan,
  });

  final CoachClient client;

  /// The last plan this run saw: shown at once while the fresh one is fetched.
  final DailyPlan? initialPlan;
  final Map<String, dynamic> Function() confirmedContext;
  final VoidCallback onOpen;
  final Future<void> Function()? beforeFirstPlan;

  /// Told each plan the coach gives (the first and every revision).
  final void Function(DailyPlan plan)? onPlan;
  final OpenUrl openUrl;

  /// Items accepted on the plan screen: Home then reads "Today: 3 things planned ✓".
  final PlanAcceptance? acceptance;

  /// One line for Home: "Today: brisk walk · protein · …", opening the plan on a tap.
  final bool condensed;

  /// Condensed only: a control at the right of the row (Home's Check in button).
  final Widget? trailing;

  /// "More ideas ›" (full card only; Home's compact card stays one short row). Null hides it (under 18).
  final VoidCallback? onIdeas;

  /// Home's compact card: a second line, "Today's idea: {title} ›", opening that idea. Null (under 18)
  /// or no featured idea: no line.
  final IdeasAccess? ideas;

  @override
  State<TodayWithMochiCard> createState() => _TodayWithMochiCardState();
}

class _TodayWithMochiCardState extends State<TodayWithMochiCard> {
  DailyPlan? _plan;
  bool _loading = true;
  bool _disposed = false;
  bool _failed = false;
  bool _busy = false;
  final _chosen = <String, String>{};

  @override
  void initState() {
    super.initState();
    _plan = widget.initialPlan;
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await widget.beforeFirstPlan?.call();
      final plan = await widget.client.plan(_context());
      widget.onPlan?.call(plan);
      if (mounted) setState(() => _plan = plan);
    } catch (_) {
      if (mounted && _plan == null) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
      // Today's idea for the second line (the day's cache, or one call) comes after the plan, so it never
      // competes with the plan for the server or delays it.
      if (!_disposed) widget.ideas?.hub.ensureToday();
    }
  }

  Map<String, dynamic> _context([List<Map<String, dynamic>>? feedback]) {
    final context = Map<String, dynamic>.from(widget.confirmedContext());
    if (context['memory_consent'] != true) context.remove('habit_notes');
    final previous = _plan;
    if (previous != null && previous.revision != null && !previous.emergency) {
      context['previous_plan'] = previous.previousPlan();
      context['latest_revision_id'] = previous.revision;
      if (feedback != null) {
        context['feedback'] = {
          'revision_id': previous.revision,
          'items': feedback,
        };
      }
    }
    return context;
  }

  /// 👍 accepted, 👎 skipped, "Not for me" not done with that reason: the coach revises the plan.
  Future<void> _feedback(
    Map<String, dynamic> item,
    String status, {
    String? reason,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final next = await widget.client.plan(
        _context([
          {'item_id': item['id'], 'status': status, 'reason': ?reason},
        ]),
      );
      widget.onPlan?.call(next);
      if (mounted) {
        setState(() {
          _plan = next;
          _chosen
            ..clear()
            ..[item['id'] as String] = reason ?? status;
        });
      }
    } catch (_) {
      // The plan stays as it was; nothing is lost.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic>? _first(String kind) {
    for (final i in _plan?.items ?? const <Map<String, dynamic>>[]) {
      if (i['kind'] == kind) return i;
    }
    return null;
  }

  void _why(Map<String, dynamic> item) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: WholeWordText('Why this?', style: LtText.display(28)),
          ),
          const SizedBox(height: 12),
          WholeWordText(item['why'] as String, style: LtText.body()),
          const SizedBox(height: 8),
          SourceLink(
            label: item['source_title'] as String,
            url: item['source_url'] as String,
            open: widget.openUrl,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => widget.acceptance == null
      ? _card(context)
      : ListenableBuilder(listenable: widget.acceptance!, builder: (context, _) => _card(context));

  Widget _card(BuildContext context) {
    final plan = _plan;
    final slots = <(String, IconData, String)>[
      ('workout', Icons.directions_walk_rounded, 'Move'),
      ('diet', Icons.restaurant_rounded, 'Eat'),
      ('habit', Icons.check_circle_outline_rounded, 'Habit'),
      ('encourage', Icons.favorite_border_rounded, 'Mochi'),
    ];
    final encourage = _first('encourage');
    final ids = widget.acceptance?.idsFor(plan?.json['local_date'] as String?) ?? const <String>{};
    final acceptedCount = [for (final i in plan?.items ?? const <Map<String, dynamic>>[]) if (ids.contains(i['id'])) i].length;
    final showRows = plan != null && !plan.emergency && plan.items.isNotEmpty;
    if (widget.condensed) {
      final titles = [
        for (final kind in ['workout', 'diet', 'habit'])
          if (showRows && _first(kind)?['title'] is String)
            (_first(kind)!['title'] as String).toLowerCase(),
      ];
      final planned = acceptedCount;
      final line = planned > 0
          ? '$planned ${planned == 1 ? 'thing' : 'things'} planned ✓'
          : titles.isEmpty
          ? (_failed || _loading
                ? todayFallbackLine
                : (encourage?['message'] as String? ?? todayFallbackLine))
          : titles.join(' · ');
      final largeText = MediaQuery.textScalerOf(context).scale(17) >= 25.5;
      final summary = Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: titles.isEmpty && planned == 0 ? 'Today with Mochi · ' : 'Today: ',
              style: LtText.body(size: 17, weight: FontWeight.w700),
            ),
            TextSpan(text: line, style: LtText.body(size: 17)),
          ],
        ),
        maxLines: largeText ? null : 2,
        overflow: largeText ? TextOverflow.clip : TextOverflow.ellipsis,
      );
      final trailing =
          widget.trailing ??
          const SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.chevron_right_rounded, color: LtColors.ink),
          );
      return Semantics(
        container: true,
        label: 'Today with Mochi',
        child: WellnessCard(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: widget.onOpen,
                child: largeText
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          summary,
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: trailing,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: summary),
                          Padding(
                            padding: const EdgeInsets.only(left: 8, right: 6),
                            child: trailing,
                          ),
                        ],
                      ),
              ),
              if (widget.ideas case final access?)
                _IdeaLine(access: access, large: largeText),
            ],
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      label: 'Today with Mochi',
      child: WellnessCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: widget.onOpen,
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Today with Mochi',
                        style: LtText.display(26),
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: LtColors.ink),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_loading && plan == null)
              WholeWordText(todayFallbackLine, style: LtText.body())
            else if (!showRows)
              WholeWordText(
                _failed
                    ? todayFallbackLine
                    : (encourage?['message'] as String? ?? todayFallbackLine),
                style: LtText.body(),
              )
            else
              for (final (kind, icon, label) in slots)
                if (_first(kind) case final item?)
                  _Row(
                    icon: icon,
                    label: label,
                    item: item,
                    chosen: _chosen[item['id']],
                    busy: _busy,
                    onWhy: () => _why(item),
                    onFeedback: (status, {reason}) =>
                        _feedback(item, status, reason: reason),
                  ),
            if (widget.onIdeas != null) MoreIdeasLink(onTap: widget.onIdeas!),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.item,
    required this.chosen,
    required this.busy,
    required this.onWhy,
    required this.onFeedback,
  });
  final IconData icon;
  final String label;
  final Map<String, dynamic> item;
  final String? chosen;
  final bool busy;
  final VoidCallback onWhy;
  final void Function(String status, {String? reason}) onFeedback;

  @override
  Widget build(BuildContext context) {
    final minutes = item['minutes'];
    Widget chip(
      String text,
      String semantic,
      VoidCallback? onTap, {
      bool on = false,
    }) => Semantics(
      button: true,
      selected: on,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LtRadii.chip),
        child: Container(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: on ? LtColors.mint : null,
            borderRadius: BorderRadius.circular(LtRadii.chip),
          ),
          child: Text(
            text,
            style: LtText.body(size: 16, weight: FontWeight.w700),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 10),
                child: Icon(icon, size: 24, color: LtColors.ink),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WholeWordText(
                      minutes is int
                          ? '${item['title']} · $minutes min'
                          : '${item['title']}',
                      style: LtText.body(weight: FontWeight.w700),
                    ),
                    WholeWordText(
                      '${item['message']}',
                      style: LtText.body(color: LtColors.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              chip('Why?', '$label: why this', onWhy),
              chip(
                '👍',
                '$label: yes',
                busy ? null : () => onFeedback('accepted'),
                on: chosen == 'accepted',
              ),
              chip(
                '👎',
                '$label: skip',
                busy ? null : () => onFeedback('dismissed'),
                on: chosen == 'dismissed',
              ),
              chip(
                'Not for me',
                '$label: not for me',
                busy
                    ? null
                    : () => onFeedback('not_done', reason: 'Not for me'),
                on: chosen == 'Not for me',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Home's second line on the compact Today card: "💡 Today's idea: {title} ›". It opens that idea's
/// detail. A 48 pt target, one line (it wraps only at very large text); nothing when there is no idea.
class _IdeaLine extends StatelessWidget {
  const _IdeaLine({required this.access, required this.large});
  final IdeasAccess access;
  final bool large;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: access.hub,
    builder: (context, _) {
      final idea = access.hub.featured;
      if (idea == null) return const SizedBox.shrink();
      void open() => access.openIdea(context, idea);
      return Semantics(
        button: true,
        label: 'Today’s idea: ${idea.title}',
        excludeSemantics: true,
        onTap: open,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: 1, thickness: 1, color: LtColors.creamLip),
            InkWell(
              onTap: open,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 22,
                      color: LtColors.ink,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Today’s idea: ',
                              style: LtText.body(size: 17),
                            ),
                            TextSpan(
                              text: idea.title,
                              style: LtText.body(
                                size: 17,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        maxLines: large ? null : 1,
                        overflow: large
                            ? TextOverflow.clip
                            : TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(
                      width: 40,
                      height: 48,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: LtColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// "More ideas ›": opens Ideas for you. A 48pt target.
class MoreIdeasLink extends StatelessWidget {
  const MoreIdeasLink({
    super.key,
    required this.onTap,
    this.label = 'More ideas',
  });
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(
              '$label ›',
              style: LtText.body(weight: FontWeight.w700).copyWith(
                decoration: TextDecoration.underline,
                decorationThickness: 2,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
