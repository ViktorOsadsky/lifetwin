import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

import 'band/band_file_session.dart';

import 'checkin/check_in_entry.dart';
import 'checkin/checkin_reminders.dart';
import 'checkin/checkin_screen.dart' show ReminderOfferCard;
import 'checkin/consents.dart' show AiProvider;
import 'customize/customize_screen.dart';
import 'demo/demo_seed.dart';
import 'agentic_routes.dart';
import 'documents/document_screen.dart';
import 'documents/document_extract.dart';
import 'documents/document_upload.dart';
import 'forecast/forecast_client.dart';
import 'forecast/forecast_screen.dart';
import 'forecast/fortune_ceremony_screen.dart';
import 'health/health_reader.dart';
import 'health/health_screen.dart';
import 'health/health_summary.dart';
import 'onboarding/onboarding_autostart.dart';
import 'onboarding/voice_onboarding_controller.dart';
import 'onboarding/voice_onboarding_screen.dart';
import 'room/room_screen.dart';
import 'quiz/quiz_game.dart';
import 'quiz/quiz_screen.dart';
import 'wellness/home_panel.dart' show HealthScoreSummary;
import 'wellness/lifespan_block.dart';
import 'wellness/models.dart';
import 'wellness/settings_screen.dart';
import 'wellness/widgets.dart' show WellnessCard;
import 'wellness/repository_adapter.dart';
import 'wellness/history_screen.dart';
import 'twin/twin_repository.dart';
import 'ui/swoosh_route.dart';
import 'ui/widgets/home_button.dart' show HomeDepth;
import 'ui/theme.dart';
import 'ui/twin_appearance.dart';
import 'ui/twin_assets.dart';
import 'voice/cartesia_speech.dart';
import 'voice/http_conversation_guide.dart';
import 'voice/voice_token.dart';

void main() => runApp(const LifeTwinApp(autoStartOnboarding: true));

/// The game shell: the Room is home; Talk opens the mascot conversation
/// (with the Apple Health import), Fortune the magic ball, Customize the look.
/// The confirmed profile, check-in history and twin look are kept on the phone only
/// (lib/twin/twin_store.dart); the forecast runs on the phone (lib/twin/).
class LifeTwinApp extends StatefulWidget {
  const LifeTwinApp({
    super.key,
    this.controller,
    this.forecastClient,
    this.healthReader,
    this.documentService,
    this.appearance,
    this.twin,
    this.agentic,
    this.autoStartOnboarding = false,
  });

  /// Tests pass a controller built from fakes.
  final VoiceOnboardingController? controller;

  /// Tests pass a fake; otherwise the on-device model.
  final ForecastClient? forecastClient;

  /// Tests may pass one; otherwise the model is loaded and the store opened at startup.
  final Future<TwinRepository>? twin;

  /// The agentic screens' shell (check-ins, Experiment, pills). Tests pass one with fake clients.
  final AgenticRoutes? agentic;

  /// With no profile, the conversation opens by itself after a short Mochi wave (the real app; tests opt in).
  final bool autoStartOnboarding;

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
  // Loaded once, at startup.
  late final Future<TwinRepository> _twin =
      widget.twin ?? openTwin(reminders: CheckinReminders(LocalNotificationPort()));
  late final ForecastClient _forecast =
      widget.forecastClient ?? OnDeviceForecastClient(_twin, modelInputs: () => _saved ? null : _controller.modelInputs);

  late final AgenticRoutes _agentic =
      widget.agentic ??
      AgenticRoutes(
        look: _look,
        api: _api,
        voice: () => _controller,
        onDeleted: _afterDelete,
        documentService: widget.documentService == null ? null : () => widget.documentService!,
        healthSamples: connectedHealthSamples(
          widget.healthReader ?? HealthReader(),
          () =>
              _healthKeys.isNotEmpty ||
              (_agentic.repo?.history().any((e) => e.source == HistorySource.appleHealth) ?? false),
        ),
      );

  /// The outside AI provider (for the training line on the AI-helper question), once known.
  AiProvider? _aiProvider;

