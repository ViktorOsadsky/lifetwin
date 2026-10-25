/// The continuous-voice indicator (design set VC-1 to VC-7, motion spec VCN-1): a status pill
/// on the bottom edge of the room picture, a ring around the twin, and the live transcript.
///
/// Honest mic rule: the teal ring and the live dot show ONLY while the microphone is open
/// ([VoiceLook.listening]). Speaking, thinking and typing never show them.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../widgets/whole_word_text.dart';

/// What the voice conversation is doing, as the person should see it.
enum VoiceLook {
  /// Mochi is talking (the microphone is closed).
  speaking,

  /// The microphone is open.
  listening,

  /// Waiting for the server (the microphone is closed).
  thinking,

  /// VoiceOver is on: Mochi waits for a tap.
  waiting,

  /// The person types: not listening.
  typing,

  /// Nothing is happening for a moment (between Mochi's line and the microphone opening).
  /// Shown as [typing] if it lasts, so a closed microphone is never dressed up as anything else.
  between,

  /// The person closed the microphone; it stays closed until they turn it on.
  micOff,
}

/// Colours from the VCN-1 contrast table (WCAG 2.1 AA).
abstract final class VoiceColors {
  static const listen = Color(0xFF17594A); // 8.06:1 on the pill, 4.78:1 on the lilac plate
  static const speak = Color(0xFF8A5A12); // 5.82:1 on the pill, 3.45:1 on the plate
  static const wait = Color(0xFF6B4E42); // 7.39:1
  static const transcript = Color(0xFFE3F5EC);
  static const mintGlow = Color(0xFF9FD9C3);
  static const dotWell = Color(0xFFCDEFE1);
}

/// Holds the look the person sees: nothing shows for the first 300 ms of thinking, and a
/// short gap after Mochi's line keeps the gold look instead of flashing "Not listening".
class VoiceLive extends StatefulWidget {
  const VoiceLive({super.key, required this.look, required this.builder});

  final VoiceLook look;
  final Widget Function(BuildContext context, VoiceLook shown, bool hidden) builder;

  static const thinkingDelay = Duration(milliseconds: 300);

  @override
  State<VoiceLive> createState() => _VoiceLiveState();
}

class _VoiceLiveState extends State<VoiceLive> {
  late VoiceLook _shown = widget.look;
  bool _hidden = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _apply(widget.look);
  }

  @override
  void didUpdateWidget(VoiceLive old) {
    super.didUpdateWidget(old);
    if (widget.look != old.look) _apply(widget.look);
  }

  void _apply(VoiceLook next) {
    _timer?.cancel();
    final previous = _shown;
    _hidden = false;
    _shown = next;
    if (next == VoiceLook.thinking) {
      // Shown only after 300 ms; until then nothing claims anything.
      _hidden = true;
      _timer = Timer(VoiceLive.thinkingDelay, () {
        if (mounted) setState(() => _hidden = false);
      });
    } else if (next == VoiceLook.between && previous == VoiceLook.speaking) {
      // The microphone is closed, so the gold look is still true for a moment.
      _shown = previous;
      _timer = Timer(VoiceLive.thinkingDelay, () {
        if (mounted) setState(() => _shown = VoiceLook.between);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _shown, _hidden);
}

/// A repeating 0..1 value. Callers build it only when motion is allowed.
class _Loop extends StatefulWidget {
  const _Loop({super.key, required this.duration, required this.builder});
  final Duration duration;
  final Widget Function(BuildContext context, double t) builder;

  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: widget.duration)..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _a, builder: (c, _) => widget.builder(c, _a.value));
}

/// The ring around the twin: teal and breathing while the microphone is open, dashed while the
/// answer is worked out; none otherwise. Mochi talking has no ring (owner, 2026-10-25); the pill
/// says it.
class VoiceRing extends StatelessWidget {
  const VoiceRing({super.key, required this.look, required this.size, this.glow = true});

  final VoiceLook look;
  final double size;

