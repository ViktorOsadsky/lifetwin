import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../ui/twin_appearance.dart';
import '../../widgets/whole_word_text.dart';
import '../../wellness/today_card.dart' show MoreIdeasLink;
import '../ideas_hub.dart';
import '../recommendations.dart';
import 'idea_card.dart' show effectNote;
import 'idea_scene.dart';

/// Voice (`client_action: open_ideas`): today's featured idea from the cached ideas, with "See ideas ›".
/// With nothing featured Mochi says it needs a bit more, and no card shows.
class IdeasOpenCard extends StatefulWidget {
  const IdeasOpenCard({super.key, required this.access, required this.appearance});
  final IdeasAccess access;
  final TwinAppearance appearance;

  @override
  State<IdeasOpenCard> createState() => _IdeasOpenCardState();
}

class _IdeasOpenCardState extends State<IdeasOpenCard> {
  @override
  void initState() {
    super.initState();
    widget.access.hub.ensureToday();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.access.hub,
    builder: (context, _) {
      final idea = widget.access.hub.featured;
      if (idea == null) {
        if (widget.access.hub.loading) return const SizedBox.shrink();
        return Semantics(
          liveRegion: true,
          child: WholeWordText('I’ll have ideas once I know a bit more.', style: LtText.body(weight: FontWeight.w700)),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeaRow(idea: idea, appearance: widget.appearance, onTap: () => widget.access.openIdea(context, idea)),
          Center(
            child: MoreIdeasLink(
              label: 'See ideas',
              onTap: () => widget.access.openList(context, origin: 'chat'),
            ),
          ),
        ],
      );
    },
  );
}

/// The end of onboarding: "Mochi's first ideas for you", one or two ideas (the featured one first), the
/// caveat right under them, and "See all ideas ›". [ideas] are the server's items for the finished
/// intake; they are kept as today's ideas until the first full answer.
class IdeasClosingCard extends StatefulWidget {
  const IdeasClosingCard({super.key, required this.access, required this.appearance, required this.ideas});
  final IdeasAccess access;
  final TwinAppearance appearance;
  final List<Recommendation> ideas;

  @override
  State<IdeasClosingCard> createState() => _IdeasClosingCardState();
}

class _IdeasClosingCardState extends State<IdeasClosingCard> {
  @override
  void initState() {
    super.initState();
    widget.access.hub.seed(widget.ideas);
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.ideas.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: WholeWordText('Mochi’s first ideas for you', style: LtText.display(24))),
        const SizedBox(height: 10),
        for (final idea in first) ...[
          IdeaRow(
            idea: idea,
            appearance: widget.appearance,
            showLine: false,
            onTap: () => widget.access.openIdea(context, idea),
          ),
          const SizedBox(height: 8),
        ],
        Center(
          child: MoreIdeasLink(
            label: 'See all ideas',
            onTap: () => widget.access.openList(context, origin: 'chat'),
          ),
        ),
        WholeWordText('$effectNote.', style: LtText.body(color: LtColors.secondary)),
      ],
    );
  }
}