  /// "Delete my data" wiped the phone: forget what this session held in memory too, so the app is
  /// as on a fresh install (the Room with no profile; Talk starts at the voice question).
  void _afterDelete() {
    _autoStartSession++; // the conversation may start by itself again, once
    _look.removeListener(_saveLook); // the default look must not be written back to the phone
    _look.value = const TwinAppearance();
    _look.addListener(_saveLook);
    _quiz?.dispose();
    _quiz = null;
    _openingQuiz = false;
    _reminderOffer = null;
    _aiProvider = null;
    _agentic.provider().then((p) => _aiProvider = p, onError: (Object _) {});
    setState(() {
      _stored = null;
      _saved = false;
      _healthKeys.clear();
      _healthValues.clear();
      _healthEstimatedKeys.clear();
      _documentValues.clear();
      _outlook.value = null;
      _controller.resetConversation();
    });
  }

  /// The profile saved on the phone by an earlier session, once the store is open.
  Map<String, dynamic>? _stored;
  RepositoryWellness? _wellness;

  /// Cosmetic only; never merged into the confirmed profile.
  late final ValueNotifier<TwinAppearance> _look = widget.appearance ?? ValueNotifier(const TwinAppearance());

  /// Profile keys that came from Apple Health, to label their source.
  final _healthKeys = <String>{};
  QuizGame? _quiz;
  bool _openingQuiz = false;

