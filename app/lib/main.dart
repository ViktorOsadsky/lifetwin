import 'package:flutter/material.dart';

import 'health/health_screen.dart';
import 'health/health_summary.dart';
import 'onboarding/voice_onboarding_controller.dart';
import 'onboarding/voice_onboarding_screen.dart';
import 'voice/cartesia_speech.dart';
import 'voice/http_conversation_guide.dart';
import 'voice/voice_token.dart';

void main() => runApp(const LifeTwinApp());

/// Temporary host until Track C's game shell lands: the mascot conversation is the
/// start screen, with a button to the Apple Health import.
class LifeTwinApp extends StatefulWidget {
  const LifeTwinApp({super.key, this.controller});

  /// Tests pass a controller built from fakes.
  final VoiceOnboardingController? controller;

  @override
  State<LifeTwinApp> createState() => _LifeTwinAppState();
}

class _LifeTwinAppState extends State<LifeTwinApp> {
  late final VoiceOnboardingController _controller = widget.controller ?? _live();

  static VoiceOnboardingController _live() {
    final tokens = VoiceTokenProvider();
    return VoiceOnboardingController(
      guide: HttpConversationGuide(),
      input: CartesiaSpeechInput(tokens: tokens),
      output: CartesiaSpeechOutput(tokens: tokens),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LifeTwin',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2F5BD3), useMaterial3: true),
      home: Builder(
        builder: (context) => VoiceOnboardingScreen(
          controller: _controller,
          onUseHealth: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => HealthImportScreen(onDone: (result) {
              Navigator.of(context).pop();
              // Each value was already checked on the Health screen ("Is this accurate?").
              _controller.importHealth({for (final c in result.confirmed) c.field.profileKey: c.value});
            }),
          )),
          onDone: (profile) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(days: 1),
            showCloseIcon: true,
            content: Text('Confirmed ${profile.length} answers.'),
          )),
        ),
      ),
    );
  }
}
