import 'package:flutter/material.dart';

import '../experiment/experiment_page.dart';
import '../experiment/experiment_twins.dart';
import '../experiment/widgets/widgets.dart';
import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart' hide TwinMood;
import '../widgets/whole_word_text.dart';
import 'consents.dart';

/// "Saved on this phone", with the full sentence behind a tap (required wording): even with outside
/// AI off, answers go to LifeTwin's server to be understood, and the server keeps nothing.
const savedOnPhone = 'Saved on this phone';
const serverSentence = 'LifeTwin’s server reads your answers to understand them, but doesn’t keep them.';

class SavedOnPhoneNote extends StatelessWidget {
  const SavedOnPhoneNote({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Saved on this phone. More about the server.',
    excludeSemantics: true,
    onTap: () => showInfoSheet(context, title: savedOnPhone, body: serverSentence),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showInfoSheet(context, title: savedOnPhone, body: serverSentence),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smartphone_rounded, size: 20, color: LtColors.ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                savedOnPhone,
                style: LtText.body(weight: FontWeight.w700)
                    .copyWith(decoration: TextDecoration.underline, decorationThickness: 2),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.info_outline_rounded, size: 18, color: LtColors.ink),
          ],
        ),
      ),
    ),
  );
}

/// Yes and No: the same size, style and weight. Nothing is pre-selected.
class EqualChoice extends StatelessWidget {
  const EqualChoice({
    super.key,
    required this.noLabel,
    required this.yesLabel,
    required this.onNo,
    required this.onYes,
  });
  final String noLabel;
  final String yesLabel;
  final VoidCallback onNo;
  final VoidCallback onYes;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: LipButton(label: noLabel, kind: LipKind.secondary, height: 64, fontSize: 21, onTap: onNo),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: LipButton(label: yesLabel, kind: LipKind.secondary, height: 64, fontSize: 21, onTap: onYes),
      ),
    ],
  );
}

/// Memory opt-in (Z-3): asked once, early, right after the basics. On: habit notes go to Mochi's notebook
/// on this phone. Off: nothing is kept and the notebook is hidden. Separate from outside AI.
class MemoryConsentScreen extends StatelessWidget {
  const MemoryConsentScreen({super.key, required this.appearance, required this.onChoose, required this.onBack});

  final TwinAppearance appearance;
  final ValueChanged<bool> onChoose;
  final VoidCallback onBack;

  static const question =
      'Can I remember the little things you tell me? It helps me give you better suggestions. You can change this any time.';

  @override
  Widget build(BuildContext context) => ExperimentPage(
    mode: LtMode.onboarding,
    onBack: onBack,
    dock: Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EqualChoice(
            noLabel: 'No thanks',
            yesLabel: 'Yes, remember',
            onNo: () => onChoose(false),
            onYes: () => onChoose(true),
          ),
          const SizedBox(height: 6),
          Text('Either way, Mochi still helps.', style: LtText.body(color: LtColors.secondary)),
        ],
      ),
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExperimentPlate(
          appearance: appearance,
          twins: const [TwinSlot(state: steadyTwin, x: 0.3)],
          bubble: 'One quick choice.',
        ),
        const SizedBox(height: 14),
        Sheet(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text('Mochi’s notebook', style: LtText.display(28))),
              const SizedBox(height: 6),
              WholeWordText.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Mochi  ',
                      style: LtText.body(weight: FontWeight.w700, color: LtColors.secondary),
                    ),
                    const TextSpan(text: question),
                  ],
                ),
                style: LtText.body(),
              ),
              const SavedOnPhoneNote(),
            ],
          ),
        ),
      ],
    ),
  );
}

/// What is sent to the outside AI provider, in full (behind "What's sent?").
const sentSentences = [
  'Everything you tell Mochi, including health answers like diabetes or blood pressure.',
  'Apple Health numbers, like sleep and activity.',
  'Your conversation and habit notes.',
  'Never your name or contact details.',
];

