import 'package:flutter/material.dart';

import '../ui/theme.dart';
import '../ui/twin_appearance.dart';
import '../ui/twin_assets.dart';
import '../ui/widgets/widgets.dart';
import '../voice/speech.dart';
import '../widgets/whole_word_text.dart';
import 'forecast_client.dart';
import 'night_plate.dart';
import 'outlook_detail_screen.dart';

/// The mascot's sentence for a supported forecast. Spoken and shown, word for word.
String forecastSentence(Forecast f) {
  final years = f.maxHorizonYears;
  return 'Out of 100 people with answers like yours, about ${f.outOf100(years)} '
      'were still living $years ${years == 1 ? 'year' : 'years'} later.';
}

String unsupportedSentence(Forecast f) =>
    "I can't make a forecast for you yet. ${f.reason ?? 'The model does not cover these answers.'}";

const couldNotReach = "I couldn't get your forecast just now.";
const stillLearningLine = "The ball isn't ready yet.";

/// The plain "what this means" lines, shown under Why? (and kept word for
/// word from the first forecast screen).
List<String> forecastMeaning(Forecast f) => [
  'These are averages for people with answers like yours in a large US health survey.',
  'They are not a promise, and they are not a date.',
  'They show links, not causes. Changing one answer may not change what happens.',
  'We only look ${f.maxHorizonYears} years ahead, as far as the model was checked.',
  if (f.filledIn.isNotEmpty)
    'We have not asked about everything yet. For ${_join(f.filledIn)}, '
        'the forecast used typical answers from the survey.',
];

String _join(List<String> items) =>
    items.length == 1 ? items.single : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

/// V-4 fortune result, with V-5 still learning and the unsupported state.
/// Shows only real response fields: never an age, a date, a countdown or a
/// "life expectancy".
class ForecastScreen extends StatefulWidget {
  const ForecastScreen({
    super.key,
    required this.client,
    required this.profile,
    required this.onBack,
    this.speech,
    this.onAnswers,
    this.onPlayQuiz,
    this.healthKeys = const {},
    this.appearance = const TwinAppearance(),
  });

  final ForecastClient client;

  /// The confirmed answers. Sent as they are; nothing is guessed here.
  final Map<String, dynamic> profile;
  final VoidCallback onBack;

  /// Set when voice is on; the mascot then says its sentence aloud.
  final SpeechOutput? speech;

  /// "Go back to my answers": back to the conversation, where an answer can be changed or
  /// a skipped one added. Falls back to [onBack] when not given.
  final VoidCallback? onAnswers;

  /// Shown on "still learning" when a quiz exists.
  final VoidCallback? onPlayQuiz;

  /// Profile keys that came from the Health app (the rest: "you told me").
  final Set<String> healthKeys;

  /// Cosmetic look of the twin on the night plate.
  final TwinAppearance appearance;

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
      await _say(e.modelMissing ? 'Still learning. $stillLearningLine' : couldNotReach);
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

