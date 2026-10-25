import 'package:flutter/material.dart';

import '../experiment/experiment_page.dart';
import '../experiment/widgets/widgets.dart';
import '../twin/twin_repository.dart';
import '../ui/theme.dart';
import '../ui/widgets/widgets.dart' hide TwinMood;
import '../widgets/whole_word_text.dart';
import 'consent_screens.dart';
import 'consents.dart';
import 'checkin_reminders.dart' show reminderLines, reminderTitle;

/// "My data" (Z-21): everything LifeTwin keeps is on this phone. Memory switch (`memory_consent`),
/// Mochi's notebook (read only; there is no edit field), AI and privacy, Apple Health access (changed in
/// iPhone Settings), and Delete my data (two confirms; Z-22, Z-36). Deleting wipes answers, check-in
/// history, logs, habit notes, the twin look, consents and reminders, and the app returns to first run.
class MyDataScreen extends StatelessWidget {
  const MyDataScreen({
    super.key,
    required this.repository,
    required this.consents,
    required this.onBack,
    required this.onAiPrivacy,
    required this.onDeleted,
    this.onNotebook,
    this.onHealthSettings,
    this.onWeeklyCheckIn,
    this.onReminders,
  });

  final TwinRepository repository;
  final ConsentStore consents;
  final VoidCallback onBack;
  final VoidCallback onAiPrivacy;

  /// After everything is deleted: back to the start.
  final VoidCallback onDeleted;
  final VoidCallback? onNotebook;
  final VoidCallback? onHealthSettings;

  /// The weekly check-in whenever the person wants it, whether or not one is due.
  final VoidCallback? onWeeklyCheckIn;
  final VoidCallback? onReminders;

  /// Wipes the phone: [TwinRepository.deleteMyData] clears answers, history, notes, the outside-AI consent, the
  /// twin look and the planned reminders; the conversation's AI helper choice goes too. Apple Health is not touched.
  Future<void> deleteEverything() async {
    await repository.deleteMyData();
    consents.setAiHelper(false);
  }

