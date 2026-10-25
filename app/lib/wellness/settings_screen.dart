import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/whole_word_text.dart';

import '../ui/theme.dart';
import 'models.dart';
import 'widgets.dart';

/// R-2's navigation surface. The existing consent, reminder and My data routes
/// own their confirmations and protected-store writes; Settings has no copy of
/// those flows or separate consent store. Values always come from that owner.
class WellnessSettingsScreen extends StatelessWidget {
  const WellnessSettingsScreen({
    super.key,
    required this.settings,
    required this.onMemory,
    required this.onSuggestions,
    required this.onReminders,
    required this.onMyData,
    required this.onBack,
    this.entries = const [],
  });
  final ValueListenable<WellnessSettings> settings;
  final VoidCallback onMemory;
  final VoidCallback onSuggestions;
  final VoidCallback onReminders;
  final VoidCallback onMyData;
  final VoidCallback onBack;
  final List<SettingsEntry> entries;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<WellnessSettings>(
        valueListenable: settings,
        builder: (context, value, _) => WellnessPage(
          title: 'Settings',
          onBack: onBack,
          children: [
            if (entries.isNotEmpty) ...[
              WholeWordText('Yours', style: LtText.display(22)),
              const SizedBox(height: 10),
              WellnessCard(
                child: Column(
                  children: [
                    for (final entry in entries)
                      _row(entry.label, entry.description, entry.open, enabled: entry.enabled),
                  ],
                ),
              ),
            ],
            WholeWordText('Choices', style: LtText.display(22)),
            const SizedBox(height: 10),
            WellnessCard(
              child: Column(
                children: [
                  _row(
                    'Memory & notebook',
                    value.memoryConsent ? 'On' : 'Off',
                    onMemory,
                  ),
                  const Divider(height: 24),
                  _row(
                    'Personal suggestions',
                    value.personalSuggestions ? 'On' : 'Off',
                    onSuggestions,
                  ),
                  const Divider(height: 24),
                  _row(
                    'Reminders',
                    TimeOfDay(
                      hour: value.reminderMinutes ~/ 60,
                      minute: value.reminderMinutes % 60,
                    ).format(context),
                    onReminders,
                  ),
                ],
              ),
            ),
            WholeWordText(
              'Your choices are saved on this phone. Personal suggestions uses your current choice with each request.',
              style: LtText.body(size: 15),
            ),
            const SizedBox(height: 18),
            WellnessCard(
              child: _row('My data', 'See your data or delete it', onMyData),
            ),
          ],
        ),
      );

  Widget _row(String label, String? description, VoidCallback open, {bool enabled = true}) {
    // Muted but still above 4.5:1 on the card.
    const muted = Color(0xFF6E5E57);
    return ListTile(
      enabled: enabled,
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 8,
      title: WholeWordText(label, style: LtText.body(weight: FontWeight.w700, color: enabled ? LtColors.ink : muted)),
      subtitle: description == null
          ? null
          : WholeWordText(description, style: LtText.body(size: 17, color: enabled ? LtColors.ink : muted)),
      trailing: enabled ? const Icon(Icons.chevron_right_rounded) : null,
      onTap: enabled ? open : null,
    );
  }
}

/// History, Apple Health, upload, wristband and voice routes supplied by the shell.
class SettingsEntry {
  const SettingsEntry({
    required this.label,
    required this.open,
    this.description,
    this.enabled = true,
  });
  final String label;
  final String? description;
  final VoidCallback open;

  /// False: shown dimmed and not tappable (the screen reader says "dimmed").
  final bool enabled;
}
