import 'package:flutter/material.dart';

import 'customize/customize_screen.dart';
import 'agentic_routes.dart';
import 'forecast/forecast_client.dart';
import 'forecast/forecast_screen.dart';
import 'forecast/fortune_ceremony_screen.dart';
import 'health/health_reader.dart';
import 'health/health_screen.dart';
import 'health/health_summary.dart';
import 'onboarding/voice_onboarding_controller.dart';
import 'onboarding/voice_onboarding_screen.dart';
import 'room/room_screen.dart';
import 'twin/twin_repository.dart';
import 'ui/swoosh_route.dart';
import 'ui/theme.dart';
import 'ui/twin_appearance.dart';
import 'ui/twin_assets.dart';
import 'voice/cartesia_speech.dart';
import 'voice/http_conversation_guide.dart';
import 'voice/voice_token.dart';

void main() => runApp(const LifeTwinApp());

/// The game shell: the Room is home; Talk opens the mascot conversation
/// (with the Apple Health import), Fortune the magic ball, Customize the look.
/// The confirmed profile, check-in history and twin look are kept on the phone only
/// (lib/twin/twin_store.dart); the forecast runs on the phone (lib/twin/).
class LifeTwinApp extends StatefulWidget {
  const LifeTwinApp({super.key, this.controller, this.forecastClient, this.healthReader, this.appearance, this.twin, this.agentic});

  /// Tests pass a controller built from fakes.
  final VoiceOnboardingController? controller;

  /// Tests pass a fake; otherwise the on-device model.
  final ForecastClient? forecastClient;

  /// Tests may pass one; otherwise the model is loaded and the store opened at startup.
  final Future<TwinRepository>? twin;

  /// The agentic screens' shell (check-ins, Experiment, pills). Tests pass one with fake clients.
  final AgenticRoutes? agentic;

  /// Tests pass a fake; otherwise Apple Health.
  final HealthReader? healthReader;

  /// Tests may pass the look; otherwise the default bear in the Cal hat.
  final ValueNotifier<TwinAppearance>? appearance;

  @override
  State<LifeTwinApp> createState() => _LifeTwinAppState();
}

class _LifeTwinAppState extends State<LifeTwinApp> {
  // Start finding the server now, while the Room is on screen.
  late final ApiBase _api = ApiBase()..url().ignore();
  late final VoiceOnboardingController _controller = widget.controller ?? _live(_api);
  // Loaded once, at startup.
  late final Future<TwinRepository> _twin = widget.twin ?? TwinRepository.open();
  late final ForecastClient _forecast = widget.forecastClient ?? OnDeviceForecastClient(_twin);

  late final AgenticRoutes _agentic = widget.agentic ?? AgenticRoutes(look: _look, api: _api);

  /// The profile saved on the phone by an earlier session, once the store is open.
  Map<String, dynamic>? _stored;

  /// Cosmetic only; never merged into the confirmed profile.
  late final ValueNotifier<TwinAppearance> _look = widget.appearance ?? ValueNotifier(const TwinAppearance());

  /// Profile keys that came from Apple Health, to label their source.
  final _healthKeys = <String>{};

  /// The answers a forecast uses: whatever the conversation holds now, once finished.
  /// Read live, so "start over" or a changed answer never leaves an older forecast behind.
  /// Before this session's conversation starts, the profile saved on the phone is used.
  Map<String, dynamic>? get _profile =>
      _controller.turn == null ? _stored : (_controller.turn!.complete ? _controller.confirmedProfile : null);

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
  void initState() {
    super.initState();
    _twin.then((repo) {
      if (!mounted) return;
      final look = repo.store.twin;
      if (look != null && widget.appearance == null) _look.value = _appearanceFrom(look);
      _look.addListener(() => repo.saveTwinLook(_appearanceJson(_look.value)).ignore());
      setState(() {
        _agentic.attach(repo);
        if (repo.store.hasProfile) _stored = repo.store.profile;
      });
    }, onError: (Object e) => debugPrint('LifeTwin model or store did not load: $e'));
  }

  static Map<String, dynamic> _appearanceJson(TwinAppearance a) => {
    'type': a.type.name,
    'look': a.look.slug,
    'name': a.name,
  };

  static TwinAppearance _appearanceFrom(Map<String, dynamic> j) => TwinAppearance(
    type: TwinType.values.firstWhere((t) => t.name == j['type'], orElse: () => TwinType.bear),
    look: TwinLook.values.firstWhere((l) => l.slug == j['look'], orElse: () => TwinLook.calHat),
    name: j['name'] as String?,
  );

  /// Keeps the finished conversation's answers on the phone.
  void _keepProfile(Map<String, dynamic> p) {
    _twin.then((repo) => repo.saveConversationProfile(p)).ignore();
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
      onDone: (profile) {
        _keepProfile(profile);
        _ceremony(talkContext, fromTalk: true);
      },
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
      builder: _agentic.wrap,
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => RoomScreen(
          appearance: _look,
          hasProfile: _profile != null,
          onUseHealth: _healthKeys.isEmpty ? () => _health(context) : null,
          onTalk: () => _talk(context),
          onCustomize: () => _customize(context),
          onFortune: () => _ceremony(context),
          outlook: _outlook,
          extraPills: _agentic.pills(context),
        ),
      ),
    );
  }
}