  /// The soft mint fill inside the teal ring. Off when the ring is drawn over the twin.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final Widget ring = switch (look) {
      VoiceLook.listening => _listening(reduced),
      VoiceLook.thinking => SizedBox(
        key: const ValueKey('voice-ring-thinking'),
        width: size,
        height: size,
        child: CustomPaint(painter: _DashedCircle(VoiceColors.wait)),
      ),
      _ => const SizedBox.shrink(key: ValueKey('voice-ring-none')),
    };
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedSwitcher(
          duration: Duration(milliseconds: reduced ? 150 : 240),
          reverseDuration: Duration(milliseconds: reduced ? 150 : 100),
          switchInCurve: const Cubic(.2, 0, 0, 1),
          switchOutCurve: const Cubic(.3, 0, 1, 1),
          child: SizedBox(
            key: ValueKey(look),
            width: size * 1.14,
            height: size * 1.14,
            child: Center(child: ring),
          ),
        ),
      ),
    );
  }

  Widget _circle(Color color, double width, {Color? fill}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: fill,
      border: Border.all(color: color, width: width),
    ),
  );

  Widget _listening(bool reduced) {
    final glow = this.glow ? VoiceColors.mintGlow.withValues(alpha: 0.28) : null;
    if (reduced) {
      return KeyedSubtree(
        key: const ValueKey('voice-ring-listening'),
        child: _circle(VoiceColors.listen, 3, fill: glow),
      );
    }
    return _Loop(
      key: const ValueKey('voice-ring-listening'),
      duration: const Duration(milliseconds: 2400),
      builder: (context, t) {
        final breathe = 1 + 0.04 * math.sin(2 * math.pi * t);
        final echo = const Cubic(.2, 0, 0, 1).transform(t);
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 0.55 * (1 - echo),
              child: Transform.scale(scale: 1 + 0.12 * echo, child: _circle(VoiceColors.listen, 2)),
            ),
            Transform.scale(
              scale: breathe,
              child: _circle(VoiceColors.listen, 3, fill: glow),
            ),
          ],
        );
      },
    );
  }
}

class _DashedCircle extends CustomPainter {
  const _DashedCircle(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final path = Path()..addOval(Rect.fromLTWH(1.25, 1.25, s.width - 2.5, s.height - 2.5));
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 14) {
        canvas.drawPath(m.extractPath(d, math.min(d + 8, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

/// The status pill: a label, never a button. One glyph, one word per state, so colour is never
/// the only signal.
class VoicePill extends StatelessWidget {
  const VoicePill({super.key, required this.look, this.hidden = false});

  final VoiceLook look;

  /// The first 300 ms of thinking: the slot stays, nothing is drawn.
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    if (hidden) return const SizedBox(key: ValueKey('voice-pill-hidden'), height: 48);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final shown = look == VoiceLook.between ? VoiceLook.typing : look;
    final (text, spoken) = switch (shown) {
      VoiceLook.speaking => ('Mochi is talking', 'Mochi is talking'),
      VoiceLook.listening => (reduced ? 'Listening' : 'Listening…', 'Listening'),
      VoiceLook.thinking => (reduced ? 'Thinking' : 'Thinking…', 'Mochi is thinking'),
      VoiceLook.waiting => ('Waiting for your tap', 'Waiting for your tap'),
      VoiceLook.micOff => ('Mic off', 'Mic off'),
      _ => ('Not listening', 'Not listening'),
    };
    final content = Container(
      key: ValueKey('voice-pill-${shown.name}'),
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(12, 6, 22, 6),
      decoration: BoxDecoration(
        color: LtColors.paper,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: LtColors.container, width: LtBorders.container),
        boxShadow: LtShadows.soft,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 32, height: 32, child: Center(child: _Glyph(shown))),
          const SizedBox(width: 8),
          Flexible(
            child: WholeWordText(text, textAlign: TextAlign.center, style: LtText.display(20)),
          ),
        ],
      ),
    );
    // A label for the screen reader: said when it changes (polite), except while Mochi talks, so
    // her voice is not read a second time.
    return Semantics(
      container: true,
      liveRegion: shown != VoiceLook.speaking,
      label: spoken,
      excludeSemantics: true,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        switchInCurve: const Cubic(.2, 0, 0, 1),
        child: content,
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.look);
  final VoiceLook look;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    switch (look) {
      case VoiceLook.speaking:
        const still = [0.45, 0.8, 1.0, 0.7, 0.4];
        Widget bars(List<double> h) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final v in h)
              Container(
                width: 4,
                height: 26 * v,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(color: VoiceColors.speak, borderRadius: BorderRadius.circular(2)),
              ),
          ],
        );
        if (reduced) return bars(still);
        return _Loop(
          duration: const Duration(milliseconds: 900),
          builder: (context, t) =>
              bars([for (var i = 0; i < 5; i++) 0.3 + 0.7 * (0.5 - 0.5 * math.cos(2 * math.pi * (t - i * 0.1667)))]),
        );
      case VoiceLook.listening:
        Widget dot([double ping = 0]) => Stack(
          alignment: Alignment.center,
          children: [
            if (ping > 0)
              Opacity(
                opacity: 0.5 * (1 - ping),
                child: Transform.scale(
                  scale: 1 + 1.6 * ping,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(color: VoiceColors.listen, shape: BoxShape.circle),
                  ),
                ),
              ),
            Container(
              key: const ValueKey('voice-live-dot'),
              width: 14,
              height: 14,
              decoration: const BoxDecoration(color: VoiceColors.listen, shape: BoxShape.circle),
            ),
          ],
        );
        final well = Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: VoiceColors.dotWell, shape: BoxShape.circle),
        );
        if (reduced) return Stack(alignment: Alignment.center, children: [well, dot()]);
        return _Loop(
          duration: const Duration(milliseconds: 1600),
          builder: (context, t) =>
              Stack(alignment: Alignment.center, children: [well, dot(const Cubic(0, 0, .2, 1).transform(t))]),
        );
      case VoiceLook.thinking:
        Widget dots(double Function(int) lift) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Transform.translate(
                offset: Offset(0, -5 * lift(i)),
                child: Opacity(
                  opacity: 0.45 + 0.55 * lift(i),
                  child: Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: const BoxDecoration(color: LtColors.ink, shape: BoxShape.circle),
                  ),
                ),
              ),
          ],
        );
        if (reduced) return dots((_) => 1);
        return _Loop(
          duration: const Duration(milliseconds: 1200),
          builder: (context, t) => dots((i) => 0.5 - 0.5 * math.cos(2 * math.pi * (t - i * 0.125))),
        );
      case VoiceLook.micOff:
        return const Icon(Icons.mic_off_rounded, size: 24, color: LtColors.ink);
      default:
        return Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: VoiceColors.wait, width: 2),
          ),
        );
    }
  }
}

