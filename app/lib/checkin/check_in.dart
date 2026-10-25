/// The check-in seam: one entry point for the Home button and anything else that starts a check-in.
///
/// ```dart
/// // Home's primary "Daily check-in" button:
/// onPressed: () => openCheckIn(context, kind: CheckInKind.daily),
/// ```
///
/// [openCheckIn] reads everything it needs from a [CheckInScope] above it in the tree
/// (`main.dart` puts one above the `MaterialApp`'s home), so callers pass only the kind. It pushes
/// the chat (`CheckInScreen`) and completes when the person leaves it. The daily check-in is the
/// light 1-minute chat (about 3 questions: feeling, sleep, moving today; quick replies, voice or
/// keyboard). The weekly check-in is the longer read-back of the week; when it finishes, it shows
/// how the outlook moved. Both go through `TwinRepository.applyCheckin`.
///
/// Check-ins send answers to LifeTwin's server to be understood (`/api/checkin/*`); the server
/// keeps nothing. They never send anything to an outside AI provider.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../experiment/widgets/source_link.dart';
import '../twin/twin_repository.dart';
import '../ui/twin_appearance.dart';
import 'checkin_client.dart';
import 'checkin_controller.dart';
import 'checkin_screen.dart';

export 'checkin_client.dart' show CheckInKind;

/// What a check-in needs, provided once near the top of the app.
class CheckInScope extends InheritedWidget {
  const CheckInScope({
    super.key,
    required this.repository,
    required this.client,
    required this.appearance,
    this.openUrl = defaultOpenUrl,
    this.onTalk,
    required super.child,
  });

  final TwinRepository repository;
  final CheckInClient client;
  final ValueListenable<TwinAppearance> appearance;
  final OpenUrl openUrl;

  /// "Tap to talk" inside a check-in. Null until voice is wired to check-ins (the keyboard shows).
  final VoidCallback? onTalk;

  static CheckInScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CheckInScope>();
    assert(scope != null, 'openCheckIn needs a CheckInScope above it');
    return scope!;
  }

  static CheckInScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<CheckInScope>();

  @override
  bool updateShouldNotify(CheckInScope old) =>
      repository != old.repository || client != old.client || appearance != old.appearance;
}

/// Starts a [kind] check-in and completes when the person is back out of it.
Future<void> openCheckIn(BuildContext context, {required CheckInKind kind}) {
  final scope = CheckInScope.of(context);
  final controller = CheckinController(client: scope.client, repository: scope.repository, kind: kind);
  return Navigator.of(context)
      .push<void>(
        MaterialPageRoute<void>(
          builder: (route) => ValueListenableBuilder<TwinAppearance>(
            valueListenable: scope.appearance,
            builder: (_, look, _) => CheckInScreen(
              controller: controller,
              appearance: look,
              open: scope.openUrl,
              onTalk: scope.onTalk,
              onDone: () => Navigator.of(route).pop(),
            ),
          ),
        ),
      )
      .whenComplete(controller.dispose);
}
