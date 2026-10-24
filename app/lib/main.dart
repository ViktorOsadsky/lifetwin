import 'package:flutter/material.dart';

import 'forecast/forecast_client.dart';
import 'forecast/forecast_screen.dart';
import 'health/health_screen.dart';
import 'health/health_summary.dart';
import 'onboarding/voice_onboarding_controller.dart';
import 'onboarding/voice_onboarding_screen.dart';
import 'theme/lifetwin_theme.dart';
import 'voice/cartesia_speech.dart';
import 'voice/http_conversation_guide.dart';
import 'voice/voice_token.dart';

void main() => runApp(const LifeTwinApp());

/// Temporary host until Track C's game shell lands: the mascot conversation is the
/// start screen, with a button to the Apple Health import.
class LifeTwinApp extends StatefulWidget {
  const LifeTwinApp({super.key, this.controller, this.forecastClient});

  /// Tests pass a controller built from fakes.
  final VoiceOnboardingController? controller;

  /// Tests pass a fake; otherwise POST /api/predict on the same server.
  final ForecastClient? forecastClient;

  @override
  State<LifeTwinApp> createState() => _LifeTwinAppState();
}

class _LifeTwinAppState extends State<LifeTwinApp> {
  // Start finding the server now, while the consent questions are on screen.
  late final ApiBase _api = ApiBase()..url().ignore();
  late final VoiceOnboardingController _controller = widget.controller ?? _live(_api);
  late final ForecastClient _forecast = widget.forecastClient ?? HttpForecastClient(base: _api);

  static VoiceOnboardingController _live(ApiBase api) {
    final tokens = VoiceTokenProvider(base: api);
    return VoiceOnboardingController(
      guide: HttpConversationGuide(base: api),
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
      debugShowCheckedModeBanner: false,
      theme: lifeTwinTheme(),
      home: Builder(
        builder: (context) => VoiceOnboardingScreen(
          controller: _controller,
          onUseHealth: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HealthImportScreen(
                onDone: (result) {
                  Navigator.of(context).pop();
                  // Each value was already checked on the Health screen ("Is this accurate?").
                  _controller.importHealth({for (final c in result.confirmed) c.field.profileKey: c.value});
                },
              ),
            ),
          ),
          onDone: (profile) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ForecastScreen(
                client: _forecast,
                profile: profile,
                // The mascot speaks only if the person chose voice and it still works.
                speech: _controller.voiceUsable && !_controller.typing ? _controller.output : null,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
