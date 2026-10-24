import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/game_health.dart';
import '../../state/intake_answers.dart';
import '../../state/twin_look.dart';
import '../../theme/lt_space.dart';
import '../../theme/lt_theme.dart';
import '../../widgets/lt_chips.dart';
import '../../widgets/lt_game_health_meter.dart';
import '../../widgets/lt_habitat.dart';
import '../../widgets/lt_icon.dart';
import '../../widgets/lt_mascot.dart';
import '../../widgets/lt_list.dart';
import '../../widgets/lt_speech_bubble.dart';
import '../../widgets/lt_twin.dart';

enum _Prop {
  fortune(LtIcons.ball, 'Fortune'),
  experiment(LtIcons.flask, 'Experiment'),
  quiz(LtIcons.quiz, 'Quiz'),
  studio(LtIcons.mirror, 'Studio');

  const _Prop(this.icon, this.label);
  final LtIcons icon;
  final String label;
}

/// What the twin is doing right now. Short reaction state, kept separate
/// from persistent game health.
enum _Reaction { none, wave, fortune, experiment, quiz, studio }

/// Game room (F1): the twin and Pip live in the habitat; the props tray
/// below is the way into each mode. Tapping a prop makes the twin respond
/// on the stage before the mode opens; tapping the twin makes it wave.
/// The tier is fixed at Steady until the vitality model is wired.
class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen>
    with SingleTickerProviderStateMixin {
  static const tier = 2;

  late final AnimationController _react;
  _Reaction _reaction = _Reaction.none;

  @override
  void initState() {
    super.initState();
    _react = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _react.dispose();
    super.dispose();
  }

  bool get _reduce => MediaQuery.of(context).disableAnimations;

  /// Commit the reaction, let the twin respond, then open the mode.
  Future<void> _openProp(_Prop prop, String route) async {
    if (_reaction != _Reaction.none) return; // one reaction at a time
    setState(() => _reaction = _Reaction.values.byName(prop.name));
    _react.duration = Duration(milliseconds: _reduce ? 240 : 420);
    await _react.forward(from: 0).orCancel.catchError((_) {});
    if (!mounted) return;
    await context.push(route);
    if (!mounted) return;
    _react.duration = Duration(milliseconds: _reduce ? 1 : 260);
    await _react.reverse().orCancel.catchError((_) {});
    if (mounted) setState(() => _reaction = _Reaction.none);
  }

  Future<void> _wave() async {
    if (_reaction != _Reaction.none) return;
    setState(() => _reaction = _Reaction.wave);
    _react.duration = const Duration(milliseconds: 1100);
    await _react.forward(from: 0).orCancel.catchError((_) {});
    if (mounted) setState(() => _reaction = _Reaction.none);
  }

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(gameHealthProvider);
    final look = ref.watch(twinLookProvider);
    final answered = ref.watch(intakeAnswersProvider).isComplete;
    final needsCare = health.hearts < GameHealth.max;
    final next = needsCare ? _Prop.quiz : _Prop.fortune;

    final line = switch (_reaction) {
      _Reaction.wave => 'Your twin says hi back!',
      _Reaction.fortune =>
        answered ? 'Let’s peek into the ball.' : 'First, a few questions!',
      _Reaction.experiment => 'Off to the lab. Nothing real changes there.',
      _Reaction.quiz => 'Quiz time. Your twin is ready.',
      _Reaction.studio => 'New look? It never changes your numbers.',
      _Reaction.none =>
        needsCare
            ? 'Your twin feels a bit off. A quiz win will perk it up.'
            : answered
            ? 'Peek into the magic ball whenever you like.'
            : 'Hi, I’m Pip! Tap the magic ball and I’ll ask a few questions.',
    };

    return ColoredBox(
      color: context.colors.bgGround,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) =>
                  _stage(context, box, line: line, look: look, health: health),
            ),
          ),
          _Tray(
            next: next,
            onOpen: (p) => _openProp(p, switch (p) {
              _Prop.fortune => answered ? '/fortune' : '/intake',
              _Prop.experiment => '/experiment',
              _Prop.quiz => '/quiz',
              _Prop.studio => '/studio',
            }),
          ),
        ],
      ),
    );
  }

  Widget _stage(
    BuildContext context,
    BoxConstraints box, {
    required String line,
    required TwinLook look,
    required GameHealth health,
  }) {
    final w = box.maxWidth;
    final h = box.maxHeight;
    final top = MediaQuery.of(context).padding.top;
    // Feet sit just above the bottom feather, so the twin stands on solid
    // meadow while the scene dissolves into the props sheet below it.
    const fadeBottom = 120.0;
    final contact = ((h - fadeBottom + 28) / h).clamp(0.6, 0.9);
    const hud = 56.0;

    // Measure Pip's line so the twin is sized to the space actually left.
    final bubbleW = math.min(w - LtSpace.gutter * 2, 320.0);
    final tp = TextPainter(
      text: TextSpan(text: line, style: context.text.callout),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: bubbleW - LtSpeechBubble.padding.horizontal);
    final bubbleH = tp.height + LtSpeechBubble.padding.vertical + 9;
    tp.dispose();
    final free = h * contact - (top + LtSpace.s12 + hud + bubbleH + 16);
    final twinW = (free / Twin.aspect).clamp(84.0, 232.0);
    final pipW = twinW * 0.44;

    return AnimatedBuilder(
      animation: _react,
      builder: (context, _) {
        final v = _react.value;
        final r = _reaction;
        final reduce = _reduce;
        // Prop reactions ease out with a little overshoot and hold; the wave
        // goes there and back. Reduced motion shows the pose without travel.
        final k = reduce
            ? (r == _Reaction.none ? 0.0 : 1.0)
            : r == _Reaction.wave
            ? math.sin(math.pi * v)
            : Curves.easeOutBack.transform(v);
        final hop = reduce ? 0.0 : math.sin(math.pi * v) * 7;

        final (pose, mood, side, lean) = switch (r) {
          _Reaction.none => (
            needsHuddle(health) ? TwinPose.huddle : TwinPose.rest,
            health.mood,
            1,
            0.0,
          ),
          _Reaction.wave => (TwinPose.wave, TwinMood.happy, 1, 0.35),
          _Reaction.fortune => (TwinPose.reach, TwinMood.thinking, -1, -0.8),
          _Reaction.experiment => (TwinPose.reach, TwinMood.happy, -1, -0.5),
          _Reaction.quiz => (TwinPose.cheer, TwinMood.happy, 1, 0.3),
          _Reaction.studio => (TwinPose.wave, TwinMood.happy, 1, 0.8),
        };
        final showPose = reduce || r == _Reaction.none || v > 0.15;

        final twin = Semantics(
          button: true,
          label: 'Your twin, feeling ${mood.name}. Wave hello',
          excludeSemantics: true,
          onTap: _wave,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _wave,
            child: Twin(
              width: twinW,
              look: look,
              mood: showPose ? mood : health.mood,
              pose: showPose ? pose : TwinPose.rest,
              reachSide: side,
              lean: lean * k,
              hop: hop * (r == _Reaction.none ? 0 : 1),
            ),
          ),
        );

        return Habitat(
          tier: tier,
          contactLine: contact,
          fadeTop: top + hud,
          fadeBottom: fadeBottom,
          actors: [
            HabitatActor(x: 0.40, footprint: twinW * 0.78, child: twin),
            HabitatActor(
              x: 0.80,
              footprint: pipW * 0.7,
              lift: 6,
              child: Mascot(
                width: pipW,
                shadow: false,
                state: r == _Reaction.none
                    ? MascotState.speaking
                    : r == _Reaction.wave
                    ? MascotState.celebrating
                    : MascotState.listening,
              ),
            ),
          ],
          overlay: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                LtSpace.gutter,
                LtSpace.s12,
                LtSpace.gutter,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: hud - LtSpace.s12,
                    child: Row(
                      children: [
                        const TierChip(tier: tier),
                        const Spacer(),
                        GameHealthMeter(hearts: health.hearts),
                      ],
                    ),
                  ),
                  const SizedBox(height: LtSpace.s12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: bubbleW),
                      child: LtSpeechBubble(text: line, tailDown: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool needsHuddle(GameHealth h) => h.mood == TwinMood.sick;
}

/// The props dock: one sheet rising out of the meadow. Props are drawn
/// icons on faint circles with labels, no tiles or boxes; the next useful
/// prop is the one filled blue circle.
class _Tray extends StatelessWidget {
  const _Tray({required this.next, required this.onOpen});

  final _Prop next;
  final ValueChanged<_Prop> onOpen;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LtSheetPanel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LtSpace.s8,
          LtSpace.s8,
          LtSpace.s8,
          LtSpace.s8,
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            // Four across when every label fits under its circle; otherwise
            // a 2 x 2 grid with the label beside the icon, so enlarged text
            // never squeezes a label.
            final quarter = box.maxWidth / 4;
            var widest = 0.0;
            for (final p in _Prop.values) {
              final tp = TextPainter(
                text: TextSpan(
                  text: p.label,
                  style: _labelStyle(context, true),
                ),
                textScaler: scaler,
                textDirection: TextDirection.ltr,
              )..layout();
              widest = math.max(widest, tp.width);
              tp.dispose();
            }
            final four = widest + LtSpace.s8 <= quarter;
            final cols = four ? 4 : 2;
            final w = box.maxWidth / cols;
            // Two across: label beside the circle when it fits, else below.
            final stacked = four || widest + 52 + LtSpace.s8 * 3 > w;
            return Wrap(
              children: [
                for (final p in _Prop.values)
                  SizedBox(
                    width: w,
                    child: _PropButton(
                      prop: p,
                      highlighted: p == next,
                      stacked: stacked,
                      onTap: () => onOpen(p),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

TextStyle _labelStyle(BuildContext context, bool highlighted) =>
    context.text.footnote.copyWith(
      color: highlighted
          ? context.colors.actionPrimary
          : context.colors.textPrimary,
      fontWeight: FontWeight.w600,
      fontVariations: const [FontVariation('wght', 600)],
    );

/// A prop entry point. The circle face drops 2 pt inside a stationary hit
/// region while pressed; semantics run the same action as a tap.
class _PropButton extends StatefulWidget {
  const _PropButton({
    required this.prop,
    required this.highlighted,
    required this.stacked,
    required this.onTap,
  });

  final _Prop prop;
  final bool highlighted;
  final bool stacked;
  final VoidCallback onTap;

  @override
  State<_PropButton> createState() => _PropButtonState();
}

class _PropButtonState extends State<_PropButton> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hi = widget.highlighted;
    final reduce = MediaQuery.of(context).disableAnimations;
    final circle = AnimatedContainer(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      width: 52,
      height: 52,
      transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
      decoration: BoxDecoration(
        color: hi
            ? (_pressed ? c.actionPrimaryPressed : c.actionPrimary)
            : (_pressed ? c.chipSelected : c.iconBackdrop),
        shape: BoxShape.circle,
        boxShadow: hi && !_pressed
            ? [
                BoxShadow(
                  color: c.actionPrimary.withValues(alpha: 0.28),
                  offset: const Offset(0, 4),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: Center(
        child: LtIcon(
          widget.prop.icon,
          size: 26,
          color: hi ? c.bgSurface : c.actionPrimary,
        ),
      ),
    );
    final label = Text(
      widget.prop.label,
      style: _labelStyle(context, hi),
      textAlign: TextAlign.center,
    );
    return Semantics(
      button: true,
      label: hi ? '${widget.prop.label}, suggested next' : widget.prop.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LtSpace.s4,
            vertical: LtSpace.s8,
          ),
          child: widget.stacked
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    circle,
                    const SizedBox(height: LtSpace.s4 + 2),
                    label,
                  ],
                )
              : Row(
                  children: [
                    circle,
                    const SizedBox(width: LtSpace.s8),
                    Expanded(
                      child: Text(
                        widget.prop.label,
                        style: _labelStyle(context, hi),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
