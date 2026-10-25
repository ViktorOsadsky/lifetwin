/// The check-in seam: one entry point for the Home button and anything else that starts a check-in.
///
/// ```dart
/// // Home's primary check-in button:
/// onPressed: () => openCheckIn(context, kind: CheckInKind.quick),
/// ```
///
/// [openCheckIn] reads everything it needs from a [CheckInScope] above it in the tree (`AgenticRoutes.wrap`
/// puts one above the `MaterialApp`'s navigator), so callers pass only the kind. It creates and owns the
/// engine's `CheckinController` (server guide, speech, `TwinCheckinStore`), pushes the chat
/// (`CheckInScreen`) and completes when the person leaves it. With no saved profile nothing opens: the
/// intake comes first.
///
/// The quick check-in is the core loop: one to three questions chosen from what the stored days are
/// missing, about a minute. The weekly one asks the model's own inputs and, when it finishes, shows how
/// the outlook moved. The store records a finished check-in exactly once (`TwinCheckinStore` ->
/// `TwinRepository.applyCheckin`): nothing here calls `applyCheckin` again.
///
/// Check-ins send answers to LifeTwin's server to be understood (`/api/checkin/*`); the server keeps
/// nothing. They never send anything to an outside AI provider.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../health/health_sample.dart';
import '../twin/twin_checkin_store.dart';
import '../twin/twin_repository.dart';
import '../ui/twin_appearance.dart';
import '../voice/speech.dart';
import 'checkin_client.dart';
import 'checkin_controller.dart';
import 'checkin_screen.dart';
import '../experiment/widgets/source_link.dart';

/// `quick` is the 1-minute daily chat; `weekly` is the longer one.
enum CheckInKind { quick, weekly }

/// What the coach says after a check-in: its `encourage` line (null: use the built-in one) and, when it
/// had a plan to compare with, the changes it made, one reason per line (empty: the plan stays the same;
/// null: nothing to say about the plan).
class TodayUpdate {
  const TodayUpdate({this.encouragement, this.changes});
  final String? encouragement;
  final List<String>? changes;
}

/// After a check-in finishes: the coach revises today's plan with the check-in results ([update]) and
/// "Here's today's plan" opens it ([open]).
class TodayPlanHook {
  const TodayPlanHook({required this.update, required this.open});
  final Future<TodayUpdate> Function() update;
  final void Function(BuildContext context) open;
}

/// What a check-in needs, provided once near the top of the app.
class CheckInScope extends InheritedWidget {
  const CheckInScope({
    super.key,
    required this.repository,
    required this.guide,
    required this.speechInput,
    required this.speechOutput,
    required this.appearance,
    this.voiceUsable,
    this.healthSamples,
    this.openUrl = defaultOpenUrl,
    this.now,
    this.todayPlan,
    required super.child,
  });

  final TwinRepository repository;

  /// `HttpCheckinClient()`; tests pass a scripted guide.
  final CheckinGuide guide;
  final SpeechInput speechInput;
  final SpeechOutput speechOutput;
  final ValueListenable<TwinAppearance> appearance;

  /// Whether the person agreed to voice (asked at onboarding). Null: voice is not used, so typing.
  final bool Function()? voiceUsable;

  /// Apple Health samples already allowed by the person, for one-tap read-backs. Null: not connected.
  final Future<List<HealthSample>> Function()? healthSamples;
  final OpenUrl openUrl;

  /// The clock for "due" (tests set it); the phone's clock by default.
  final DateTime Function()? now;

  /// Encouragement and "Here's today's plan" on the finished check-in. Null: neither is shown.
  final TodayPlanHook? todayPlan;

  static CheckInScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CheckInScope>();
    assert(scope != null, 'openCheckIn needs a CheckInScope above it');
    return scope!;
  }

  static CheckInScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CheckInScope>();

  @override
  bool updateShouldNotify(CheckInScope old) =>
      repository != old.repository || guide != old.guide || appearance != old.appearance;
}

/// Starts a [kind] check-in and completes when the person is back out of it. Does nothing without a
/// saved profile. If nothing is due (a quick check-in already done today) the screen says so.
Future<void> openCheckIn(BuildContext context, {required CheckInKind kind}) {
  final scope = CheckInScope.of(context);
  if (!scope.repository.store.hasProfile) return Future.value();
  final controller = CheckinController(
    guide: scope.guide,
    input: scope.speechInput,
    output: scope.speechOutput,
    ownsSpeech: false,
    store: TwinCheckinStore(scope.repository),
    reminders: scope.repository.reminders,
    healthSamples: scope.healthSamples,
    clock: scope.now,
    voiceUsable: scope.voiceUsable?.call() ?? false,
  );
  return Navigator.of(context)
      .push<void>(
        MaterialPageRoute<void>(
          builder: (route) => ValueListenableBuilder<TwinAppearance>(
            valueListenable: scope.appearance,
            builder: (_, look, _) => CheckInScreen(
              controller: controller,
              kind: kind,
              repository: scope.repository,
              appearance: look,
              open: scope.openUrl,
              todayPlan: scope.todayPlan,
              onDone: () => Navigator.of(route).pop(),
            ),
          ),
        ),
      )
      .whenComplete(controller.dispose);
}
