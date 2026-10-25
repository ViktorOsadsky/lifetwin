import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'band/band_file_intake.dart';
import 'band/band_file_session.dart';
import 'band/band_screens.dart';
import 'band/band_service.dart';
import 'band/band_store.dart';
import 'checkin/change_chat.dart';
import 'documents/document_extract.dart';
import 'documents/document_screen.dart';
import 'documents/document_upload.dart';
import 'documents/health_documents_screen.dart';
import 'wellness/coach_client.dart';
import 'wellness/coach_context.dart';
import 'wellness/daily_plan_screen.dart';
import 'wellness/today_card.dart';
import 'checkin/check_in.dart';
import 'checkin/checkin_client.dart';
import 'checkin/consent_screens.dart';
import 'checkin/consents.dart';
import 'checkin/my_data_screen.dart';
import 'checkin/notebook_screen.dart';
import 'experiment/answers.dart';
import 'health/health_reader.dart';
import 'health/health_sample.dart';
import 'onboarding/voice_onboarding_controller.dart';
import 'experiment/experiment_screen.dart';
import 'experiment/room_pills.dart';
import 'experiment/still_learning_screen.dart';
import 'experiment/weight_screen.dart';
import 'experiment/wellness_screen.dart';
import 'twin/twin_repository.dart';
import 'ui/twin_appearance.dart';
import 'voice/api_base.dart';
import 'wellness/outlook_drivers_screen.dart';

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
    this.documentService,
    CoachClient? coach,
    CapabilitiesClient? capabilities,
    BandClient? bandClient,
    BandFilePicker? bandFilePicker,
    this.onDeleted,
    // ignore: prefer_initializing_formals
  }) : _guide = guide,
       _api = api,
       // ignore: prefer_initializing_formals
       _coach = coach,
       changeClient = changeClient ?? HttpChangeClient(base: api),
       capabilities = capabilities ?? HttpCapabilitiesClient(base: api),
       _bandClientParam = bandClient,
       // ignore: prefer_initializing_formals
       _bandFilePicker = bandFilePicker,
       _bandClient = bandClient ?? StubBandClient();

  final ValueListenable<TwinAppearance> look;

  /// The onboarding conversation, for its speech input and output and the person's choice of voice.
  final VoiceOnboardingController Function() voice;
  final CheckinGuide? _guide;
  final ApiBase _api;

  /// Reads a document for the Health documents page; the live OCR and server when null.
  final DocumentUploadService Function()? documentService;

  /// Today's plan (`POST /api/coach/plan`); tests pass a fake.
  late final CoachClient coach = _coach ?? HttpCoachClient(base: _api);
  final CoachClient? _coach;

  /// The check-in server; it is told the profile's age so Mochi's examples fit.
  late final CheckinGuide guide = _guide ?? HttpCheckinClient(base: _api, age: () => repo?.profile['age']);
  final ChangeClient changeClient;

  /// Apple Health samples already allowed by the person; null when Health is not connected.
  final Future<List<HealthSample>> Function()? healthSamples;
  final CapabilitiesClient capabilities;
  final BandClient _bandClient;
  final BandClient? _bandClientParam;
  final BandFilePicker? _bandFilePicker;

  /// Called after "Delete my data" has wiped the phone, so the app shell forgets what it held in memory.
  final VoidCallback? onDeleted;
  TwinRepository? repo;

  /// The AI consents; created once the repository has loaded.
  ConsentStore? consents;

  /// The wristband (recorded demo only until a Bluetooth plugin exists) and what it suggests.
  late final BandStore band = _bandClientGiven ? BandStore(_bandClient) : BandFileSession.instance.store;

  /// Band files (`lifetwin.band_day.v0`): the shared phone-only import session unless a test gave a client.
  late final BandFileIntake intake = _bandClientGiven ? BandFileIntake(store: band, picker: _bandFilePicker) : BandFileSession.instance.intake;
  late final bool _bandClientGiven = _bandClientParam != null;
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
        todayPlan: TodayPlanHook(update: _planUpdate, open: (c) => todayPlan(c)),
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
    ),
    if (repo != null) BandPill(store: band, onTap: () => bandFlow(context)),
  ];

  /// Picks a `lifetwin.band_day.v0` file and feeds the band days. Says what happened; true when days came in.
  Future<bool> importBandFile(BuildContext context) async {
    await intake.importFromFiles();
    final o = intake.outcome;
    final ok = o != null && o.error == null && !o.cancelled && o.reportCount > 0;
    if (context.mounted && o != null && !o.cancelled) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            o.error ??
                (o.changed
                    ? 'Added ${o.reportCount} ${o.reportCount == 1 ? 'day' : 'days'} from the file.'
                    : 'Already imported.'),
          ),
        ),
      );
    }
    return ok;
  }

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
              builder: (s) => BandSettingsScreen(
                store: band,
                onBack: () => Navigator.of(s).pop(),
                onImportFile: () => importBandFile(s),
                onForget: intake.forgetImports,
              ),
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

    if (band.paired || band.demo || band.hasImportedFile) return panel(nav);
    nav.push(
      MaterialPageRoute<void>(
        builder: (page) => BandPairScreen(
          store: band,
          appearance: look.value,
          onClose: () => Navigator.of(page).pop(),
          onSeeToday: () => panel(Navigator.of(page), replace: true),
          onImportFile: () async {
            // A file instead of Bluetooth: once days are in, the panel (and the weekly suggestion) follow.
            if (await importBandFile(page) && page.mounted) panel(Navigator.of(page), replace: true);
          },
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
          onNotebook: () => notebook(page),
          onDeleted: () {
            intake.forgetImports().ignore();
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

  /// The latest plan the coach gave, so a later revision can say what changed.
  DailyPlan? _lastPlan;

  /// After a check-in: asks the coach to revise today's plan with the check-in results (the same
  /// `previous_plan` path the plan screen uses) and returns its encouragement and, one line each, its own
  /// reasons for what changed. Without an earlier plan to compare with there is nothing to say about changes.
  Future<TodayUpdate> _planUpdate() async {
    final r = repo;
    if (r == null) return const TodayUpdate();
    final context = coachContext(r);
    final previous = _lastPlan;
    if (previous != null && previous.revision != null && !previous.emergency) {
      context['previous_plan'] = previous.previousPlan();
      context['latest_revision_id'] = previous.revision;
    }
    final plan = await coach.plan(context);
    _lastPlan = plan;
    String? line;
    for (final i in plan.items) {
      if (i['kind'] == 'encourage') line = i['message'] as String;
    }
    return TodayUpdate(
      encouragement: line,
      changes: previous == null ? null : (plan.reusedPrevious ? const [] : plan.changedLines),
    );
  }

  /// "Today with Mochi" for Home: mount it where the Today card goes. It asks the outside-AI consent once
  /// before the first plan (the coach may use the same provider), and opens the full plan on a tap.
  Widget todayCard(BuildContext context, {VoidCallback? onTalk, bool condensed = false, Widget? trailing}) => TodayWithMochiCard(
    condensed: condensed,
    trailing: trailing,
    client: coach,
    onPlan: (p) => _lastPlan = p,
    confirmedContext: () => coachContext(repo!),
    beforeFirstPlan: () => ensureOutsideAiConsent(context),
    onOpen: () => todayPlan(context, onTalk: onTalk),
  );

  /// The full daily plan (`DailyPlanScreen`).
  void todayPlan(BuildContext context, {VoidCallback? onTalk}) {
    final r = repo;
    if (r == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (page) => DailyPlanScreen(
          client: coach,
          onPlan: (p) async => _lastPlan = p,
          confirmedContext: () => coachContext(r),
          onBack: () => Navigator.of(page).pop(),
          onTalk: () {
            Navigator.of(page).pop();
            onTalk?.call();
          },
        ),
      ),
    );
  }

  /// "Health documents": past uploads, readings, and the upload flow. Opened from Settings.
  void healthDocuments(BuildContext context) {
    final r = repo;
    if (r == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (c) => _HealthDocumentsHost(routes: this, repository: r, parent: context),
      ),
    );
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
        ),
      ),
    );
  }

  /// "What moves it": the engine's guidance cards as directions only (strengths link with a higher
  /// outlook, opportunities with a lower one). "Explore an experiment" opens [experiment].
  void drivers(BuildContext context) {
    final r = repo;
    if (r == null) return;
    final drivers = [
      for (final c in r.wellnessCards)
        if (c.level == 'strength' || c.level == 'opportunity')
          OutlookDriver(
            label: c.title,
            direction: c.level == 'strength' ? DriverDirection.higher : DriverDirection.lower,
            reason: c.message,
          ),
    ];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (c) => OutlookDriversScreen(
          drivers: drivers,
          onBack: () => Navigator.of(c).pop(),
          onExperiment: () => experiment(c),
        ),
      ),
    );
  }

  /// Mochi's notebook: the saved habit notes and the Memory switch.
  void notebook(BuildContext context) {
    final r = repo;
    if (r == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (c) => NotebookScreen(repository: r, onBack: () => Navigator.of(c).pop())),
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

class _HealthDocumentsHost extends StatefulWidget {
  const _HealthDocumentsHost({required this.routes, required this.repository, required this.parent});
  final AgenticRoutes routes;
  final TwinRepository repository;
  final BuildContext parent;

  @override
  State<_HealthDocumentsHost> createState() => _HealthDocumentsHostState();
}

class _HealthDocumentsHostState extends State<_HealthDocumentsHost> {
  List<String> _notices = const [];

  void _upload() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (c) => DocumentUploadScreen(
        service:
            widget.routes.documentService?.call() ??
            liveDocumentService(extractor: HttpDocumentExtractor(base: widget.routes._api)),
        onDone: (result) async {
          Navigator.of(c).pop();
          final r = widget.repository;
          final values = result.profileValues;
          if (values.isNotEmpty) await r.recordImport(values, source: HistorySource.document);
          if (result.notes.isNotEmpty) await r.recordDocumentReadings(result.notes);
          if (mounted) setState(() => _notices = result.notices);
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => HealthDocumentsScreen(
    repository: widget.repository,
    onBack: () => Navigator.of(context).pop(),
    onUpload: _upload,
    notices: _notices,
    onTellMochiWeight: () => widget.routes.changeWithMochi(context, 'weight_kg'),
  );
}
