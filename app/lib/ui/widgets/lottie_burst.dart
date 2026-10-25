import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// A UI Lottie from `assets/lottie/` (design/lottie/ui, manifest.json), played once, or
/// looped when [loop] is set. With Reduce Motion it is one still frame, never moving:
/// progress = [reducedFrame] / [frames], the manifest's `reduced_motion_frame`.
class LottieBurst extends StatefulWidget {
  const LottieBurst({
    super.key,
    required this.asset,
    required this.frames,
    required this.reducedFrame,
    this.duration = const Duration(seconds: 1),
    this.loop = false,
    this.size,
  });

  /// whatif_appear: a lilac halo behind the what-if twin that blooms and stays.
  const LottieBurst.whatIfAppear({super.key, this.size})
    : asset = 'assets/lottie/whatif_appear.json',
      frames = 60,
      reducedFrame = 59,
      duration = const Duration(milliseconds: 1000),
      loop = false;

  /// outlook_glow: a soft Sun-tint glow that blooms and fades when the outlook updates.
  const LottieBurst.outlookGlow({super.key, this.size})
    : asset = 'assets/lottie/outlook_glow.json',
      frames = 72,
      reducedFrame = 25,
      duration = const Duration(milliseconds: 1200),
      loop = false;

  /// thinking_dots: Mochi is thinking.
  const LottieBurst.thinkingDots({super.key, this.size})
    : asset = 'assets/lottie/thinking_dots.json',
      frames = 72,
      reducedFrame = 0,
      duration = const Duration(milliseconds: 1200),
      loop = true;

  final String asset;
  final int frames;
  final int reducedFrame;
  final Duration duration;
  final bool loop;
  final Size? size;

  @override
  State<LottieBurst> createState() => _LottieBurstState();
}

class _LottieBurstState extends State<LottieBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) return;
    widget.loop ? _c.repeat() : _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          width: widget.size?.width,
          height: widget.size?.height,
          child: still
              ? Lottie.asset(
                  widget.asset,
                  animate: false,
                  controller: AlwaysStoppedAnimation(widget.reducedFrame / widget.frames),
                )
              : Lottie.asset(widget.asset, controller: _c),
        ),
      ),
    );
  }
}
