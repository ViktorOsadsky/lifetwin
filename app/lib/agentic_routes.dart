import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'checkin/change_chat.dart';
import 'documents/document_extract.dart';
import 'documents/document_screen.dart';
import 'documents/document_upload.dart';
import 'documents/health_documents_screen.dart';
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
import 'wellness/outlook_drivers_screen.dart';

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
  }) : _api = api,
       guide = guide ?? HttpCheckinClient(base: api),
       changeClient = changeClient ?? HttpChangeClient(base: api);

  final ApiBase _api;

  /// Reads a document for the Health documents page; the live OCR and server when null.
  final DocumentUploadService Function()? documentService;
  final ValueListenable<TwinAppearance> look;

  /// The onboarding conversation, for its speech input and output and the person's choice of voice.
  final VoiceOnboardingController Function() voice;
  final CheckinGuide guide;
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
    return CheckInScope(
      repository: r,
      guide: guide,
      speechInput: v.input,
      speechOutput: v.output,
      voiceUsable: () => v.voiceUsable,
      healthSamples: healthSamples,
      appearance: look,
      child: child!,
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
