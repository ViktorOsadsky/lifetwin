import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Text that wraps only between words, never inside one ("Contin/ue").
///
/// At the person's chosen text size it is a plain [Text]. Only when a single word is
/// wider than the room it has (very large accessibility sizes) is the whole text scaled
/// down, just enough for that word to fit on a line. Lines still wrap at spaces.
class WholeWordText extends StatelessWidget {
  const WholeWordText(
    String this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.semanticsLabel,
    this.maxLines,
    this.softWrap,
  }) : textSpan = null;

  const WholeWordText.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.textAlign,
    this.semanticsLabel,
    this.maxLines,
    this.softWrap,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final TextAlign? textAlign;
  final String? semanticsLabel;

  /// For one-line labels (with [softWrap] false, inside a scale-down FittedBox).
  final int? maxLines;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    var base = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) base = base.merge(const TextStyle(fontWeight: FontWeight.bold));
    final direction = Directionality.of(context);
    final span = textSpan ?? TextSpan(text: data);
    final align = textAlign ?? DefaultTextStyle.of(context).textAlign ?? TextAlign.start;
    TextScaler fitTo(double maxWidth) {
      final factor = wordFitFactor(span, base, scaler, maxWidth, direction);
      return factor < 1 ? ShrunkTextScaler(scaler, factor) : scaler;
    }

    // LayoutBuilder cannot answer intrinsic-size questions (SliverFillRemaining, IntrinsicHeight
    // ask them), so _TextIntrinsics answers them by measuring the same text at the same fit.
    return _TextIntrinsics(
      measure: (maxWidth) => TextPainter(
        text: TextSpan(style: base, children: [span]),
        textAlign: align,
        textDirection: direction,
        textScaler: maxWidth.isFinite ? fitTo(maxWidth) : scaler,
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth),
      child: LayoutBuilder(
        builder: (context, box) {
          final fitted = fitTo(box.maxWidth);
          final shrunk = identical(fitted, scaler) ? null : fitted;
          final data = this.data;
          return data != null
              ? Text(
                  data,
                  style: style,
                  textAlign: textAlign,
                  semanticsLabel: semanticsLabel,
                  textScaler: shrunk,
                  maxLines: maxLines,
                  softWrap: softWrap,
                )
              : Text.rich(
                  textSpan!,
                  style: style,
                  textAlign: textAlign,
                  semanticsLabel: semanticsLabel,
                  textScaler: shrunk,
                  maxLines: maxLines,
                  softWrap: softWrap,
                );
        },
      ),
    );
  }
}

/// Lays out its child as usual; answers intrinsic and dry-layout questions from [measure].
class _TextIntrinsics extends SingleChildRenderObjectWidget {
  const _TextIntrinsics({required this.measure, required super.child});

  /// The text laid out within a maximum width (infinite for its natural widths).
  final TextPainter Function(double maxWidth) measure;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTextIntrinsics(measure);

  @override
  void updateRenderObject(BuildContext context, _RenderTextIntrinsics renderObject) => renderObject.measure = measure;
}

class _RenderTextIntrinsics extends RenderProxyBox {
  _RenderTextIntrinsics(this._measure);

  TextPainter Function(double) _measure;
  set measure(TextPainter Function(double) value) {
    _measure = value;
    markNeedsLayout(); // also drops cached intrinsic sizes
  }

  T _with<T>(double maxWidth, T Function(TextPainter p) read) {
    final p = _measure(maxWidth);
    final v = read(p);
    p.dispose();
    return v;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _with(double.infinity, (p) => p.minIntrinsicWidth);

  @override
  double computeMaxIntrinsicWidth(double height) => _with(double.infinity, (p) => p.maxIntrinsicWidth);

  @override
  double computeMinIntrinsicHeight(double width) => _with(width, (p) => p.height);

  @override
  double computeMaxIntrinsicHeight(double width) => _with(width, (p) => p.height);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_with(constraints.maxWidth, (p) => p.size));

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) =>
      _with(constraints.maxWidth, (p) => p.computeDistanceToActualBaseline(baseline));
}

/// [base] made smaller by [factor] (0 < factor <= 1).
class ShrunkTextScaler extends TextScaler {
  const ShrunkTextScaler(this.base, this.factor);
  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor => scale(1);

  @override
  bool operator ==(Object other) => other is ShrunkTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// How much [span] must shrink (1 = not at all) so that its widest word fits in
/// [maxWidth] at [scaler]. Words are what lies between whitespace.
double wordFitFactor(InlineSpan span, TextStyle style, TextScaler scaler, double maxWidth, TextDirection direction) {
  if (!maxWidth.isFinite || maxWidth <= 0) return 1;
  // A small margin: a word exactly as wide as the line can still be pushed over by rounding.
  final room = maxWidth - 0.5;
  double widest(TextScaler s) => _widestWord(span, style, s, direction);
  // Cheap check first: the whole text on one line fits, so every word does.
  if (_width(span, style, scaler, direction) <= room) return 1;
  final w = widest(scaler);
  if (w <= room) return 1;
  var factor = room / w;
  // Glyph widths do not shrink exactly in proportion (hinting, rounding): check and nudge.
  for (var i = 0; i < 10 && widest(ShrunkTextScaler(scaler, factor)) > room; i++) {
    factor *= 0.98;
  }
  return factor;
}

double _width(InlineSpan span, TextStyle style, TextScaler scaler, TextDirection direction) {
  final p = TextPainter(
    text: TextSpan(style: style, children: [span]),
    textDirection: direction,
    textScaler: scaler,
  )..layout();
  final w = p.maxIntrinsicWidth;
  p.dispose();
  return w;
}

/// The width of the widest run of non-space text. A word that crosses from one span into
/// the next (a bold number inside a sentence) is measured as the sum of its pieces.
double _widestWord(InlineSpan span, TextStyle style, TextScaler scaler, TextDirection direction) {
  var widest = 0.0;
  var current = 0.0;
  void endWord() {
    if (current > widest) widest = current;
    current = 0;
  }

  void visit(InlineSpan s, TextStyle inherited) {
    final st = inherited.merge(s.style);
    if (s is! TextSpan) {
      endWord(); // a widget in the text: a break either side
      return;
    }
    final text = s.text;
    if (text != null && text.isNotEmpty) {
      final parts = text.split(_space);
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) endWord();
        if (parts[i].isNotEmpty) current += _width(TextSpan(text: parts[i]), st, scaler, direction);
      }
    }
    for (final child in s.children ?? const <InlineSpan>[]) {
      visit(child, st);
    }
  }

  visit(span, style);
  endWord();
  return widest;
}

final _space = RegExp(r'\s+');
