import 'package:flutter/material.dart';

import '../theme/lifetwin_theme.dart';
import '../voice/speech.dart';
import '../widgets/lt_buttons.dart';
import '../widgets/lt_icons.dart';
import '../widgets/magic_ball_badge.dart';
import '../widgets/pip.dart';
import '../widgets/scene_paper.dart';
import '../widgets/speech_bubble.dart';
import 'forecast_client.dart';

/// The mascot's sentence for a supported forecast. Spoken and shown, word for word.
String forecastSentence(Forecast f) {
  final years = f.maxHorizonYears;
  return 'Out of 100 people with answers like yours, about ${f.outOf100(years)} '
      'were still living $years ${_years(years)} later.';
}

String unsupportedSentence(Forecast f) =>
    "I can't make a forecast for you yet. ${f.reason ?? 'The model does not cover these answers.'}";

const couldNotReach = "I couldn't get your forecast just now.";

String _years(int y) => y == 1 ? 'year' : 'years';

/// Magic-ball forecast (Fortune.dc.html): awaiting model, a short reveal, then the
/// result. Never shows a date, a countdown or a "life expectancy". Every number comes
/// from the server's answer.
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
      backgroundColor: LtColors.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: LtSpace.md, bottom: 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Pad(
                Row(
                  children: [
                    Expanded(
                      child: Align(alignment: Alignment.centerLeft, child: LtBackButton(onPressed: _back)),
                    ),
                    const SizedBox(width: LtSpace.md),
                    _MagicBall(reveal: _reveal, dim: f != null && !f.supported),
                  ],
                ),
              ),
              const SizedBox(height: LtSpace.sm),
              _Pad(Semantics(header: true, child: Text('Your forecast', style: LtText.title))),
              if (_loading)
                const _PipSays('Looking into the magic ball…')
              else if (_error != null)
                ..._failed()
              else if (!f!.supported)
                ..._unsupported(f)
              else
                FadeTransition(
                  opacity: _reveal,
                  child: _Result(forecast: f, onBack: _back, speech: widget.speech),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _failed() => [
    const _PipSays(couldNotReach),
    _Pad(Text(_error?.plain ?? 'Please check the connection and try again.', style: LtText.body)),
    const SizedBox(height: LtSpace.xxl),
    _Pad(LtPrimaryButton(label: 'Try again', onPressed: _retry)),
    const SizedBox(height: LtSpace.buttonGap),
    _Pad(LtSecondaryButton(label: 'Go back', onPressed: _back)),
  ];

  List<Widget> _unsupported(Forecast f) => [
    _PipSays(unsupportedSentence(f)),
    const SizedBox(height: LtSpace.md),
    _Pad(LtPrimaryButton(label: 'Go back to my answers', onPressed: _back)),
  ];
}

/// The screen's side gutter. Scenes are drawn edge to edge, so padding is per row.
class _Pad extends StatelessWidget {
  const _Pad(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: LtSpace.gutter), child: child);
}

class _Result extends StatefulWidget {
  const _Result({required this.forecast, required this.onBack, this.speech});

  final Forecast forecast;
  final VoidCallback onBack;
  final SpeechOutput? speech;

  @override
  State<_Result> createState() => _ResultState();
}

class _ResultState extends State<_Result> {
  /// The time span the dots show. Starts at the longest one the model was checked for.
  late int _span = widget.forecast.maxHorizonYears;

  @override
  Widget build(BuildContext context) {
    final f = widget.forecast;
    final spans = f.survival.keys.toList()..sort();
    final living = f.outOf100(_span);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: LtSpace.md),
        _Pad(_Sentence(f)),
        const SizedBox(height: LtSpace.lg),
        _Pad(Text('Still living, out of 100', style: LtText.caption)),
        const SizedBox(height: LtSpace.sm),
        _Pad(
          _SpanTiles(
            forecast: f,
            spans: spans,
            selected: _span,
            onSelect: (y) => setState(() => _span = y),
          ),
        ),
        const SizedBox(height: 20),
        _DotGrid(filled: living),
        const SizedBox(height: LtSpace.md),
        _Pad(_Legend(living: living)),
        const SizedBox(height: LtSpace.md),
        _Pad(
          Text(
            'Each dot is one person. A filled dot is someone still living '
            'after $_span ${_years(_span)}.',
            textAlign: TextAlign.center,
            style: LtText.bodySmall,
          ),
        ),
        const SizedBox(height: 28),
        _Pad(_WhatThisMeans(forecast: f)),
        const SizedBox(height: 28),
        if (widget.speech != null) ...[
          _Pad(
            LtSecondaryButton(
              label: 'Say it again',
              onPressed: () => widget.speech!.speak(forecastSentence(f)).ignore(),
            ),
          ),
          const SizedBox(height: LtSpace.buttonGap),
        ],
        _Pad(LtPrimaryButton(label: 'Go back to my answers', onPressed: widget.onBack)),
        const SizedBox(height: LtSpace.xl),
        _Pad(Text('Model ${f.modelVersion}', style: LtText.caption)),
      ],
    );
  }
}

/// The spoken sentence, with "about N" in bold as on the artboard.
class _Sentence extends StatelessWidget {
  const _Sentence(this.forecast);
  final Forecast forecast;