  Future<void> _playQuiz(BuildContext context) async {
    if (_openingQuiz) return;
    _openingQuiz = true;
    try {
      if (_quiz == null) {
        final questions = await loadReviewedQuiz();
        if (!mounted) return;
        _quiz = QuizGame(questions);
      }
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (c) => QuizScreen(
            game: _quiz,
            appearance: _look.value,
            onBack: () => Navigator.of(c).pop(),
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The quiz needs a moment. Try again soon.'),
          ),
        );
      }
    } finally {
      _openingQuiz = false;
    }
  }

  /// The Apple Health values taken this session, so a value is labelled Apple Health only
  /// while the confirmed answer is still that value.
  final _healthValues = <String, Object?>{};
  final _healthEstimatedKeys = <String>{};

  /// The same for values the person confirmed from an uploaded document.
  final _documentValues = <String, Object?>{};

  /// The answers a forecast uses: whatever the conversation holds now, once finished.
  /// Read live, so "start over" or a changed answer never leaves an older forecast behind.
  /// Before this session's conversation starts, the profile saved on the phone is used.
  ///
  /// Once the finished intake is saved on the phone ([_saved]) the saved profile is read instead, so
  /// a later change through Mochi or a weekly check-in shows in the forecast, not the old intake.
  Map<String, dynamic>? get _profile {
    final turn = _controller.turn;
    if (turn != null && !(turn.complete && _saved)) return turn.complete ? _controller.confirmedProfile : null;
    final repo = _wellness?.repository;
    return repo == null ? _stored : (repo.store.hasProfile ? repo.profile : null);
  }

  /// The last supported forecast, for the Room's outlook card.
  final _outlook = ValueNotifier<Forecast?>(null);

  /// The finished intake is on the phone, so the saved profile (not the intake's answers and its
  /// `model_inputs`) is what the forecast reads. Cleared when the conversation is reopened.
  bool _saved = false;

  /// Fills [_outlook] from the phone's own current assessment, so the Room never shows an older
  /// number after a change. Not while an intake is still running.
  void _syncOutlook() {
    final a = _wellness?.repository.current;
    final turn = _controller.turn;
    if (a == null || (turn != null && !turn.complete)) return;
    final f = Forecast.fromAssessment(a);
    _outlook.value = f.supported ? f : null;
  }

  void _intakeChanged() {
    final turn = _controller.turn;
    if (turn != null && !turn.complete) _saved = false;
  }

  static VoiceOnboardingController _live(ApiBase api) {
    final tokens = VoiceTokenProvider(base: api);
    return VoiceOnboardingController(
      guide: HttpConversationGuide(base: api),
      input: CartesiaSpeechInput(tokens: tokens),
      output: CartesiaSpeechOutput(tokens: tokens),
      handsFree: true,
    );
  }

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      BandFileSession.instance.start().ignore();
    }
    _agentic.provider().then((p) => _aiProvider = p, onError: (Object _) {});
    _twin.then((repo) {
      if (!mounted) return;
      final look = repo.store.twin;
      if (look != null && widget.appearance == null) _look.value = _appearanceFrom(look);
      _look.addListener(_saveLook);
      repo.addListener(_syncOutlook);
      _controller.addListener(_intakeChanged);
      setState(() {
        _wellness = RepositoryWellness(repo);
        _agentic.attach(repo);
        if (repo.store.hasProfile) _stored = repo.store.profile;
      });
      _syncOutlook();
    }, onError: (Object e) => debugPrint('LifeTwin model or store did not load: $e'));
  }

  void _saveLook() => _wellness?.repository.saveTwinLook(_appearanceJson(_look.value)).ignore();

  void _history(BuildContext context) {
    final adapter = _wellness;
    if (adapter == null) return;
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (c) => ListenableBuilder(
      listenable: adapter,
      builder: (_, _) => HistoryScreen(days: adapter.historyDays(), goodWeeks: adapter.repository.goodWeeks(), now: DateTime.now(),
        onBack: () => Navigator.of(c).pop(), onTalk: () { Navigator.of(c).pop(); _talk(context); }),
    )));
  }

  static Map<String, dynamic> _appearanceJson(TwinAppearance a) => {
    'type': a.type.name,
    'look': a.look.slug,
    'name': a.name,
    'room': a.room.name,
  };

  static TwinAppearance _appearanceFrom(Map<String, dynamic> j) => TwinAppearance(
    type: TwinType.values.firstWhere((t) => t.name == j['type'], orElse: () => TwinType.bear),
    look: TwinLook.values.firstWhere((l) => l.slug == j['look'], orElse: () => TwinLook.calHat),
    name: j['name'] as String?,
    room: TwinRoom.values.firstWhere((r) => r.name == j['room'], orElse: () => TwinRoom.original),
  );

  /// Keeps the finished conversation on the phone: memory consent, habit notes (only
  /// with consent) and the confirmed answers, each Apple Health value labelled as such.
  Future<TwinRepository?> _keepConversation() async {
    final state = _controller.state;
    if (state == null) return null;
    final confirmed = (state['confirmed_profile'] as Map?) ?? const {};
    final sources = {
      for (final e in _healthValues.entries)
        if (confirmed[e.key] == e.value) e.key: HistorySource.appleHealth,
      for (final e in _documentValues.entries)
        if (confirmed[e.key] == e.value) e.key: HistorySource.document,
    };
    try {
      final repo = await _twin;
      await repo.saveOnboarding(
        state,
        modelInputs: _controller.modelInputs,
        sources: sources,
        estimatedFields: {
          for (final key in _healthEstimatedKeys)
            if (sources[key] == HistorySource.appleHealth) key,
        },
      );
      _saved = true;
      _syncOutlook();
      return repo;
    } catch (e) {
      debugPrint('Could not keep the conversation: $e');
      return null;
    }
  }

  Future<void> _offerReminders(BuildContext context, TwinRepository repo) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => Dialog(
      backgroundColor: Colors.transparent,
      child: ReminderOfferCard(
        onNotNow: () async {
          await repo.declineReminders();
          if (dialog.mounted) Navigator.of(dialog).pop();
        },
        onYes: () async {
          await repo.acceptReminders();
          if (dialog.mounted) Navigator.of(dialog).pop();
        },
      ),
    ),
  );

  @override
  void dispose() {
    _look.removeListener(_saveLook);
    _wellness?.repository.removeListener(_syncOutlook);
    _controller.removeListener(_intakeChanged);
    _wellness?.dispose();
    BandFileSession.disposeIfCreated();
    _controller.dispose();
    if (widget.appearance == null) _look.dispose();
    _outlook.dispose();
    _quiz?.dispose();
    super.dispose();
  }

  /// Bumped by "Delete my data": re-arms the one automatic start of the conversation.
  int _autoStartSession = 0;

  /// Set once onboarding is saved and the reminder offer is still due; shown on the first return to the Room.
  (BuildContext, TwinRepository)? _reminderOffer;

  void _toRoom(BuildContext context) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    _syncOutlook();
    final offer = _reminderOffer;
    if (offer == null) return;
    _reminderOffer = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && offer.$1.mounted && offer.$2.shouldOfferReminders) _offerReminders(offer.$1, offer.$2);
    });
  }

  /// The conversation, swooshing up from the Room.
  void _talk(BuildContext context, {bool quick = false}) => (quick ? OnboardingAutoStart.fadeIn<void> : SwooshRoute.push<void>)(
    context,
    (talkContext) => VoiceOnboardingScreen(
      controller: _controller,
      appearance: _look.value,
      aiProvider: _aiProvider,
      onUseHealth: () => _health(talkContext),
      onUploadDocument: () => _documents(talkContext),
      onDone: (profile) {
        // The reveal waits for the save, so it sees the new answers.
        final saved = _keepConversation();
        _ceremony(talkContext, fromTalk: true, saved: saved);
        // Then the one-time reminder offer: after the reveal, when the person is back on the Room.
        // Not offered again after the first check-in once it has been answered.
        saved.then((repo) {
          if (repo != null && repo.shouldOfferReminders) _reminderOffer = (context, repo);
        }).ignore();
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
          if (await _controller.importHealth(values)) {
            final estimates = {
              for (final c in result.confirmed)
                if (c.isEstimate) c.field.profileKey,
            };
            _twin.then((repo) => repo.recordHealthImport(values, estimatedFields: estimates)).ignore();
            _healthValues.addAll(values);
            _healthEstimatedKeys.removeAll(values.keys);
            _healthEstimatedKeys.addAll(estimates);
            if (mounted) setState(() => _healthKeys.addAll(values.keys));
          }
        },
      ),
    ),
  );

  /// Health-document upload, separate from Apple Health. Only values the person confirmed
  /// one by one reach the conversation; it then asks only for what is still missing.
  void _documents(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DocumentUploadScreen(
        confirmedValues: _profile ?? _controller.confirmedProfile,
        provider: _aiProvider,
        service: widget.documentService ?? liveDocumentService(extractor: HttpDocumentExtractor(base: _api)),
        onDone: (result) async {
          Navigator.of(context).pop();
          final values = result.profileValues;
          if (values.isNotEmpty && await _controller.importDocument(values)) {
            _twin.then((repo) => repo.recordImport(values, source: HistorySource.document)).ignore();
            _documentValues.addAll(values);
          }
          // Information notes (blood pressure, A1c, LDL) go to History only, never the forecast.
          if (result.notes.isNotEmpty) _twin.then((repo) => repo.recordDocumentReadings(result.notes)).ignore();
          if (mounted && context.mounted) _talk(context);
        },
      ),
    ),
  );

  /// The ceremony, then the fortune. From the intake's Continue ([fromTalk]) the
  /// conversation is dropped, so Back lands on the Room; from the Room it is pushed.
  /// Completes when the person is back on the Room.
  Future<void> _ceremony(BuildContext context, {bool fromTalk = false, Future<void>? saved}) {
    final nav = Navigator.of(context);
    // The one-time lifespan reveal, decided once (after the save) and then marked seen.
    var decided = false, reveal = false;
    bool revealNow() {
      if (!decided) {
        decided = true;
        final snap = _wellness?.snapshot;
        reveal = fromTalk && snap?.lifespan != null && !(snap?.lifespanRevealSeen ?? true);
        if (reveal) WidgetsBinding.instance.addPostFrameCallback((_) => _wellness?.markLifespanRevealSeen());
      }
      return reveal;
    }

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
              documentKeys: {..._documentValues.keys},
              onDrivers: () => _agentic.drivers(forecastContext),
              onPlayQuiz: () => _playQuiz(forecastContext),
              onResult: (f) {
                if (f.supported) _outlook.value = f;
              },
              scoreCard: switch (_wellness?.snapshot) {
                final score? when !score.underAge => WellnessCard(
                  child: FutureBuilder<void>(
                    future: saved ?? Future<void>.value(),
                    builder: (_, done) {
                      final show = done.connectionState == ConnectionState.done && revealNow();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          HealthScoreSummary(snapshot: _wellness?.snapshot ?? score, emphasis: show),
                          // The estimate: once, after onboarding; later only on "See your estimate".
                          if (show || !fromTalk) LifespanBlock(lifespan: (_wellness?.snapshot ?? score).lifespan),
                        ],
                      );
                    },
                  ),
                ),
                _ => null,
              },
              // The mascot speaks only if the person chose voice and it still works.
              speech: _controller.voiceUsable && !_controller.typing ? _controller.output : null,
              onBack: () => _toRoom(forecastContext),
              // "Go back to my answers": the conversation, where an answer can be changed.
              onAnswers: () {
                _toRoom(forecastContext);
                _talk(forecastContext);
              },
              // Answers missing: only those, then back on the Room with the score (never the
              // whole intake again, never a loop).
              onAnswerMissing: () {
                _toRoom(forecastContext);
                _agentic.answerMissing(context);
              },
            ),
            transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
          ),
        ),
      ),
    );
    return fromTalk ? nav.pushAndRemoveUntil(route, (r) => r.isFirst) : nav.push(route);
  }

  /// The Settings hub: choices, My data, reminders, AI and memory privacy, changing an answer, and the
  /// places that left Home (Apple Health, Health documents, What I see, Still learning, the wristband).
  void _settings(BuildContext context) {
    final adapter = _wellness;
    if (adapter == null) return;
    String? providerId;
    var closed = false;
    final value = ValueNotifier(adapter.settingsFor());
    void refresh() {
      if (!closed) value.value = adapter.settingsFor(providerId: providerId);
    }

    adapter.addListener(refresh);
    _agentic.provider().then((p) {
      providerId = p?.id;
      refresh();
    }, onError: (Object _) {}).ignore();
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute(
            builder: (c) => WellnessSettingsScreen(
              settings: value,
              onMemory: () => _agentic.notebook(c),
              onSuggestions: () => _agentic.aiPrivacy(c),
              onReminders: () => _agentic.reminders(c),
              onMyData: () => _agentic.myData(c),
              onBack: () => Navigator.of(c).pop(),
              entries: [
                SettingsEntry(label: 'Change an answer', description: 'Tell Mochi what changed', open: () => _agentic.changeAnswer(c)),
                SettingsEntry(
                  label: 'Weekly check-in',
                  description: _wellness?.repository.weeklyGateLine ?? 'A few questions about your week',
                  enabled: _wellness?.repository.weeklyAvailable ?? true,
                  open: () => _agentic.weeklyCheckIn(c),
                ),
                SettingsEntry(label: 'Apple Health', description: 'Bring in values you check', open: () => _health(c)),
                SettingsEntry(label: 'Health documents', description: 'Upload a visit summary or lab report', open: () => _agentic.healthDocuments(c)),
                SettingsEntry(label: 'Try a change', description: 'Explore what could move your outlook', open: () => _agentic.experiment(c)),
                SettingsEntry(label: 'What I see', description: 'Your wellness cards, with sources', open: () => _agentic.wellness(c)),
                SettingsEntry(label: 'Still learning', description: 'Answers Mochi still needs', open: () => _agentic.stillLearning(c)),
                SettingsEntry(label: 'Activity band', description: 'Pair or try the recorded demo', open: () => _agentic.bandFlow(c)),
              ],
            ),
          ),
        )
        .whenComplete(() {
          closed = true;
          adapter.removeListener(refresh);
          value.dispose();
        });
  }

  String? _stillLearning() {
    final n = _wellness?.repository.current?.missingInputs.length ?? 0;
    return n == 0 ? null : 'Still learning $n';
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
      navigatorObservers: [HomeDepth.instance],
      builder: _agentic.wrap,
      home: ListenableBuilder(
        listenable: Listenable.merge([_controller, _wellness]),
        builder: (context, _) => OnboardingAutoStart(
          enabled: widget.autoStartOnboarding && _wellness != null && _profile == null,
          session: _autoStartSession,
          appearance: _look,
          onStart: (c, {required quick}) => _talk(c, quick: quick),
          child: RoomScreen(
          appearance: _look,
          hasProfile: _profile != null,
          onTalk: () => _talk(context),
          onCustomize: () => _customize(context),
          onFortune: () => _ceremony(context),
          outlook: _outlook,
          // The seven days come from the phone repository.
          wellness: _wellness?.snapshot ?? const WellnessSnapshot(),
          onHistory: _wellness == null ? null : () => _history(context),
          onQuiz: () => _playQuiz(context),
          onExperiment: _wellness == null ? null : () => _agentic.experiment(context),
          onDrivers: () => _agentic.drivers(context),
          onBand: _wellness == null ? null : () => _agentic.bandFlow(context),
          onSettings: _wellness == null ? null : () => _settings(context),
          stateLine: _stillLearning(),
          ideas: _agentic.ideasAccess,
          onAnswerMissing: _wellness == null ? null : () => _agentic.answerMissing(context),
          // The whole card opens the plan; its own buttons (Why?, thumbs) win the tap.
          today: _wellness == null || (_profile?['age'] as num? ?? 0) < 18
              ? null
              : GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => _agentic.todayPlan(context, onTalk: () => _talk(context)),
                  child: _agentic.todayCard(context, onTalk: () => _talk(context), condensed: true, trailing: const CheckInEntry(compact: true)),
                ),
        ),
        ),
      ),
    );
  }
}
