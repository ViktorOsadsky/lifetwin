import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart';
import 'night_plate.dart';

/// V-8 ceremony before the fortune: the chosen twin (bear or human) holds
/// the ball on the night plate. "Ask the ball" plays two slow glow pulses (about 1.2 s each), then
/// hands off to the result. Reduced motion: no pulses, straight to the result
/// (the route crossfades).
class FortuneCeremonyScreen extends StatefulWidget {
  const FortuneCeremonyScreen({
    super.key,
    required this.onAsk,
    required this.onBack,
    this.appearance = const TwinAppearance(),
  });

  final VoidCallback onAsk;
  final VoidCallback onBack;

  /// Cosmetic look of the twin.
  final TwinAppearance appearance;

  @override
  State<FortuneCeremonyScreen> createState() => _FortuneCeremonyScreenState();
}

class _FortuneCeremonyScreenState extends State<FortuneCeremonyScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _asking = false;

  Future<void> _ask() async {
    if (_asking) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onAsk();
      return;
    }
    setState(() => _asking = true);
    await _glow.forward(from: 0);
    if (!mounted) return;
    widget.onAsk();
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // With much larger text the bubble leaves the window for the sheet, so it is never cut off.
    final large = MediaQuery.textScalerOf(context).scale(20) > 28;
    final bubble = Bubble(
      text: _asking ? 'The ball is glowing…' : 'Want to peek ahead?',
      fontSize: 25,
      tail: large ? BubbleTail.none : BubbleTail.bottom,
      tailAt: 0.75,
      liveRegion: true,
    );
    return ModeScaffold(
      mode: LtMode.fortune,
      child: PlateSheetLayout(
        minWindow: 160,
        window: PlateWindow(
          night: true,
          name: widget.appearance.name,
          // Two ease-in-out pulses of the ball's glow; no flashes.
          plate: AnimatedBuilder(
            animation: _glow,
            builder: (context, _) {
              final pulse = math.sin(_glow.value * 4 * math.pi - math.pi / 2) * 0.5 + 0.5;
              return NightTwinPlate(
                appearance: widget.appearance,
                pose: TwinPose.holdBall,
                glow: _asking ? 0.55 + 0.45 * Curves.easeInOut.transform(pulse) : 0.55,
                feetAt: const Offset(0.6, 0.9),
              );
            },
          ),
          overlay: large
              ? null
              : Stack(
                  children: [
                    Positioned(
                      left: 30,
                      top: 110,
                      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 210), child: bubble),
                    ),
                  ],
                ),
        ),
        sheet: Sheet(
          night: true,
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (large) ...[bubble, const SizedBox(height: 14)],
              LipButton(
                label: 'Ask the ball',
                icon: Icons.auto_awesome_rounded,
                fontSize: 24,
                onTap: _asking ? null : _ask,
              ),
              const SizedBox(height: 10),
              LipButton(
                label: 'Back to room',
                icon: Icons.home_rounded,
                kind: LipKind.secondary,
                height: 56,
                fontSize: 21,
                onTap: _asking ? null : widget.onBack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