  Future<void> _memory(BuildContext context, bool on) async {
    if (!on && repository.store.habitNotes.isNotEmpty) {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (c) => _TwoStep(
          title: 'Turn off memory?',
          body: 'Mochi’s notebook on this phone will be cleared.',
          keepLabel: 'Keep it on',
          goLabel: 'Turn off and clear',
          onKeep: () => Navigator.of(c).pop(false),
          onGo: () => Navigator.of(c).pop(true),
        ),
      );
      if (ok != true) return;
    }
    await repository.applyMemoryConsent(on);
  }

  Future<void> _delete(BuildContext context) async {
    final first = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      // Full height when needed: at large text the words and both buttons are taller than the default sheet.
      isScrollControlled: true,
      builder: (c) => _TwoStep(
        title: 'Delete your data?',
        body: 'This erases everything Mochi saved on this phone. It can’t be undone. Answers, check-ins, notes, your twin’s look, privacy choices, reminders. Apple Health stays as it is.',
        keepLabel: 'Keep my data',
        goLabel: 'Delete everything',
        onKeep: () => Navigator.of(c).pop(false),
        onGo: () => Navigator.of(c).pop(true),
      ),
    );
    if (first != true || !context.mounted) return;
    final second = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      // Full height when needed: at large text the words and both buttons are taller than the default sheet.
      isScrollControlled: true,
      builder: (c) => _TwoStep(
        title: 'Delete everything now?',
        body: 'It can’t be undone.',
        keepLabel: 'Keep my data',
        goLabel: 'Yes, delete',
        onKeep: () => Navigator.of(c).pop(false),
        onGo: () => Navigator.of(c).pop(true),
        goIcon: Icons.delete_outline_rounded,
      ),
    );
    if (second != true) return;
    await deleteEverything();
    onDeleted();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([repository, consents]),
    builder: (context, _) {
      final memory = repository.store.memoryConsent;
      final notes = repository.store.habitNotes.length;
      return ExperimentPage(
        mode: LtMode.customize,
        title: 'My data',
        onBack: onBack,
        backLabel: 'Back to settings',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: LtColors.paper,
                borderRadius: BorderRadius.circular(LtRadii.panel),
                border: Border.all(color: LtColors.container, width: LtBorders.container),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text(savedOnPhone, style: LtText.display(24))),
                  const SavedOnPhoneNote(),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      for (final (icon, t) in [
                        (Icons.description_outlined, 'Answers and notes'),
                        (Icons.event_note_outlined, 'Check-ins and logs'),
                        (Icons.checkroom_rounded, 'Mochi’s look'),
                        (Icons.notifications_none_rounded, 'Reminders'),
                      ])
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 20, color: LtColors.ink),
                            const SizedBox(width: 6),
                            Flexible(child: WholeWordText(t, style: LtText.body())),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Row(
              icon: Icons.description_outlined,
              title: 'Mochi remembers',
              toggle: memory,
              onTap: () => _memory(context, !memory),
              semantic: 'Mochi remembers. ${memory ? 'On' : 'Off'}',
            ),
            if (memory) ...[
              const SizedBox(height: 8),
              _Row(
                icon: Icons.menu_book_outlined,
                title: 'Mochi’s notebook',
                sub: '$notes ${notes == 1 ? 'note' : 'notes'} · read only',
                onTap: onNotebook,
                semantic: 'Mochi’s notebook, $notes notes, read only',
              ),
            ],
            if (onWeeklyCheckIn != null) ...[
              const SizedBox(height: 8),
              _Row(
                icon: Icons.calendar_month_outlined,
                title: 'Weekly check-in',
                sub: repository.weeklyGateLine ?? 'Do it now',
                onTap: repository.weeklyAvailable ? onWeeklyCheckIn : null,
                semantic: 'Weekly check-in. ${repository.weeklyGateLine ?? 'Do it now.'}',
              ),
            ],
            if (onReminders != null) ...[
              const SizedBox(height: 8),
              _Row(
                icon: Icons.notifications_none_rounded,
                title: 'Reminders',
                onTap: onReminders,
                semantic: 'Reminders',
              ),
            ],
            const SizedBox(height: 8),
            _Row(
              icon: Icons.auto_awesome_rounded,
              title: 'AI and privacy',
              sub: 'What may be sent',
              onTap: onAiPrivacy,
              semantic: 'AI and privacy. What may be sent.',
            ),
            const SizedBox(height: 8),
            _Row(
              icon: Icons.favorite_border_rounded,
              title: 'Apple Health access',
              sub: 'Change in iPhone Settings',
              onTap: onHealthSettings,
              semantic: 'Apple Health access. Change in iPhone Settings.',
            ),
            const SizedBox(height: 8),
            _Row(
              icon: Icons.delete_outline_rounded,
              title: 'Delete my data',
              onTap: () => _delete(context),
              semantic: 'Delete my data',
            ),
          ],
        ),
      );
    },
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.semantic, this.sub, this.onTap, this.toggle});
  final IconData icon;
  final String title;
  final String? sub;
  final String semantic;
  final VoidCallback? onTap;
  final bool? toggle;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      button: true,
      toggled: toggle,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          decoration: BoxDecoration(
            color: LtColors.paper,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: LtColors.control, width: LtBorders.control),
          ),
          child: Row(
            children: [
              LeverIcon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WholeWordText(title, style: LtText.body(size: 18, weight: FontWeight.w700)),
                    if (sub != null) WholeWordText(sub!, style: LtText.body(color: LtColors.secondary)),
                  ],
                ),
              ),
              if (toggle != null)
                Container(
                  width: 64,
                  height: 38,
                  padding: const EdgeInsets.all(3),
                  alignment: toggle! ? Alignment.centerRight : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: toggle! ? LtColors.mint : LtColors.trackOff,
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: LtColors.controlOnMint, width: LtBorders.control),
                  ),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: LtColors.paper,
                      shape: BoxShape.circle,
                      border: Border.all(color: LtColors.controlOnMint, width: LtBorders.control),
                    ),
                    child: toggle! ? const Icon(Icons.check_rounded, size: 16, color: LtColors.ink) : null,
                  ),
                )
              else if (onTap != null)
                const Icon(Icons.chevron_right_rounded, size: 28, color: LtColors.ink),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A destructive confirmation (HIG): "Keep" is the main button, the other is secondary.
