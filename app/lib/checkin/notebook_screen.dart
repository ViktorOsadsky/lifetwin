import 'package:flutter/material.dart';

import '../experiment/experiment_page.dart';
import '../twin/twin_repository.dart';
import '../ui/theme.dart';
import '../ui/widgets/widgets.dart' hide TwinMood;
import '../widgets/whole_word_text.dart';
import 'consent_screens.dart' show EqualChoice;

/// "Mochi's notebook" (R-4, R-5): the habit notes Mochi saved while memory is on, with their dates, and
/// the Memory switch. The engine has no per-note delete, so notes are read only here and "forget" means
/// turning memory off, which clears every note (`applyMemoryConsent(false)`). Two steps, equal weight on
/// the second. Answers and the outlook are never touched.
class NotebookScreen extends StatelessWidget {
  const NotebookScreen({super.key, required this.repository, required this.onBack});
  final TwinRepository repository;
  final VoidCallback onBack;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _date(Object? at) {
    final d = DateTime.tryParse('$at');
    return d == null ? '' : '${_months[d.month - 1]} ${d.day}';
  }

  Future<void> _setMemory(BuildContext context, bool on) async {
    if (on) return repository.applyMemoryConsent(true);
    final n = repository.store.habitNotes.length;
    final off = await _ask(
      context,
      title: 'Turn off memory?',
      body: n == 0
          ? 'Mochi will stop saving notes. Your answers and outlook stay.'
          : 'Mochi will forget your ${_notes(n)}. You can’t get them back. Your answers and outlook stay.',
      child: (c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LipButton(label: 'Keep memory', fontSize: 22, onTap: () => Navigator.of(c).pop(false)),
          const SizedBox(height: 10),
          LipButton(
            label: n == 0 ? 'Turn off' : 'Turn off and forget',
            kind: LipKind.secondary,
            height: 56,
            fontSize: 21,
            onTap: () => Navigator.of(c).pop(true),
          ),
        ],
      ),
    );
    if (off != true || !context.mounted) return;
    if (n > 0) {
      final forget = await _ask(
        context,
        title: 'Forget $n ${n == 1 ? 'note' : 'notes'}?',
        body: 'They’ll be gone for good.',
        child: (c) => EqualChoice(
          noLabel: 'Keep them',
          yesLabel: 'Forget notes',
          onNo: () => Navigator.of(c).pop(false),
          onYes: () => Navigator.of(c).pop(true),
        ),
      );
      if (forget != true) return;
    }
    await repository.applyMemoryConsent(false);
  }

  static String _notes(int n) => '$n ${n == 1 ? 'note' : 'notes'}';

  Future<bool?> _ask(
    BuildContext context, {
    required String title,
    required String body,
    required Widget Function(BuildContext) child,
  }) => showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: LtColors.paper,
            borderRadius: BorderRadius.circular(LtRadii.panel),
            border: Border.all(color: LtColors.container, width: LtBorders.container),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, child: Text(title, style: LtText.display(26))),
                const SizedBox(height: 8),
                WholeWordText(body, style: LtText.body()),
                const SizedBox(height: 16),
                child(c),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repository,
    builder: (context, _) {
      final on = repository.store.memoryConsent;
      final notes = on ? repository.store.habitNotes : const <Map<String, dynamic>>[];
      return ExperimentPage(
        mode: LtMode.customize,
        title: 'Mochi’s notebook',
        onBack: onBack,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!on)
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(header: true, child: Text('Memory is off.', style: LtText.display(24))),
                    const SizedBox(height: 4),
                    WholeWordText(
                      'Turn it on and Mochi can remember the little things for more personal ideas.',
                      style: LtText.body(),
                    ),
                  ],
                ),
              )
            else if (notes.isEmpty)
              _Card(
                child: WholeWordText(
                  'No notes yet. Mochi saves a note when you mention a habit.',
                  style: LtText.body(),
                ),
              )
            else ...[
              Semantics(header: true, child: Text(_notes(notes.length), style: LtText.display(22))),
              const SizedBox(height: 4),
              WholeWordText(
                'Mochi remembers these to make suggestions fit you.',
                style: LtText.body(color: LtColors.secondary),
              ),
              const SizedBox(height: 10),
              for (final row in notes)
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_date(row['at']), style: LtText.body(size: 16, color: LtColors.secondary)),
                      WholeWordText(
                        '${(row['note'] is Map ? (row['note'] as Map)['text'] : null) ?? ''}',
                        style: LtText.body(size: 20, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 4),
            _Card(
              child: MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Memory', style: LtText.body(size: 18, weight: FontWeight.w700)),
                          Text(on ? 'On' : 'Off', style: LtText.body(color: LtColors.secondary)),
                        ],
                      ),
                    ),
                    Switch(value: on, onChanged: (v) => _setMemory(context, v)),
                  ],
                ),
              ),
            ),
            if (on)
              WholeWordText(
                'Notes shape ideas. Numbers stay the same. Turning memory off clears these notes.',
                style: LtText.body(color: LtColors.secondary),
              ),
          ],
        ),
      );
    },
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: LtColors.paper,
      borderRadius: BorderRadius.circular(LtRadii.panel),
      border: Border.all(color: LtColors.container, width: LtBorders.container),
    ),
    child: child,
  );
}