  @override
  Widget build(BuildContext context) {
    final line = forecastSentence(forecast);
    final strong = 'about ${forecast.outOf100(forecast.maxHorizonYears)}';
    final at = line.indexOf(strong);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: line.substring(0, at)),
            TextSpan(text: strong, style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: line.substring(at + strong.length)),
          ],
        ),
        style: LtText.body,
      ),
    );
  }
}

/// One tile per time span the server returned (98 · 1 year, …). Side by side, or
/// stacked when text is enlarged so numbers never squeeze.
class _SpanTiles extends StatelessWidget {
  const _SpanTiles({required this.forecast, required this.spans, required this.selected, required this.onSelect});

  final Forecast forecast;
  final List<int> spans;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final tiles = [
      for (final y in spans)
        LtChoiceTile(
          key: ValueKey('span-$y'),
          selected: y == selected,
          semanticLabel: 'About ${forecast.outOf100(y)} in 100 still living after $y ${_years(y)}',
          onPressed: () => onSelect(y),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${forecast.outOf100(y)}', style: LtText.stat),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (y == selected) ...[
                    const LtIcon(LtIconKind.check, size: 18, strokeWidth: 3.4),
                    const SizedBox(width: 4),
                  ],
                  Flexible(child: Text('$y ${_years(y)}', style: LtText.caption)),
                ],
              ),
            ],
          ),
        ),
    ];
    return Semantics(
      container: true,
      label: 'Choose a time span',
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final t in tiles) Padding(padding: const EdgeInsets.only(bottom: LtSpace.md), child: t),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: LtSpace.md),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
    );
  }
}

/// A calm magic ball beside Pip. It brightens once during the reveal; no looping motion.
class _MagicBall extends StatelessWidget {
  const _MagicBall({required this.reveal, required this.dim});
  final Animation<double> reveal;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: reveal,
      builder: (context, child) {
        final t = Curves.easeOut.transform(reveal.value);
        return Opacity(
          opacity: dim ? 0.55 : 1,
          child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
        );
      },
      child: const MagicBallBadge(),
    );
  }
}

/// Pip's line in a bubble, with Pip below on the paper scene.
class _PipSays extends StatelessWidget {
  const _PipSays(this.line);
  final String line;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: LtSpace.xl),
        _Pad(
          SpeechBubble(
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Text(line, style: LtText.bubble),
            ),
          ),
        ),
        const ScenePaper(
          height: 132,
          child: Positioned(left: 62, bottom: 6, child: Pip(mood: PipMood.asking, height: 104)),
        ),
      ],
    );
  }
}

const _filledDot = BoxDecoration(
  shape: BoxShape.circle,
  color: LtColors.mintDeep,
  border: Border.fromBorderSide(BorderSide(color: LtColors.ink, width: 2.5)),
);
const _emptyDot = BoxDecoration(
  shape: BoxShape.circle,
  color: LtColors.white,
  border: Border.fromBorderSide(BorderSide(color: LtColors.inkMuted, width: 2)),
);
const _dot = 17.0, _dotGap = 6.0;

/// 100 dots, [filled] of them solid mint. Empty rings for the rest, so it is not color alone.
class _DotGrid extends StatelessWidget {
  const _DotGrid({required this.filled});
  final int filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'About $filled of 100 dots are filled.',
      child: ExcludeSemantics(
        child: Center(
          // Exactly ten across, so it always reads as 10 rows of 10.
          child: SizedBox(
            width: 10 * _dot + 9 * _dotGap + 0.5,
            child: Wrap(
              spacing: _dotGap,
              runSpacing: _dotGap,
              children: [
                for (var i = 0; i < 100; i++)
                  Container(
                    key: ValueKey('dot-$i-${i < filled ? 'filled' : 'empty'}'),
                    width: _dot,
                    height: _dot,
                    decoration: i < filled ? _filledDot : _emptyDot,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.living});
  final int living;

  @override
  Widget build(BuildContext context) {
    Widget item(BoxDecoration d, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: _dot, height: _dot, decoration: d),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: LtText.caption)),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 24,
      runSpacing: 8,
      children: [item(_filledDot, '$living still living'), item(_emptyDot, '${100 - living} were not')],
    );
  }
}

/// The honest small print, always on screen (the artboard's "What this means").
class _WhatThisMeans extends StatelessWidget {
  const _WhatThisMeans({required this.forecast});
  final Forecast forecast;

  @override
  Widget build(BuildContext context) {
    final f = forecast;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      decoration: const BoxDecoration(
        color: LtColors.white,
        borderRadius: LtRadii.card,
        border: Border.fromBorderSide(LtOutline.side),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LtIcon(LtIconKind.info, size: 32, strokeWidth: 2.3),
              const SizedBox(width: LtSpace.md),
              Expanded(
                child: Semantics(header: true, child: Text('What this means', style: LtText.sectionTitle)),
              ),
            ],
          ),
          const SizedBox(height: LtSpace.md),
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
              padding: const EdgeInsets.only(bottom: LtSpace.md),
              child: Text('•  $line', style: LtText.bodySmall),
            ),
        ],
      ),
    );
  }

  static String _join(List<String> items) =>
      items.length == 1 ? items.single : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}
