import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_button.dart';
import '../../widgets/lt_chips.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_list.dart';
import '../../widgets/lt_scaffold.dart';

enum _Effect { modeled, none, uncertain }

class _Lever {
  const _Lever(this.title, this.note, this.icon, this.effect);
  final String title;
  final String note;
  final LtIcons icon;
  final _Effect effect;
}

const _levers = [
  _Lever(
    'Move 60 more minutes a week',
    'About ten minutes a day, any way you like.',
    LtIcons.sneaker,
    _Effect.modeled,
  ),
  _Lever(
    'Sleep one more hour',
    'An earlier night on a usual evening.',
    LtIcons.moon,
    _Effect.modeled,
  ),
  _Lever(
    'Two fewer drinks a week',
    'The research here is still mixed.',
    LtIcons.glass,
    _Effect.uncertain,
  ),
  _Lever(
    'A daily supplement',
    'We found no supported benefit, so none is assumed.',
    LtIcons.leaf,
    _Effect.none,
  ),
];

/// F5: ranked, bounded single changes as a light list. Rank comes from
/// order and type weight; every figure is a placeholder.
class LeversScreen extends StatelessWidget {
  const LeversScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LtPage(
      title: 'Small steps',
      // The list scrolls; the next useful action stays pinned below it.
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(
                top: LtSpace.s8,
                bottom: LtSpace.s24,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LtSpace.gutter,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Small steps that may help',
                        style: context.text.title1,
                      ),
                      const SizedBox(height: LtSpace.s8),
                      Text(
                        'One change at a time, so you can see what each one does '
                        'for your twin.',
                        style: context.text.subhead.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const LtSectionHeader(
                  'Most helpful first, once the model is connected',
                ),
                LtRowGroup(
                  children: [
                    for (final (i, l) in _levers.indexed)
                      LtRow(
                        semanticsLabel:
                            'Step ${i + 1}. ${l.title}. ${l.note}. '
                            '${_effectWords(l.effect)}',
                        leading: LtRowIcon(
                          l.icon,
                          muted: l.effect != _Effect.modeled,
                        ),
                        title: l.title,
                        subtitle: l.note,
                        below: _EffectLine(effect: l.effect),
                      ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    LtSpace.gutter,
                    LtSpace.s12,
                    LtSpace.gutter,
                    0,
                  ),
                  child: OutlookFootnote(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LtSpace.gutter,
              LtSpace.s8,
              LtSpace.gutter,
              LtSpace.s12,
            ),
            child: LtButton(
              label: 'Research a plan',
              onPressed: () => context.go('/plan'),
            ),
          ),
        ],
      ),
    );
  }
}

String _effectWords(_Effect e) => switch (e) {
  _Effect.modeled => 'Modeled change placeholder.',
  _Effect.none => _noEffect,
  _Effect.uncertain => _unsure,
};

const _noEffect = 'Doesn’t change the model, but it may still feel good';
const _unsure = 'We’re not sure yet';

/// The trailing value as calm text: sign, number and a small icon. Warm,
/// honest words where there is no modeled number.
class _EffectLine extends StatelessWidget {
  const _EffectLine({required this.effect});

  final _Effect effect;

  @override
  Widget build(BuildContext context) => switch (effect) {
    _Effect.modeled => const DeltaChip(
      direction: DeltaDirection.flat,
      value: '[x.x pts]',
      prefix: 'about ',
    ),
    _Effect.none => const LtNote(label: _noEffect, icon: LtIcons.smile),
    _Effect.uncertain => const LtNote(label: _unsure, icon: LtIcons.question),
  };
}