class _TwoStep extends StatelessWidget {
  const _TwoStep({
    required this.title,
    required this.body,
    required this.keepLabel,
    required this.goLabel,
    required this.onKeep,
    required this.onGo,
    this.goIcon,
  });
  final String title;
  final String body;
  final String keepLabel;
  final String goLabel;
  final VoidCallback onKeep;
  final VoidCallback onGo;
  final IconData? goIcon;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LtColors.paper,
          borderRadius: BorderRadius.circular(LtRadii.panel),
          border: Border.all(color: LtColors.container, width: LtBorders.container),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: WholeWordText(title, style: LtText.display(26))),
              const SizedBox(height: 8),
              WholeWordText(body, style: LtText.body()),
              const SizedBox(height: 16),
              LipButton(label: keepLabel, height: 64, fontSize: 22, onTap: onKeep),
              const SizedBox(height: 10),
              LipButton(label: goLabel, icon: goIcon, kind: LipKind.secondary, height: 56, fontSize: 21, onTap: onGo),
            ],
          ),
        ),
      ),
    ),
  );
}

/// "Reminders" (Z-18): one daily reminder, off until turned on. The engine's `CheckinReminders` asks the phone
/// for permission the first time it is turned on and plans local notifications; the preference is
/// `TwinRepository.checkinSettings`. The notification never carries health details.
class ReminderSettingsScreen extends StatelessWidget {
  const ReminderSettingsScreen({super.key, required this.repository, required this.onBack, this.now});
  final TwinRepository repository;
  final VoidCallback onBack;
  final DateTime Function()? now;

  DateTime _now() => (now ?? DateTime.now)();

  Future<void> _set(bool on, {int? hour, int? minute}) async {
    final reminders = repository.reminders;
    if (reminders == null) return;
    final s = repository.checkinSettings;
    final next = on
        ? await reminders.accept(s, localNow: _now(), history: repository.store.checkins, hour: hour, minute: minute)
        : await reminders.turnOff(s);
    await repository.saveCheckinSettings(next);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: repository,
    builder: (context, _) {
      final s = repository.checkinSettings;
      return ExperimentPage(
        mode: LtMode.customize,
        title: 'Reminders',
        onBack: onBack,
        backLabel: 'Back to settings',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('What it looks like', style: LtText.body(weight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LtColors.paper,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: LtColors.container, width: 1.5),
              ),
              child: Semantics(
                label: 'Notification preview: LifeTwin. $reminderTitle: ${reminderLines.first}',
                excludeSemantics: true,
                child: Row(
                  children: [
                    const LeverIcon(Icons.notifications_none_rounded, size: 40),
                    const SizedBox(width: 10),
                    Expanded(child: WholeWordText('$reminderTitle: ${reminderLines.first}', style: LtText.body())),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _Row(
              icon: Icons.wb_sunny_outlined,
              title: 'Check-in reminder',
              sub: s.remindersOn ? 'At ${_time(s.reminderHour, s.reminderMinute)}' : 'Off',
              toggle: s.remindersOn,
              onTap: repository.reminders == null ? null : () => _set(!s.remindersOn),
              semantic: 'Check-in reminder. ${s.remindersOn ? 'On' : 'Off'}',
            ),
            if (s.remindersOn) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final (h, m, label) in [
                    (9, 0, 'Morning 9:00'),
                    (10, 0, 'Morning 10:00'),
                    (19, 30, 'Evening 7:30'),
                  ])
                    ChoiceChip(
                      label: Text(label, style: LtText.body(weight: FontWeight.w700)),
                      selected: s.reminderHour == h && s.reminderMinute == m,
                      onSelected: (_) => _set(true, hour: h, minute: m),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );

  static String _time(int h, int m) {
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$hh:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }
}
