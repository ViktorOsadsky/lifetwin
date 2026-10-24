import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/activity/activity_screen.dart';
import '../features/activity/health_import_screen.dart';
import '../features/confirm/confirm_screen.dart';
import '../features/experiment/experiment_screen.dart';
import '../features/fortune/fortune_screen.dart';
import '../features/intake/intake_screen.dart';
import '../features/levers/levers_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/quiz_feedback/quiz_feedback_screen.dart';
import '../features/record_measurements/record_measurements_screen.dart';
import '../features/room/room_screen.dart';
import '../features/studio/studio_screen.dart';
import '../features/try_on/try_on_screen.dart';
import 'shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter buildRouter({String initialLocation = '/room'}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => LtShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/room', builder: (_, _) => const RoomScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/plan', builder: (_, _) => const PlanScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/activity',
                builder: (_, _) => const ActivityScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(path: '/intake', builder: (_, _) => const IntakeScreen()),
      GoRoute(path: '/confirm', builder: (_, _) => const ConfirmScreen()),
      GoRoute(path: '/fortune', builder: (_, _) => const FortuneScreen()),
      GoRoute(path: '/levers', builder: (_, _) => const LeversScreen()),
      GoRoute(path: '/try-on', builder: (_, _) => const TryOnScreen()),
      GoRoute(path: '/experiment', builder: (_, _) => const ExperimentScreen()),
      GoRoute(path: '/quiz', builder: (_, _) => const QuizScreen()),
      GoRoute(
        path: '/quiz-feedback',
        builder: (_, _) => const QuizFeedbackScreen(),
      ),
      GoRoute(path: '/studio', builder: (_, _) => const StudioScreen()),
      GoRoute(
        path: '/record-measurements',
        builder: (_, _) => const RecordMeasurementsScreen(),
      ),
      GoRoute(
        path: '/health-import',
        builder: (_, _) => const HealthImportScreen(),
      ),
    ],
  );
}