/// "Mochi listens only on this screen." (honest copy: no "recording", no retention claims).
class ListeningNote extends StatelessWidget {
  const ListeningNote({super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const ExcludeSemantics(child: Icon(Icons.smartphone_rounded, size: 22, color: LtColors.secondary)),
      const SizedBox(width: 10),
      Expanded(
        child: Text('Mochi listens only on this screen.', style: LtText.body(size: 17, color: LtColors.secondary)),
      ),
    ],
  );
}

/// The words heard. While the microphone is open ([listening]) it has the teal outline, the last
/// word is softer until it settles, and a caret blinks; afterwards it is "You said".
class TranscriptCard extends StatelessWidget {
  const TranscriptCard({super.key, required this.text, required this.listening});

  final String text;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final words = text.trim().split(RegExp(r'\s+'));
    final ink = LtText.body(size: 22);
    final soft = ink.copyWith(color: LtColors.secondary);
    final spans = <InlineSpan>[
      if (listening) ...[
        TextSpan(text: words.length > 1 ? '${words.sublist(0, words.length - 1).join(' ')} ' : '', style: ink),
        TextSpan(text: words.last, style: soft),
      ] else
        TextSpan(text: '“$text”', style: ink),
    ];
    return Semantics(
      container: true,
      // Only the final words are announced (polite); the partials are not read word by word.
      liveRegion: !listening,
      label: listening ? 'Hearing you: $text' : 'You said: $text',
      excludeSemantics: true,
      child: Container(
        key: ValueKey(listening ? 'transcript-live' : 'transcript-final'),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        decoration: BoxDecoration(
          color: VoiceColors.transcript,
          borderRadius: BorderRadius.circular(LtRadii.tile),
          border: Border.all(
            color: listening ? VoiceColors.listen : LtColors.container,
            width: listening ? 2 : LtBorders.container,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(listening ? 'Hearing you…' : 'You said', style: LtText.body(size: 17, color: LtColors.secondary)),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(
                children: [
                  ...spans,
                  if (listening)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: _Caret(still: reduced),
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

class _Caret extends StatelessWidget {
  const _Caret({required this.still});
  final bool still;

  @override
  Widget build(BuildContext context) {
    final bar = Container(width: 2, height: 24, margin: const EdgeInsets.only(left: 3), color: LtColors.ink);
    if (still) return bar;
    return _Loop(
      duration: const Duration(milliseconds: 1000),
      builder: (context, t) => Opacity(opacity: t < .5 ? 1 : 0, child: bar),
    );
  }
}

/// Mochi's one nudge, as the smaller caption under the question.
class NudgeCaption extends StatelessWidget {
  const NudgeCaption({super.key, required this.line});
  final String line;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('nudge-caption'),
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
    decoration: BoxDecoration(
      color: LtColors.paper,
      borderRadius: BorderRadius.circular(LtRadii.tile),
      border: Border.all(color: LtColors.control, width: LtBorders.control),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mochi', style: LtText.body(size: 17, color: LtColors.secondary)),
        Text(line, style: LtText.body(size: 19)),
      ],
    ),
  );
}

/// Shown instead of the live look when VoiceOver is on and Mochi waits for a tap.
class VoiceOverInfo extends StatelessWidget {
  const VoiceOverInfo({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
    decoration: BoxDecoration(
      color: LtColors.mintWash,
      borderRadius: BorderRadius.circular(LtRadii.tile),
      border: Border.all(color: LtColors.container, width: LtBorders.container),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ExcludeSemantics(child: Icon(Icons.info_outline_rounded, size: 26, color: LtColors.ink)),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: LtText.body(size: 18),
              children: [
                TextSpan(
                  text: 'VoiceOver is on, so Mochi waits for your tap. ',
                  style: LtText.body(size: 18, weight: FontWeight.w700),
                ),
                const TextSpan(text: 'Then talk. Mochi listens until you pause.'),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
