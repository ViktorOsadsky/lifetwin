import 'package:flutter/material.dart';

import '../ui/widgets/widgets.dart';
import 'widgets.dart';

enum WellnessError {
  serverUnavailable(
    'A little pause',
    'Mochi can’t connect right now.',
    'Try again',
    Icons.cloud_off_rounded,
  ),
  microphoneDenied(
    'Typing works too',
    'Your microphone is off. You can keep going by typing.',
    'Type instead',
    Icons.mic_off_rounded,
  ),
  rateLimited(
    'A moment to breathe',
    'There’s a lot going on. Give it a moment.',
    'Try again',
    Icons.hourglass_empty_rounded,
  ),
  offline(
    'You’re offline',
    'Your saved history is still here.',
    'See my history',
    Icons.wifi_off_rounded,
  );

  const WellnessError(this.title, this.message, this.action, this.icon);
  final String title;
  final String message;
  final String action;
  final IconData icon;
}

class WellnessErrorScreen extends StatelessWidget {
  const WellnessErrorScreen({
    super.key,
    required this.error,
    required this.onAction,
    required this.onBack,
  });
  final WellnessError error;
  final VoidCallback onAction;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => WellnessPage(
    title: error.title,
    onBack: onBack,
    children: [
      Semantics(liveRegion: true, child: MochiMessage(message: error.message)),
      LipButton(label: error.action, icon: error.icon, onTap: onAction),
    ],
  );
}
