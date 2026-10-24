import 'package:flutter/material.dart';

import 'customize/customize_screen.dart';
import 'documents/document_screen.dart';
import 'documents/document_extract.dart';
import 'documents/document_upload.dart';
import 'forecast/forecast_client.dart';
import 'forecast/forecast_screen.dart';
import 'forecast/fortune_ceremony_screen.dart';
import 'health/health_reader.dart';
import 'health/health_screen.dart';
import 'health/health_summary.dart';
import 'onboarding/voice_onboarding_controller.dart';
import 'onboarding/voice_onboarding_screen.dart';
import 'room/room_screen.dart';
import 'ui/swoosh_route.dart';
import 'ui/theme.dart';
import 'ui/twin_appearance.dart';
import 'voice/cartesia_speech.dart';
import 'voice/http_conversation_guide.dart';
import 'voice/voice_token.dart';

void main() => runApp(const LifeTwinApp());

/// The game shell: the Room is home; Talk opens the mascot conversation
/// (with the Apple Health import), Fortune the magic ball, Customize the look.
/// The confirmed profile is kept in memory for this session only.
class LifeTwinApp extends StatefulWidget {
  const LifeTwinApp({
    super.key,
    this.controller,
    this.forecastClient,
    this.healthReader,
    this.documentService,
    this.appearance,
  });

  /// Tests pass a controller built from fakes.
  final VoiceOnboardingController? controller;

  /// Tests pass a fake; otherwise POST /api/predict on the same server.
  final ForecastClient? forecastClient;

  /// Tests pass a fake; otherwise Apple Health.
  final HealthReader? healthReader;

  /// Tests pass fakes; otherwise Vision on the phone and POST /api/documents/extract.
  final DocumentUploadService? documentService;

  /// Tests may pass the look; otherwise the default bear in the Cal hat.
  final ValueNotifier<TwinAppearance>? appearance;

  @override
  State<LifeTwinApp> createState() => _LifeTwinAppState();
}

class _LifeTwinAppState extends State<LifeTwinApp> {
  // Start finding the server now, while the Room is on screen.
  late final ApiBase _api = ApiBase()..url().ignore();
  late final VoiceOnboardingController _controller = widget.controller ?? _live(_api);
  late final ForecastClient _forecast = widget.forecastClient ?? HttpForecastClient(base: _api);

  /// Cosmetic only; never merged into the confirmed profile.
  late final ValueNotifier<TwinAppearance> _look = widget.appearance ?? ValueNotifier(const TwinAppearance());

  /// Profile keys that came from Apple Health, to label their source.
  final _healthKeys = <String>{};

  /// The answers a forecast uses: whatever the conversation holds now, once finished.
  /// Read live, so "start over" or a changed answer never leaves an older forecast behind.
  Map<String, dynamic>? get _profile => _controller.turn?.complete == true ? _controller.confirmedProfile : null;

  /// The last supported forecast, for the Room's outlook card.
  final _outlook = ValueNotifier<Forecast?>(null);

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
    if (widget.appearance == null) _look.dispose();
    _outlook.dispose();
    super.dispose();
  }

  void _toRoom(BuildContext context) => Navigator.of(context).popUntil((r) => r.isFirst);

  /// The conversation, swooshing up from the Room.
  void _talk(BuildContext context) => SwooshRoute.push<void>(
    context,
    (talkContext) => VoiceOnboardingScreen(
      controller: _controller,
      appearance: _look.value,
      onUseHealth: () => _health(talkContext),
      onDone: (_) => _ceremony(talkContext, fromTalk: true),
    ),
  );

  /// The Apple Health import, from the conversation or the Room. From the Room, before the
  /// conversation started, the checked values wait for its first question.
  void _health(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HealthImportScreen(
        reader: widget.healthReader,
        onDone: (result) async {
          Navigator.of(context).pop();
          // Each value was already checked on the Health screen ("Is this accurate?").
          final values = {for (final c in result.confirmed) c.field.profileKey: c.value};
          // Only once the values were taken (sent and accepted, or queued for the start of
          // the talk) are they labelled "Apple Health" and does the Room's pill go away.
          if (await _controller.importHealth(values) && mounted) setState(() => _healthKeys.addAll(values.keys));
        },
      ),
    ),
  );

  /// Health-document upload, separate from Apple Health. Only values the person confirmed
  /// one by one reach the conversation; it then asks only for what is still missing.
  void _documents(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DocumentUploadScreen(
        service: widget.documentService ?? liveDocumentService(extractor: HttpDocumentExtractor(base: _api)),
        onDone: (result) async {
          Navigator.of(context).pop();
          final values = result.profileValues;
          if (values.isNotEmpty) await _controller.importDocument(values);
        },
      ),
    ),
  );

  /// The ceremony, then the fortune. From the intake's Continue ([fromTalk]) the
  /// conversation is dropped, so Back lands on the Room; from the Room it is pushed.
  /// Completes when the person is back on the Room.
  Future<void> _ceremony(BuildContext context, {bool fromTalk = false}) {
    final nav = Navigator.of(context);
    final route = MaterialPageRoute<void>(
      builder: (ceremonyContext) => FortuneCeremonyScreen(
        appearance: _look.value,
        onBack: () => _toRoom(ceremonyContext),
        onAsk: () => Navigator.of(ceremonyContext).pushReplacement(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 400),
            pageBuilder: (forecastContext, _, _) => ForecastScreen(
              client: _forecast,
              profile: _profile ?? const {},
              appearance: _look.value,
              healthKeys: {..._healthKeys},
              onResult: (f) {
                if (f.supported) _outlook.value = f;
              },
              // The mascot speaks only if the person chose voice and it still works.
              speech: _controller.voiceUsable && !_controller.typing ? _controller.output : null,
              onBack: () => _toRoom(forecastContext),
              // "Go back to my answers": the conversation, where an answer can be changed.
              onAnswers: () {
                _toRoom(forecastContext);
                _talk(forecastContext);
              },
            ),
            transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
          ),
        ),
      ),
    );
    return fromTalk ? nav.pushAndRemoveUntil(route, (r) => r.isFirst) : nav.push(route);
  }

  void _customize(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CustomizeScreen(appearance: _look, onDone: () => Navigator.of(context).pop()),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LifeTwin',
      debugShowCheckedModeBanner: false,
      theme: lifeTwinTheme(),
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => RoomScreen(
          appearance: _look,
          hasProfile: _profile != null,
          onUseHealth: _healthKeys.isEmpty ? () => _health(context) : null,
          onUploadDocument: () => _documents(context),
          onTalk: () => _talk(context),
          onCustomize: () => _customize(context),
          onFortune: () => _ceremony(context),
          outlook: _outlook,
        ),
      ),
    );
  }
}
