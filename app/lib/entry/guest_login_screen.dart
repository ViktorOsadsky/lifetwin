import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/widgets/widgets.dart';

/// A local guest entry, not remote authentication. Entering never grants provider,
/// microphone, memory or health-import consent; those remain in their own flows.
class GuestLoginScreen extends StatefulWidget {
  const GuestLoginScreen({super.key, required this.onContinue, this.unavailable = false});

  final Future<void> Function()? onContinue;
  final bool unavailable;

  @override
  State<GuestLoginScreen> createState() => _GuestLoginScreenState();
}

class _GuestLoginScreenState extends State<GuestLoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _continue() async {
    if (_busy || widget.onContinue == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onContinue!();
    } catch (_) {
      if (mounted) setState(() => _error = 'We couldn’t save your guest choice. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ModeScaffold(
    mode: LtMode.room,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text('Welcome to LifeTwin', style: LtText.display(34), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 8),
              Text('A little twin. A healthier routine.', style: LtText.body(size: 20), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ExcludeSemantics(
                child: SizedBox(
                  height: 210,
                  child: Center(child: TwinSprite(appearance: const TwinAppearance(), height: 210)),
                ),
              ),
              const SizedBox(height: 20),
              Sheet(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Guest login', style: LtText.display(26)),
                    const SizedBox(height: 10),
                    Text(
                      'No account or email needed. Your saved twin and history stay on this device.',
                      style: LtText.body(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'You choose what to share with AI helpers later.',
                      style: LtText.body(color: LtColors.secondary),
                    ),
                    const SizedBox(height: 22),
                    LipButton(
                      label: _busy ? 'Opening your twin…' : 'Continue as guest',
                      fontSize: 22,
                      onTap: _busy || widget.onContinue == null ? null : _continue,
                    ),
                    if (widget.onContinue == null || _error != null) ...[
                      const SizedBox(height: 14),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error ??
                              (widget.unavailable
                                  ? 'Your saved data couldn’t be opened. Please close and reopen LifeTwin to try again.'
                                  : 'Getting your twin ready…'),
                          style: LtText.body(color: LtColors.secondary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