void showWhatsSent(BuildContext context) => showInfoSheet(
  context,
  title: 'What’s sent?',
  body: sentSentences.first,
  extra: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final s in sentSentences.skip(1))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: WholeWordText(s, style: LtText.body()),
        ),
    ],
  ),
);

/// Personal suggestions consent (Z-24), and the re-ask when the provider changes (Z-27).
///
/// Its own screen and its own yes: all answers, including Apple Health numbers, go under this one
/// consent (never bundled with Apple Health or notifications). The provider name is [AiProvider.displayName]
/// from `/api/capabilities`; the screen is not offered when no provider is configured. Nothing is sent
/// before a yes. Back is the same as "No thanks": built-in tips. No promise is made about the
/// provider's own retention.
class OutsideAiConsentScreen extends StatelessWidget {
  const OutsideAiConsentScreen({
    super.key,
    required this.provider,
    required this.onChoose,
    this.reconsent = false,
    this.appearance,
  });

  final AiProvider provider;
  final ValueChanged<bool> onChoose;

  /// The provider changed since the last answer (Z-27): "A new AI provider".
  final bool reconsent;
  final TwinAppearance? appearance;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) onChoose(false);
    },
    child: ExperimentPage(
      mode: LtMode.customize,
      title: reconsent ? 'A new AI provider' : 'Personal suggestions?',
      onBack: () => onChoose(false),
      backLabel: 'Back. Same as No thanks',
      dock: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EqualChoice(
              noLabel: 'No thanks',
              yesLabel: reconsent ? 'Yes, that’s OK' : 'Yes, share',
              onNo: () => onChoose(false),
              onYes: () => onChoose(true),
            ),
            if (provider.trainingLine case final line?) ...[const SizedBox(height: 6), TrainingLine(line)],
            const SizedBox(height: 6),
            Text(
              'No thanks? You’ll still get built-in tips.',
              style: LtText.body(color: LtColors.secondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const LeverIcon(Icons.auto_awesome_rounded, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Just for you', style: LtText.display(24)),
                    WholeWordText('With ${provider.displayName}', style: LtText.body(color: LtColors.secondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (reconsent)
            WholeWordText(
              'We now use ${provider.displayName} for personal suggestions. Is that OK? Same things are sent.',
              style: LtText.body(),
            )
          else ...[
            Semantics(
              header: true,
              child: Text('Sends', style: LtText.body(weight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            for (final (icon, text, bold) in [
              (Icons.chat_bubble_outline_rounded, 'What you tell Mochi, and notes', false),
              (Icons.favorite_border_rounded, 'Health answers, like blood pressure', false),
              (Icons.directions_run_rounded, 'Apple Health numbers', false),
              (Icons.lock_outline_rounded, 'Never your name or contact details', true),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    LeverIcon(icon, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: WholeWordText(text, style: LtText.body(weight: bold ? FontWeight.w700 : FontWeight.w400)),
                    ),
                  ],
                ),
              ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showWhatsSent(context),
              icon: const Icon(Icons.info_outline_rounded, size: 20),
              label: Text(
                'What’s sent?',
                style: LtText.body(weight: FontWeight.w700)
                    .copyWith(decoration: TextDecoration.underline, decorationThickness: 2),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.check_rounded, size: 22, color: Color(0xFF17594A)),
              const SizedBox(width: 8),
              Expanded(child: WholeWordText('Off unless you say yes. Turn off anytime.', style: LtText.body())),
            ],
          ),
        ],
      ),
    ),
  );
}

/// "Meta may use what you share to improve its AI." (the company comes from the server): shown beside an
/// outside-AI Yes button only when the server says the provider may train on content.
class TrainingLine extends StatelessWidget {
  const TrainingLine(this.line, {super.key});
  final String line;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: WholeWordText(
      line,
      style: LtText.body(weight: FontWeight.w700),
      textAlign: TextAlign.center,
    ),
  );
}

/// "AI and privacy" (Z-25): two separate whole-row switches, both off until turned on. The provider
/// comes from `/api/capabilities`. Turning Personal suggestions on opens the consent first
/// ([onAskOutsideAi]); turning it off just turns it off.
class AiSettingsScreen extends StatelessWidget {
  const AiSettingsScreen({
    super.key,
    required this.consents,
    required this.provider,
    required this.onAskOutsideAi,
    required this.onBack,
  });

  final ConsentStore consents;
  final AiProvider? provider;
  final VoidCallback onAskOutsideAi;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: consents,
    builder: (context, _) {
      final p = provider;
      final name = p?.displayName;
      final suggestionsOn = p != null && consents.outsideAiFor(p.id) == true;
      return ExperimentPage(
        mode: LtMode.customize,
        title: 'AI and privacy',
        onBack: onBack,
        backLabel: 'Back to my data',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WholeWordText('Off unless you turn it on.', style: LtText.body(color: LtColors.secondary)),
            const SizedBox(height: 10),
            // The AI helper reads conversation answers: the server's `conversation` provider
            // (Claude today), which may differ from Personal suggestions'.
            _SwitchRow(
              icon: Icons.mic_none_rounded,
              title: 'AI helper',
              sub: p == null
                  ? 'Only reads answers Mochi didn’t understand'
                  : 'Only reads answers Mochi didn’t understand · Sends to ${p.helper.displayName}',
              value: consents.aiHelper,
              enabled: p != null && p.helper.configured,
              onChanged: consents.setAiHelper,
            ),
            const SizedBox(height: 10),
            _SwitchRow(
              icon: Icons.auto_awesome_rounded,
              title: 'Personal suggestions',
              sub: name == null ? 'Uses everything you tell Mochi' : 'Uses everything you tell Mochi · With $name',
              value: suggestionsOn,
              enabled: p != null && p.configured,
              onChanged: (on) => on ? onAskOutsideAi() : consents.setOutsideAi(p!.id, false),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => showWhatsSent(context),
                child: Text(
                  'What’s sent?',
                  style: LtText.body(weight: FontWeight.w700)
                      .copyWith(decoration: TextDecoration.underline, decorationThickness: 2),
                ),
              ),
            ),
            if (p?.trainingLine case final line?) TrainingLine(line),
            if (p == null || !p.configured)
              WholeWordText(
                'No AI provider is set up. You’ll get built-in tips.',
                style: LtText.body(color: LtColors.secondary),
              ),
          ],
        ),
      );
    },
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.sub,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String sub;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      toggled: value,
      enabled: enabled,
      label: '$title. $sub',
      excludeSemantics: true,
      onTap: enabled ? () => onChanged(!value) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(!value) : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
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
                    Text(title, style: LtText.body(size: 18, weight: FontWeight.w700)),
                    WholeWordText(sub, style: LtText.body(color: LtColors.secondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Track(on: value),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Track extends StatelessWidget {
  const _Track({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => Container(
    width: 64,
    height: 38,
    padding: const EdgeInsets.all(3),
    alignment: on ? Alignment.centerRight : Alignment.centerLeft,
    decoration: BoxDecoration(
      color: on ? LtColors.mint : LtColors.trackOff,
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
      child: on ? const Icon(Icons.check_rounded, size: 16, color: LtColors.ink) : null,
    ),
  );
}

/// The "From built-in tips" tag on a suggestion made without outside AI (Z-26).
class BuiltInTipTag extends StatelessWidget {
  const BuiltInTipTag({super.key});

  @override
  Widget build(BuildContext context) => DashedBox(
    color: LtColors.control,
    radius: 16,
    fill: LtColors.paper,
    constraints: const BoxConstraints(minHeight: 32),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Center(
      widthFactor: 1,
      child: Text('From built-in tips', style: LtText.body(weight: FontWeight.w700)),
    ),
  );
}
