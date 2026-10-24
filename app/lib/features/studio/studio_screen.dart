import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/twin_look.dart';
import '../../theme/lt_cosmetics.dart';
import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_chips.dart';
import '../../widgets/lt_habitat.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_list.dart';
import '../../widgets/lt_pressable.dart';
import '../../widgets/lt_scaffold.dart';
import '../../widgets/lt_segmented.dart';
import '../../widgets/lt_twin.dart';

enum _Tab { skin, hair, top, extras }

/// F11: cosmetic choices for the twin. Looks never change any number.
class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key});

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen>
    with SingleTickerProviderStateMixin {
  _Tab _tab = _Tab.skin;

  /// A small hop when the look changes, so the change lands on the twin.
  late final AnimationController _hop;

  @override
  void initState() {
    super.initState();
    _hop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  /// Commit the choice first, then animate.
  void _pick(VoidCallback commit) {
    commit();
    if (!MediaQuery.of(context).disableAnimations) _hop.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final look = ref.watch(twinLookProvider);
    final n = ref.read(twinLookProvider.notifier);
    return LtPage(
      title: 'Twin studio',
      sheetToBottom: true,
      child: LayoutBuilder(
        // The stage absorbs whatever height the controls leave, so tall
        // phones get a bigger twin instead of an empty band; the controls
        // scroll on their own only when they outgrow the space.
        builder: (context, box) {
          return Column(
            children: [
              Expanded(
                child: AnimatedBuilder(
                  animation: _hop,
                  builder: (context, _) => LayoutBuilder(
                    builder: (context, stage) {
                      // Leave headroom for the chip, which wraps at large text.
                      final reserve =
                          40 + MediaQuery.textScalerOf(context).scale(16) * 2;
                      const fadeBottom = 120.0;
                      final h = stage.maxHeight;
                      final contact = ((h - fadeBottom + 28) / h).clamp(
                        0.55,
                        0.9,
                      );
                      final twinW = ((h * contact - reserve) / Twin.aspect)
                          .clamp(72.0, 232.0);
                      final v = _hop.value;
                      final moving = _hop.isAnimating;
                      return Habitat(
                        tier: 2,
                        contactLine: contact,
                        fadeTop: 72,
                        fadeBottom: fadeBottom,
                        actors: [
                          HabitatActor(
                            x: 0.5,
                            footprint: twinW * 0.78,
                            child: Twin(
                              width: twinW,
                              look: look,
                              mood: TwinMood.happy,
                              pose: moving ? TwinPose.cheer : TwinPose.rest,
                              hop: math.sin(math.pi * v) * 8,
                            ),
                          ),
                        ],
                        overlay: Padding(
                          padding: const EdgeInsets.all(LtSpace.s12),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: LtNote(
                              label: 'Looks never change your numbers',
                              icon: LtIcons.lock,
                              color: c.textPrimary,
                              iconColor: c.actionPrimary,
                              strong: true,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.max(0, box.maxHeight - 190),
                ),
                child: LtSheetPanel(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      LtSpace.gutter,
                      LtSpace.s12,
                      LtSpace.gutter,
                      LtSpace.s16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LtSegmented<_Tab>(
                          segments: const [
                            LtSegment(value: _Tab.skin, label: 'Skin'),
                            LtSegment(value: _Tab.hair, label: 'Hair'),
                            LtSegment(value: _Tab.top, label: 'Top'),
                            LtSegment(value: _Tab.extras, label: 'Extras'),
                          ],
                          value: _tab,
                          onChanged: (t) => setState(() => _tab = t),
                        ),
                        const SizedBox(height: LtSpace.s16),
                        KeyedSubtree(
                          key: ValueKey(_tab),
                          child: switch (_tab) {
                            _Tab.skin => _Section(
                              title: 'Skin tone',
                              child: _Swatches(
                                labels: [
                                  for (var i = 1; i <= 5; i++)
                                    'Skin tone $i of 5',
                                ],
                                colors: LtCosmetics.skin,
                                selected: look.skin,
                                onSelect: (i) => _pick(() => n.setSkin(i)),
                              ),
                            ),
                            _Tab.hair => _Section(
                              title: 'Hair',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _LookTiles(
                                    options: [
                                      for (final (h, label) in const [
                                        (TwinHair.shortHair, 'Short'),
                                        (TwinHair.bob, 'Bob'),
                                        (TwinHair.curly, 'Curly'),
                                      ])
                                        (
                                          label,
                                          look.copyWith(hairStyle: h),
                                          look.hairStyle == h,
                                          () => _pick(() => n.setHairStyle(h)),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: LtSpace.s16),
                                  _Swatches(
                                    labels: [
                                      for (final name in LtCosmetics.hairNames)
                                        'Hair colour $name',
                                    ],
                                    colors: LtCosmetics.hair,
                                    selected: look.hairColor,
                                    onSelect: (i) =>
                                        _pick(() => n.setHairColor(i)),
                                  ),
                                ],
                              ),
                            ),
                            _Tab.top => _Section(
                              title: 'Top colour',
                              child: _Swatches(
                                labels: [
                                  for (final name in LtCosmetics.topNames)
                                    'Top colour $name',
                                ],
                                colors: LtCosmetics.tops(c),
                                selected: look.top,
                                onSelect: (i) => _pick(() => n.setTop(i)),
                              ),
                            ),
                            _Tab.extras => _Section(
                              title: 'Extras',
                              child: _LookTiles(
                                options: [
                                  for (final (e, label) in const [
                                    (TwinExtra.none, 'None'),
                                    (TwinExtra.glasses, 'Glasses'),
                                    (TwinExtra.headband, 'Headband'),
                                  ])
                                    (
                                      label,
                                      look.copyWith(extra: e),
                                      look.extra == e,
                                      () => _pick(() => n.setExtra(e)),
                                    ),
                                ],
                              ),
                            ),
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: context.text.headline),
        const SizedBox(height: LtSpace.s12),
        child,
      ],
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.labels,
    required this.colors,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final List<Color> colors;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // One row of five on every phone: the swatch shrinks (never below the
    // 44 pt target) instead of orphaning the last tone on a second row.
    return LayoutBuilder(
      builder: (context, box) {
        final size = ((box.maxWidth - LtSpace.s8 * 4) / 5).clamp(44.0, 52.0);
        final gap = ((box.maxWidth - size * 5) / 4).clamp(LtSpace.s8, 16.0);
        return Wrap(
          spacing: gap,
          runSpacing: LtSpace.s12,
          children: [
            for (final (i, color) in colors.indexed)
              LtPressable(
                label: labels[i],
                selected: i == selected,
                onTap: () => onSelect(i),
                // The face drops into a transparent edge: tactile, not bubbly.
                baseColor: c.clear,
                borderRadius: LtRadius.chipAll,
                depth: 2,
                builder: (context, pressed) => Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: i == selected ? c.actionPrimary : c.line,
                      width: i == selected ? 3 : 1,
                    ),
                  ),
                  child: i == selected
                      ? Center(
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: c.bgSurface,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: LtIcon(
                                LtIcons.check,
                                color: c.actionPrimary,
                                size: 16,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Object picker: each tile shows the twin's head wearing that option, so
/// the choice is recognisable before and after it is applied.
class _LookTiles extends StatelessWidget {
  const _LookTiles({required this.options});

  final List<(String, TwinLook, bool, VoidCallback)> options;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scaler = MediaQuery.textScalerOf(context);
    final style = context.text.footnote.copyWith(color: c.textPrimary);
    return LayoutBuilder(
      builder: (context, box) {
        const gap = LtSpace.s8;
        var widest = 0.0;
        for (final o in options) {
          final tp = TextPainter(
            text: TextSpan(text: o.$1, style: style),
            textScaler: scaler,
            textDirection: TextDirection.ltr,
          )..layout();
          widest = math.max(widest, tp.width);
          tp.dispose();
        }
        final need = math.max(widest + LtSpace.s16 * 2, 84.0);
        var cols = options.length;
        while (cols > 1 && (box.maxWidth - gap * (cols - 1)) / cols < need) {
          cols--;
        }
        final tileW = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (label, look, selected, onTap) in options)
              SizedBox(
                width: tileW,
                child: LtPressable(
                  label: label,
                  selected: selected,
                  onTap: onTap,
                  baseColor: c.clear,
                  depth: 2,
                  borderRadius: LtRadius.smallAll,
                  builder: (context, pressed) => Container(
                    padding: const EdgeInsets.fromLTRB(
                      LtSpace.s8,
                      LtSpace.s12,
                      LtSpace.s8,
                      LtSpace.s8,
                    ),
                    decoration: BoxDecoration(
                      color: selected || pressed ? c.chipSelected : c.bgSurface,
                      borderRadius: LtRadius.smallAll,
                      border: Border.all(
                        color: selected ? c.actionPrimary : c.line,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: 0.62,
                            child: Twin(width: 64, look: look),
                          ),
                        ),
                        const SizedBox(height: LtSpace.s4),
                        Text(label, style: style, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
