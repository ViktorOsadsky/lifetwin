import 'package:flutter/material.dart';

import 'forecast/forecast_client.dart';
import 'forecast/forecast_screen.dart';
import 'health/health_reader.dart';
import 'health/health_screen.dart';
import 'health/health_summary.dart';
import 'onboarding/voice_onboarding_controller.dart';
import 'onboarding/voice_onboarding_screen.dart';
import 'room/room_screen.dart';
import 'theme/lifetwin_theme.dart';
import 'voice/cartesia_speech.dart';
import 'voice/http_conversation_guide.dart';
import 'voice/voice_token.dart';

void main() => runApp(const LifeTwinApp());

/// Temporary host until Track C's game shell lands: the Room is the start screen; its
/// buttons lead to the mascot conversation (which can open the Apple Health import) and
/// the forecast. The confirmed profile is kept in memory for this session only.
class LifeTwinApp extends StatefulWidget {
  const LifeTwinApp({super.key, this.controller, this.forecastClient, this.healthReader});

  /// Tests pass a controller built from fakes.
  final VoiceOnboardingController? controller;

  /// Tests pass a fake; otherwise POST /api/predict on the same server.
  final ForecastClient? forecastClient;

  /// Tests pass a fake; otherwise Apple Health.
  final HealthReader? healthReader;

  @override
  State<LifeTwinApp> createState() => _LifeTwinAppState();
}

class _LifeTwinAppState extends State<LifeTwinApp> {
  // Start finding the server now, while the consent questions are on screen.
  late final ApiBase _api = ApiBase()..url().ignore();
  late final VoiceOnboardingController _controller = widget.controller ?? _live(_api);
  late final ForecastClient _forecast = widget.forecastClient ?? HttpForecastClient(base: _api);

  /// The answers a forecast uses: whatever the conversation holds now, once finished.
  /// Read live, so "start over" or a changed answer never leaves an older forecast behind.
  Map<String, dynamic>? get _profile => _controller.turn?.complete == true ? _controller.confirmedProfile : null;

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
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => RoomScreen(
          hasProfile: _profile != null,
          onTalk: () => _talk(context),
          onForecast: () => _showForecast(context, replaceStack: false),
        ),
      ),
    );
  }

  /// [replace] swaps the forecast for the conversation ("Go back to my answers").
  void _talk(BuildContext context, {bool replace = false}) {
    final nav = Navigator.of(context);
    final route = MaterialPageRoute<void>(
      builder: (talkContext) => VoiceOnboardingScreen(
        controller: _controller,
        onUseHealth: () => Navigator.of(talkContext).push(
          MaterialPageRoute<void>(
            builder: (_) => HealthImportScreen(
              reader: widget.healthReader,
              onDone: (result) {
                Navigator.of(talkContext).pop();
                // Each value was already checked on the Health screen ("Is this accurate?").
                _controller.importHealth({for (final c in result.confirmed) c.field.profileKey: c.value});
              },
            ),
          ),
        ),
        onDone: (_) => _showForecast(talkContext, replaceStack: true),
      ),
    );
    if (replace) {
      nav.pushReplacement(route);
    } else {
      nav.push(route);
    }
  }

  /// From the intake's Continue ([replaceStack]) the conversation is dropped, so the
  /// forecast's Back lands on the Room; from the Room it is simply pushed.
  void _showForecast(BuildContext context, {required bool replaceStack}) {
    final route = MaterialPageRoute<void>(
      builder: (forecastContext) => ForecastScreen(
        client: _forecast,
        profile: _profile!,
        // The mascot speaks only if the person chose voice and it still works.
        speech: _controller.voiceUsable && !_controller.typing ? _controller.output : null,
        onBack: () => Navigator.of(forecastContext).pop(),
        onAnswers: () => _talk(forecastContext, replace: true),
      ),
    );
    final nav = Navigator.of(context);
    if (replaceStack) {
      nav.pushAndRemoveUntil(route, (r) => r.isFirst);
    } else {
      nav.push(route);
    }
  }
}
