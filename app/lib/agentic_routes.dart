import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'checkin/change_chat.dart';
import 'checkin/check_in.dart';
import 'checkin/checkin_client.dart';
import 'experiment/answers.dart';
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
    // ignore: prefer_initializing_formals
  }) : _guide = guide,
       _api = api,
       changeClient = changeClient ?? HttpChangeClient(base: api);

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
  TwinRepository? repo;

  /// The repository has loaded.
  void attach(TwinRepository r) {
    repo = r;
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
  List<Widget> pills(BuildContext context) => roomPills(
    repository: repo,
    onExperiment: () => experiment(context),
    onStillLearning: () => stillLearning(context),
    onWellness: () => wellness(context),
  );

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
