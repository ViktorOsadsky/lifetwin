import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'band/band_screens.dart';
import 'band/band_service.dart';
import 'band/band_store.dart';
import 'checkin/change_chat.dart';
import 'checkin/check_in.dart';
import 'checkin/checkin_client.dart';
import 'checkin/consent_screens.dart';
import 'checkin/consents.dart';
import 'checkin/my_data_screen.dart';
import 'experiment/answers.dart';
import 'health/health_reader.dart';
import 'health/health_sample.dart';
import 'onboarding/voice_onboarding_controller.dart';
import 'experiment/experiment_screen.dart';
import 'experiment/ideas_screen.dart';
import 'experiment/recommendations.dart';
import 'experiment/room_pills.dart';
import 'experiment/still_learning_screen.dart';
import 'experiment/weight_screen.dart';
import 'experiment/wellness_screen.dart';
import 'twin/twin_repository.dart';
import 'ui/twin_appearance.dart';
import 'voice/api_base.dart';

/// The check-in's Apple Health read: the last 3 days, only once Apple Health is connected (the person has
/// imported from it); otherwise nothing is read and Mochi asks.
Future<List<HealthSample>> Function() connectedHealthSamples(
  HealthReader reader,
  bool Function() connected, {
  DateTime Function()? now,
}) =>
    () async => connected() ? reader.read(now: (now ?? DateTime.now)(), days: 3) : const <HealthSample>[];

/// Everything the agentic screens need from the app shell, in one place so `main.dart` stays small:
/// the scope that lets any screen call `openCheckIn`, the Room's pills, and the routes behind them
/// (Experiment, Still learning, What I see, About weight, the change conversation).
///
/// `main.dart` creates one, calls [attach] when the repository has loaded, wraps the app with [wrap]
/// and gives the Room `extraPills: agentic.pills(context)`. Tests pass fake clients.
class AgenticRoutes {
  AgenticRoutes({
    required this.look,
    required ApiBase api,
    required this.voice,
    CheckinGuide? guide,
    ChangeClient? changeClient,
    this.healthSamples,
    CapabilitiesClient? capabilities,
    BandClient? bandClient,
    this.recommendations,
    this.onDeleted,
    // ignore: prefer_initializing_formals
  }) : _guide = guide,
       _api = api,
       changeClient = changeClient ?? HttpChangeClient(base: api),
       capabilities = capabilities ?? HttpCapabilitiesClient(base: api),
       _bandClient = bandClient ?? StubBandClient();

  final ValueListenable<TwinAppearance> look;

  /// The onboarding conversation, for its speech input and output and the person's choice of voice.
  final VoiceOnboardingController Function() voice;
  final CheckinGuide? _guide;
  final ApiBase _api;

  /// The check-in server; it is told the profile's age so Mochi's examples fit.
  late final CheckinGuide guide = _guide ?? HttpCheckinClient(base: _api, age: () => repo?.profile['age']);
  final ChangeClient changeClient;

  /// Apple Health samples already allowed by the person; null when Health is not connected.
  final Future<List<HealthSample>> Function()? healthSamples;
  final CapabilitiesClient capabilities;
  final BandClient _bandClient;

  /// Tests pass a fake source (given the provider id when Personal suggestions are on).
  final RecommendationsSource Function(String? provider)? recommendations;

  /// Called after "Delete my data" has wiped the phone, so the app shell forgets what it held in memory.
  final VoidCallback? onDeleted;
  TwinRepository? repo;

  /// The AI consents; created once the repository has loaded.
  ConsentStore? consents;

  /// The wristband (recorded demo only until a Bluetooth plugin exists) and what it suggests.
  late final BandStore band = BandStore(_bandClient);
  BandService? bandService;
  Future<AiProvider?>? _provider;

  /// The outside AI provider from `/api/capabilities` (asked once; null when none is set up).
  Future<AiProvider?> provider() => _provider ??= capabilities.personalize();

  /// The repository has loaded.
  void attach(TwinRepository r) {
    repo = r;
    consents ??= ConsentStore(r);
    bandService ??= BandService(repository: r);
    // The forecast follows what the check-ins and the stored days say.
    r.refresh();
  }

  /// Puts the check-in scope above the navigator, so every route can call `openCheckIn`.
  Widget wrap(BuildContext context, Widget? child) {
    final r = repo;
    if (r == null) return child!;
    final v = voice();
    return ResumeRefresh(
      repository: r,
      child: CheckInScope(
        repository: r,
        guide: guide,
        speechInput: v.input,
        speechOutput: v.output,
        voiceUsable: () => v.voiceUsable,
        healthSamples: healthSamples,
        appearance: look,
        child: child!,
      ),
    );
  }

