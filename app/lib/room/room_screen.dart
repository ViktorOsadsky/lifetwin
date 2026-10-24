import 'package:flutter/material.dart';

import '../theme/lifetwin_theme.dart';
import '../widgets/lt_buttons.dart';
import '../widgets/pip.dart';
import '../widgets/scene_paper.dart';
import '../widgets/speech_bubble.dart';
import '../widgets/twin.dart';

/// Home screen (Main.dc.html, "Room"): the twin and Pip in the paper scene, Pip's one
/// short sentence, and two big buttons. Nothing here is stored; [hasProfile] is whatever
/// the host kept in memory for this session.
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.hasProfile, required this.onTalk, required this.onForecast});

  /// True once an intake has been confirmed this session.
  final bool hasProfile;

  /// "Talk with Pip": the voice onboarding flow.
  final VoidCallback onTalk;

  /// "See my forecast", only called when [hasProfile].
  final VoidCallback onForecast;

  static const firstGreeting = "Hi! I'm Pip. Shall we talk?";
  static const returningGreeting = 'Welcome back.';
  static const talkFirst = "Let's talk first, so I can make your forecast.";

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  bool _needTalk = false;

  String get _line => _needTalk && !widget.hasProfile
      ? RoomScreen.talkFirst
      : widget.hasProfile
      ? RoomScreen.returningGreeting
      : RoomScreen.firstGreeting;

  void _forecast() {
    if (widget.hasProfile) {
      widget.onForecast();
    } else {
      setState(() => _needTalk = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The bubble is 146 pt wide in the scene; with much larger text it moves above the
    // scene at full width so nothing is cut off or covers Pip.
    final large = MediaQuery.textScalerOf(context).scale(20) > 28;
    final bubble = Semantics(
      liveRegion: true,
      label: 'Pip says: $_line',
      excludeSemantics: true,
      child: SpeechBubble(
        tail: BubbleTail.down,
        tailOffset: large ? 120 : 66,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        radius: const BorderRadius.all(Radius.circular(22)),
        child: Text(_line, style: LtText.bodySmall.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Semantics(
                      container: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(header: true, child: Text('Your room', style: LtText.display)),
                          const SizedBox(height: 6),
                          Text('Good to see you.', style: LtText.body.copyWith(fontSize: 21, height: 1.35)),
                        ],
                      ),
                    ),
                  ),
                  if (large) Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 0), child: bubble),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ScenePaper(
                      kind: SceneKind.room,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Positioned(left: 50, top: 40, child: Twin()),
                          const Positioned(left: 242, top: 190, child: Pip(height: 128, label: 'Pip')),
                          if (!large) Positioned(left: 222, top: 78, width: 146, child: bubble),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),
                    child: Column(
                      children: [
                        LtPrimaryButton(
                          label: 'Talk with Pip',
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 40, color: LtColors.ink),
                          onPressed: widget.onTalk,
                        ),
                        const SizedBox(height: 22),
                        LtSecondaryButton(
                          label: 'See my forecast',
                          icon: const Icon(Icons.auto_awesome_outlined, size: 34, color: LtColors.ink),
                          onPressed: _forecast,
                        ),
                      ],
                    ),
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
