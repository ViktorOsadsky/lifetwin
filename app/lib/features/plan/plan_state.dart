import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/experiment_state.dart';

/// A ranked plan item. Model and evidence rows are placeholders until the
/// model and research are connected; nothing here is a computed number.
class PlanItem {
  const PlanItem({
    required this.id,
    required this.title,
    required this.assumed,
    required this.why,
  });

  final String id;
  final String title;
  final AssumedChange assumed;
  final String why;
}

const planItems = [
  PlanItem(
    id: 'active-150',
    title: 'Add 150 active minutes a week',
    assumed: AssumedChange(kind: ChangeKind.activity, delta: 150),
    why: 'A bounded single change to the activity input.',
  ),
  PlanItem(
    id: 'sleep-1',
    title: 'Sleep one more hour a night',
    assumed: AssumedChange(kind: ChangeKind.sleep, delta: 1),
    why: 'A bounded single change to the sleep input.',
  ),
  PlanItem(
    id: 'active-60',
    title: 'Add 60 active minutes a week',
    assumed: AssumedChange(kind: ChangeKind.activity, delta: 60),
    why: 'A smaller step on the activity input.',
  ),
];

enum PlanStatus { open, added, skipped }

class PlanStatusNotifier extends Notifier<Map<String, PlanStatus>> {
  @override
  Map<String, PlanStatus> build() => const {};

  void set(String id, PlanStatus status) => state = {...state, id: status};
}

final planStatusProvider =
    NotifierProvider<PlanStatusNotifier, Map<String, PlanStatus>>(
      PlanStatusNotifier.new,
    );
