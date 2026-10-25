import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart' show TwinPose;
import '../ui/widgets/twin_sprite.dart';

/// With no profile, the conversation starts by itself: Mochi waves in the Room for a moment,
/// then [onStart] opens the onboarding screen (no tap). Once per [session]; backing out of
/// the conversation does not start it again. A new [session] (after "Delete my data") re-arms it.
///
/// Reduce Motion: no wave, [onStart] right away with `quick` true (a short crossfade).
/// VoiceOver: [announcement] is spoken first; the voice onboarding already waits for the reader.
class OnboardingAutoStart extends StatefulWidget {
  const OnboardingAutoStart({
    super.key,
    required this.child,
    required this.enabled,
    required this.session,
    required this.appearance,
    required this.onStart,
  });

  final Widget child;

  /// True when there is no profile and the app has finished loading what is on the phone.
  final bool enabled;
  final int session;
  final ValueListenable<TwinAppearance> appearance;
  final void Function(BuildContext context, {required bool quick}) onStart;

  static const wave = Duration(milliseconds: 1500);
  static const fade = Duration(milliseconds: 400);
  static const announcement = "Hi, I'm Mochi. Let's get started.";

  /// Reduce Motion: a quick crossfade into [page] (the screen is already at rest under it).
  static Future<T?> fadeIn<T>(BuildContext context, WidgetBuilder page) =>
      Navigator.of(context).push<T>(
        PageRouteBuilder<T>(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 150),
          reverseTransitionDuration: const Duration(milliseconds: 150),
          pageBuilder: (c, _, _) => page(c),
          transitionsBuilder: (_, a, _, child) =>
              FadeTransition(opacity: a, child: child),
        ),
      );

  @override
  State<OnboardingAutoStart> createState() => _OnboardingAutoStartState();
}

class _OnboardingAutoStartState extends State<OnboardingAutoStart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: OnboardingAutoStart.wave,
  );
  bool _handled = false;
  bool _showing = false;
  bool _leaving = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  @override
  void didUpdateWidget(OnboardingAutoStart old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      _timer?.cancel();
      _wave.stop();
      _handled = false;
      _showing = false;
      _leaving = false;
    }
    if (!widget.enabled && _showing && !_leaving) _cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  void _cancel() {
    _timer?.cancel();
    _wave.stop();
    setState(() => _showing = false);
  }

  void _maybeStart() {
    if (!mounted || !widget.enabled || _handled) {
      return;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      return; // something else is open
    }
    _handled = true;
    if (MediaQuery.accessibleNavigationOf(context)) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        OnboardingAutoStart.announcement,
        Directionality.of(context),
      );
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onStart(context, quick: true);
      return;
    }
    setState(() => _showing = true);
    _wave.repeat();
    _timer = Timer(OnboardingAutoStart.wave, _open);
  }

  void _open() {
    if (!mounted) return;
    _wave.stop();
    setState(
      () => _leaving = true,
    ); // fades out while the conversation comes in
    widget.onStart(context, quick: false);
    _timer = Timer(OnboardingAutoStart.fade, () {
      if (mounted) setState(() => _showing = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (_showing)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _leaving,
              child: AnimatedOpacity(
                opacity: _leaving ? 0 : 1,
                duration: OnboardingAutoStart.fade,
                child: _WaveCard(appearance: widget.appearance, wave: _wave),
              ),
            ),
          ),
      ],
    );
  }
}

class _WaveCard extends StatelessWidget {
  const _WaveCard({required this.appearance, required this.wave});
  final ValueListenable<TwinAppearance> appearance;
  final Animation<double> wave;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('autostart-wave'),
      color: LtColors.cream.withValues(alpha: 0.94),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: LtColors.paper,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: LtColors.creamLip, width: 2),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  'Hi! I\'m Mochi.',
                  style: TextStyle(
                    color: LtColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ExcludeSemantics(
              child: AnimatedBuilder(
                animation: wave,
                builder: (_, child) => Transform.rotate(
                  alignment: Alignment.bottomCenter,
                  angle: 0.07 * math.sin(wave.value * 2 * math.pi * 3),
                  child: child,
                ),
                child: ValueListenableBuilder<TwinAppearance>(
                  valueListenable: appearance,
                  builder: (_, look, _) => TwinSprite(
                    appearance: look,
                    pose: TwinPose.wave,
                    height: 240,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
