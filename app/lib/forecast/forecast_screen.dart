import 'package:flutter/material.dart';

import '../onboarding/voice_onboarding_screen.dart' show BigButton;
import '../voice/speech.dart';
import 'forecast_client.dart';

/// The mascot's sentence for a supported forecast. Spoken and shown, word for word.
String forecastSentence(Forecast f) {
  final years = f.maxHorizonYears;
  return 'Out of 100 people with answers like yours, about ${f.outOf100(years)} '
      'were still living $years ${years == 1 ? 'year' : 'years'} later.';
}

String unsupportedSentence(Forecast f) =>
    "I can't make a forecast for you yet. ${f.reason ?? 'The model does not cover these answers.'}";

const couldNotReach = "I couldn't get your forecast just now.";

/// Magic-ball forecast: awaiting model, a short reveal, then the mascot's result.
/// Never shows a date, a countdown or a "life expectancy".
class ForecastScreen extends StatefulWidget {
  const ForecastScreen({
    super.key,
    required this.client,
    required this.profile,
    required this.onBack,
    this.speech,
  });

  final ForecastClient client;

  /// The confirmed answers. Sent as they are; nothing is guessed here.
  final Map<String, dynamic> profile;
  final VoidCallback onBack;

  /// Set when voice is on; the mascot then says its sentence aloud.
  final SpeechOutput? speech;

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  Forecast? _forecast;
  ForecastFailure? _error;
  bool _loading = true;
  bool _spoke = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _retry() {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  Future<void> _load() async {
    _reveal.value = 0;
    try {
      final f = await widget.client.predict(widget.profile);
      if (!mounted) return;
      setState(() {
        _forecast = f;
        _loading = false;
      });
      if (MediaQuery.disableAnimationsOf(context)) {
        _reveal.value = 1;
      } else {
        await _reveal.forward();
      }
      if (!mounted) return;
      await _say(f.supported ? forecastSentence(f) : unsupportedSentence(f));
    } on ForecastFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      await _say(couldNotReach);
    }
  }

  Future<void> _say(String line) async {
    final speech = widget.speech;
    if (speech == null) return;
    _spoke = true;
    try {
      await speech.speak(line).timeout(const Duration(seconds: 60));
    } catch (_) {
      // The words are on screen; a voice problem changes nothing else.
    }
  }

  void _back() {
    if (_spoke) widget.speech?.stop();
    widget.onBack();
  }

  @override
  void dispose() {
    if (_spoke) widget.speech?.stop();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = _forecast;
    return Scaffold(
      appBar: AppBar(title: const Text('Your forecast')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _MagicBall(reveal: _reveal, dim: f != null && !f.supported)),
              const SizedBox(height: 24),
              if (_loading)
                const _MascotLine('Looking into the magic ball…')
              else if (_error != null)
                ..._failed(context)
              else if (!f!.supported)
                ..._unsupported(f)
              else
                FadeTransition(opacity: _reveal, child: _Result(forecast: f, onBack: _back, speech: widget.speech)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _failed(BuildContext context) => [
    const _MascotLine(couldNotReach),
    const SizedBox(height: 12),
    Text(_error?.plain ?? 'Please check the connection and try again.', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 32),
    BigButton(label: 'Try again', filled: true, onTap: _retry),
    const SizedBox(height: 16),
    BigButton(label: 'Go back', filled: false, onTap: _back),
  ];

  List<Widget> _unsupported(Forecast f) => [
    _MascotLine(unsupportedSentence(f)),
    const SizedBox(height: 32),
    BigButton(label: 'Go back to my answers', filled: true, onTap: _back),
  ];
}

class _Result extends StatelessWidget {
  const _Result({required this.forecast, required this.onBack, this.speech});

  final Forecast forecast;
  final VoidCallback onBack;
  final SpeechOutput? speech;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final f = forecast;
    final years = f.survival.keys.toList()..sort();
    final body = text.titleLarge?.copyWith(height: 1.4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MascotLine(forecastSentence(f)),
        const SizedBox(height: 28),
        for (final y in years)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'After $y ${y == 1 ? 'year' : 'years'}: '),
                  TextSpan(
                    text: 'about ${f.outOf100(y)} in 100',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              style: body,
            ),
          ),
        const SizedBox(height: 20),
        _DotGrid(filled: f.outOf100(f.maxHorizonYears)),
        const SizedBox(height: 12),
        Text(
          'Each dot is one person. A filled dot is someone still living '
          'after ${f.maxHorizonYears} years.',
          style: text.titleMedium?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 32),
        Semantics(header: true, child: Text('What this means', style: text.headlineSmall)),
        const SizedBox(height: 12),
        for (final line in [
          'These are averages for people with answers like yours in a large US health survey.',
          'They are not a promise, and they are not a date.',
          'They show links, not causes. Changing one answer may not change what happens.',
          'We only look ${f.maxHorizonYears} years ahead, as far as the model was checked.',
          if (f.filledIn.isNotEmpty)
            'We have not asked about everything yet. For ${_join(f.filledIn)}, '
                'the forecast used typical answers from the survey.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('•  $line', style: body),
          ),
        const SizedBox(height: 24),
        if (speech != null) ...[
          BigButton(label: 'Say it again', filled: false, onTap: () => speech!.speak(forecastSentence(f)).ignore()),
          const SizedBox(height: 16),
        ],
        BigButton(label: 'Go back to my answers', filled: true, onTap: onBack),
        const SizedBox(height: 24),
        Text('Model ${f.modelVersion}', style: text.bodyMedium),
      ],
    );
  }

  static String _join(List<String> items) =>
      items.length == 1 ? items.single : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

class _MascotLine extends StatelessWidget {
  const _MascotLine(this.line);
  final String line;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(child: Icon(Icons.pets, size: 48)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(line, style: Theme.of(context).textTheme.headlineSmall?.copyWith(height: 1.35)),
          ),
        ],
      ),
    );
  }
}

/// A calm glowing ball. It brightens once during the reveal; no looping motion.
class _MagicBall extends StatelessWidget {
  const _MagicBall({required this.reveal, required this.dim});
  final Animation<double> reveal;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: reveal,
        builder: (context, _) {
          final t = Curves.easeOut.transform(reveal.value);
          final glow = dim ? 0.15 : 0.2 + 0.5 * t;
          return Transform.scale(
            scale: 0.9 + 0.1 * t,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  colors: [Colors.white, scheme.primaryContainer, scheme.primary],
                  stops: const [0.0, 0.45, 1.0],
                ),
                boxShadow: [
                  BoxShadow(color: scheme.primary.withValues(alpha: glow), blurRadius: 40, spreadRadius: 6),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 100 dots, [filled] of them solid. Rings for the rest, so it is not color alone.
class _DotGrid extends StatelessWidget {
  const _DotGrid({required this.filled});
  final int filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'About $filled of 100 dots are filled.',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            const gap = 6.0;
            final size = ((box.maxWidth - 9 * gap) / 10).clamp(4.0, 28.0);
            // Exactly ten across, so it always reads as 10 rows of 10.
            return Center(
              child: SizedBox(
                width: 10 * size + 9 * gap + 0.5,
                child: Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (var i = 0; i < 100; i++)
                      Container(
                        key: ValueKey('dot-$i-${i < filled ? 'filled' : 'empty'}'),
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < filled ? scheme.primary : null,
                          border: Border.all(color: i < filled ? scheme.primary : scheme.outline, width: 2),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