  void _answers() {
    if (_spoke) widget.speech?.stop();
    (widget.onAnswers ?? widget.onBack)();
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
    final supported = f != null && f.supported;
    final String? bubble = _loading
        ? 'Looking into the magic ball…'
        : _error != null
        ? (_error!.modelMissing ? stillLearningLine : couldNotReach)
        : !supported
        ? unsupportedSentence(f!)
        : null;
    // Holding the ball while it looks and when it answers; a shrug otherwise.
    final pose = (_loading || supported) ? TwinPose.holdBall : TwinPose.shrug;
    return ModeScaffold(
      mode: LtMode.fortune,
      child: PlateSheetLayout(
        minWindow: 160,
        window: PlateWindow(
          night: true,
          name: widget.appearance.name,
          plate: NightTwinPlate(
            appearance: widget.appearance,
            pose: pose,
            glow: pose == TwinPose.holdBall ? 0.8 : 0,
            // Feet clear of the sheet, which overlaps the window's bottom edge.
            feetAt: Offset(bubble == null ? 0.5 : 0.3, bubble == null ? 0.8 : 0.86),
            twinHeight: bubble == null ? 0.74 : 0.5,
          ),
          overlay: Stack(
            children: [
              Positioned(
                left: 14,
                top: 18,
                child: RoundBackButton(label: 'Back', onTap: _back),
              ),
              if (bubble != null)
                Positioned(
                  top: 36,
                  right: 10,
                  left: 84,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Bubble(text: bubble, liveRegion: true, fontSize: 21, maxHeight: 220),
                  ),
                ),
            ],
          ),
        ),
        sheet: Sheet(night: true, padding: const EdgeInsets.fromLTRB(22, 18, 22, 18), child: _sheet(context)),
      ),
    );
  }

  Widget _sheet(BuildContext context) {
    final f = _forecast;
    if (_loading) {
      return WholeWordText('One moment…', style: LtText.body(size: 18, color: LtColors.cream));
    }
    final e = _error;
    if (e != null && e.modelMissing) return _stillLearning();
    if (e != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WholeWordText(
            e.plain ?? 'Please check the connection and try again.',
            style: LtText.body(size: 18, color: LtColors.cream),
          ),
          const SizedBox(height: 16),
          LipButton(label: 'Try again', icon: Icons.refresh_rounded, onTap: _retry),
          const SizedBox(height: 12),
          LipButton(label: 'Go back', kind: LipKind.secondary, height: 56, fontSize: 21, onTap: _back),
        ],
      );
    }
    if (!f!.supported) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The plain reason is in the bubble; nothing is added to it here.
          LipButton(label: 'Go back to my answers', icon: Icons.edit_rounded, onTap: _answers),
          if (widget.onAnswers != null) ...[
            const SizedBox(height: 12),
            LipButton(label: 'Go back', kind: LipKind.secondary, height: 56, fontSize: 21, onTap: _back),
          ],
        ],
      );
    }
    return FadeTransition(opacity: _reveal, child: _result(context, f));
  }

  Widget _stillLearning() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: WholeWordText('Still learning', style: LtText.display(34, color: LtColors.gold)),
      ),
      const SizedBox(height: 6),
      WholeWordText('Your fortune will show here later.', style: LtText.body(color: LtColors.cream)),
      const SizedBox(height: 16),
      if (widget.onPlayQuiz != null) ...[
        LipButton(label: 'Play the quiz', icon: Icons.extension_rounded, onTap: widget.onPlayQuiz),
        const SizedBox(height: 12),
      ],
      LipButton(
        label: 'Back to room',
        icon: Icons.home_rounded,
        kind: widget.onPlayQuiz != null ? LipKind.secondary : LipKind.primary,
        height: widget.onPlayQuiz != null ? 56 : 64,
        fontSize: 21,
        onTap: _back,
      ),
    ],
  );

  Widget _result(BuildContext context, Forecast f) {
    final years = f.maxHorizonYears;
    final n = f.outOf100(years);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: WholeWordText('Your look ahead', style: LtText.display(22, color: LtColors.gold)),
        ),
        const SizedBox(height: 8),
        WholeWordText.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'About ',
                style: LtText.display(40, color: LtColors.cream, weight: FontWeight.w500),
              ),
              TextSpan(
                text: '$n in 100',
                style: LtText.display(40, color: LtColors.cream),
              ),
            ],
          ),
        ),
        WholeWordText(
          'chance you’re still here in $years ${years == 1 ? 'year' : 'years'}',
          style: LtText.body(color: LtColors.cream),
        ),
        const SizedBox(height: 12),
        BearHeadArray(filled: n),
        const SizedBox(height: 8),
        WholeWordText(
          forecastSentence(f),
          textAlign: TextAlign.center,
          style: LtText.body(color: LtColors.gold),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            WholeWordText(
              'Linked, not proven.',
              style: LtText.body(color: LtColors.cream, weight: FontWeight.w700),
            ),
            LinkButton(label: 'Why?', icon: Icons.help_outline_rounded, color: LtColors.gold, onTap: () => _why(f)),
          ],
        ),
        if (widget.speech != null)
          Align(
            alignment: Alignment.centerLeft,
            child: LinkButton(
              label: 'Say it again',
              icon: Icons.volume_up_rounded,
              color: LtColors.gold,
              onTap: () => widget.speech!.speak(forecastSentence(f)).ignore(),
            ),
          ),
        const SizedBox(height: 4),
        LipButton(
          label: 'See what shaped it',
          icon: Icons.show_chart_rounded,
          height: 58,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OutlookDetailScreen(
                forecast: f,
                profile: widget.profile,
                healthKeys: widget.healthKeys,
                onAddAnswer: () {
                  Navigator.of(context).pop();
                  _answers();
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: LinkButton(
            label: 'Go back to my answers',
            icon: Icons.edit_rounded,
            color: LtColors.gold,
            onTap: _answers,
          ),
        ),
      ],
    );
  }

  void _why(Forecast f) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LtColors.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(LtRadii.panel))),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, child: WholeWordText('What this means', style: LtText.display(26))),
                const SizedBox(height: 12),
                for (final line in [...forecastMeaning(f), ...f.limitations])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: WholeWordText('•  $line', style: LtText.body(size: 18)),
                  ),
                const SizedBox(height: 8),
                LipButton(
                  label: 'Got it',
                  kind: LipKind.secondary,
                  height: 56,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