  /// The Room's pills ("Still learning N", "What I see", "Try a change").
  List<Widget> pills(BuildContext context) => [
    ...roomPills(
      repository: repo,
      onExperiment: () => experiment(context),
      onStillLearning: () => stillLearning(context),
      onWellness: () => wellness(context),
      onMyData: () => myData(context),
    ),
    if (repo != null) BandPill(store: band, onTap: () => bandFlow(context)),
  ];

  /// Wristband: pair (or try the recorded demo) -> panel -> weekly suggestion -> read-back, and settings.
  void bandFlow(BuildContext context) {
    final r = repo, svc = bandService;
    if (r == null || svc == null) return;
    final nav = Navigator.of(context);
    void panel(NavigatorState n, {bool replace = false}) {
      final route = MaterialPageRoute<void>(
        builder: (page) => BandPanelScreen(
          store: band,
          service: svc,
          onBack: () => Navigator.of(page).pop(),
          onSettings: () => Navigator.of(page).push(
            MaterialPageRoute<void>(
              builder: (s) => BandSettingsScreen(store: band, onBack: () => Navigator.of(s).pop()),
            ),
          ),
          onUseSuggestion: (suggestion) => Navigator.of(page).push(
            MaterialPageRoute<void>(
              builder: (s) => BandSuggestScreen(
                service: svc,
                store: band,
                suggestion: suggestion,
                appearance: look.value,
                onBack: () => Navigator.of(s).pop(),
                onUse: () => Navigator.of(s).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (b) => BandReadbackScreen(
                      service: svc,
                      suggestion: suggestion,
                      appearance: look.value,
                      onClose: () => Navigator.of(b).pop(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      replace ? n.pushReplacement(route) : n.push(route);
    }

    if (band.paired || band.demo) return panel(nav);
    nav.push(
      MaterialPageRoute<void>(
        builder: (page) => BandPairScreen(
          store: band,
          appearance: look.value,
          onClose: () => Navigator.of(page).pop(),
          onSeeToday: () => panel(Navigator.of(page), replace: true),
        ),
      ),
    );
  }

  /// "Tell Mochi" and "Change": a short talk with Mochi about one saved answer (`/api/change/start` with
  /// `field`) or "What would you like to update?" (no field). Saves only after "Yes, save".
  void changeWithMochi(BuildContext context, String? field) {
    final r = repo;
    if (r == null) return;
    final controller = ChangeChatController(client: changeClient, repository: r, field: field);
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (c) =>
                ChangeChatScreen(controller: controller, appearance: look.value, onClose: () => Navigator.of(c).pop()),
          ),
        )
        .whenComplete(controller.dispose);
  }

  /// "My data": what is saved on this phone, the memory switch, AI and privacy, and Delete my data.
  void myData(BuildContext context) {
    final r = repo, c = consents;
    if (r == null || c == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (page) => MyDataScreen(
          repository: r,
          consents: c,
          onBack: () => Navigator.of(page).pop(),
          onAiPrivacy: () => aiPrivacy(page),
          onWeeklyCheckIn: () => weeklyCheckIn(page),
          onReminders: () => reminders(page),
          onDeleted: () {
            band.unpair().ignore();
            onDeleted?.call();
            Navigator.of(page).popUntil((route) => route.isFirst);
          },
        ),
      ),
    );
  }

  /// "Check-in reminders": whether and when the phone nudges, and which days.
  void reminders(BuildContext context) {
    final r = repo;
    if (r == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (page) => ReminderSettingsScreen(repository: r, onBack: () => Navigator.of(page).pop()),
      ),
    );
  }

  /// "AI and privacy": the AI helper and Personal suggestions, each off until turned on.
  void aiPrivacy(BuildContext context) {
    final c = consents;
    if (c == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (page) => FutureBuilder<AiProvider?>(
          future: provider(),
          builder: (_, snap) => AiSettingsScreen(
            consents: c,
            provider: snap.data,
            onAskOutsideAi: () => ensureOutsideAiConsent(page),
            onBack: () => Navigator.of(page).pop(),
          ),
        ),
      ),
    );
  }

  /// Memory: "Should Mochi remember what you tell it?" Saves the choice and leaves.
  void memoryChoice(BuildContext context) {
    final r = repo;
    if (r == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (page) => MemoryConsentScreen(
          appearance: look.value,
          onBack: () => Navigator.of(page).pop(),
          onChoose: (on) async {
            await r.applyMemoryConsent(on);
            if (page.mounted) Navigator.of(page).pop();
          },
        ),
      ),
    );
  }

  /// "What would you like to update?": the change conversation with no field chosen.
  void changeAnswer(BuildContext context) => changeWithMochi(context, null);

  /// The weekly check-in, whether or not the schedule says one is due.
  Future<void> weeklyCheckIn(BuildContext context) => openCheckIn(context, kind: CheckInKind.weekly);

  /// Asks for the outside-AI consent when this provider has no answer yet (or a new provider has taken
  /// over), and completes with whether Personal suggestions may use it now. Call it before the first plan or
  /// ideas request: it is false, and nothing should be sent, when no provider is set up or the answer is no.
  Future<bool> ensureOutsideAiConsent(BuildContext context) async {
    final r = repo, c = consents;
    if (r == null || c == null) return false;
    final p = await provider();
    if (p == null || !p.configured) return false;
    if (!c.needsAnswer(p)) return c.mayShare(p);
    if (!context.mounted) return false;
    final answer = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (page) => OutsideAiConsentScreen(
          provider: p,
          reconsent: r.outsideAiProvider != null,
          appearance: look.value,
          onChoose: (yes) => Navigator.of(page).pop(yes),
        ),
      ),
    );
    if (answer == null) return false;
    await c.setOutsideAi(p.id, answer);
    return answer;
  }

  void experiment(BuildContext context) {
    final r = repo;
    if (r == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (c) => ExperimentScreen(
          repository: r,
          appearance: look.value,
          onBack: () => Navigator.of(c).pop(),
          onTellMochi: (field) {
            Navigator.of(c).pop();
            changeWithMochi(context, field);
          },
          onIdeas: () => ideas(c),
        ),
      ),
    );
  }

  /// "Ideas for you": asks the outside-AI consent first (once), then Mochi's suggestions.
  /// Without a yes they are worded by Mochi alone and nothing goes to an outside AI.
  Future<void> ideas(BuildContext context) async {
    final r = repo;
    if (r == null) return;
    final allowed = await ensureOutsideAiConsent(context);
    if (!context.mounted) return;
    final provider = allowed ? (await this.provider())?.id : null;
    if (!context.mounted) return;
    final source =
        recommendations?.call(provider) ?? HttpRecommendations(repository: r, base: _api, outsideAiProvider: provider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (page) => FutureBuilder<List<Recommendation>>(
          future: source.load(),
          builder: (_, snap) => !snap.hasData
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : ListenableBuilder(
                  listenable: r,
                  builder: (_, _) => IdeasScreen(
                    appearance: look.value,
                    ideas: snap.data!,
                    cards: r.wellnessCards,
                    memoryOn: r.store.memoryConsent,
                    onBack: () => Navigator.of(page).pop(),
                    onMemory: () => memoryChoice(page),
                    // The lever is one tap away in the Experiment.
                    onTry: (_) {
                      Navigator.of(page).pop();
                      experiment(context);
                    },
                  ),
                ),
        ),
      ),
    );
  }

  void stillLearning(BuildContext context) {
    final r = repo;
    if (r == null) return;
    final a = r.current ?? r.assess(const {});
    final known = [
      for (final e in a.profileUsed.entries)
        if (Answers.text(e.key, e.value) case final text?) (e.key, text),
      // Height and weight are one model input (BMI); never shown as a number.
      if (a.profileUsed['bmi'] != null) ('bmi', ''),
    ];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (c) => StillLearningScreen(
          appearance: look.value,
          assessment: a,
          known: known,
          onBack: () => Navigator.of(c).pop(),
          onTellMochi: (field) {
            Navigator.of(c).pop();
            changeWithMochi(context, field);
          },
        ),
      ),
    );
  }

  void wellness(BuildContext context) {
    final r = repo;
    if (r == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (c) => WellnessScreen(
          appearance: look.value,
          state: r.twinState(),
          cards: r.wellnessCards,
          onBack: () => Navigator.of(c).pop(),
          onWeight: () {
            final bmi = r.wellnessCards.where((w) => w.id == 'bmi').firstOrNull;
            if (bmi == null) return;
            Navigator.of(c).push(
              MaterialPageRoute<void>(
                builder: (w) => WeightInfoScreen(
                  appearance: look.value,
                  card: bmi,
                  onBack: () => Navigator.of(w).pop(),
                  onAskMochi: () {
                    Navigator.of(w).pop();
                    Navigator.of(c).pop();
                    changeWithMochi(context, 'weight_kg');
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Keeps the forecast, the due check-in and the planned reminders current: when the app comes back
/// to the foreground (the date may have moved on, so a daily window ends on a different day and today's
/// check-in is due again) it calls `repo.refresh()` and plans the reminders again.
class ResumeRefresh extends StatefulWidget {
  const ResumeRefresh({super.key, required this.repository, required this.child, this.now});
  final TwinRepository repository;
  final Widget child;

  /// The clock for reminders (tests set it).
  final DateTime Function()? now;

  @override
  State<ResumeRefresh> createState() => _ResumeRefreshState();
}

class _ResumeRefreshState extends State<ResumeRefresh> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final repo = widget.repository;
    repo.refresh();
    final reminders = repo.reminders;
    final settings = repo.checkinSettings;
    if (reminders != null && settings.remindersOn) {
      reminders.reschedule(settings, localNow: (widget.now ?? DateTime.now)(), history: repo.store.checkins).ignore();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
