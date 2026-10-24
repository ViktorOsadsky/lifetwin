import 'package:flutter/material.dart';

import '../theme/lt_space.dart';
import '../theme/lt_theme.dart';
import 'lt_icon.dart';

/// Light lists (§7b.4–5): plain rows on the page or sheet, 0.5 pt `line`
/// hairlines inset to the text edge, a quiet Caption header, and no
/// container, border or shadow around a group or a row.

/// Width of the leading icon slot; hairlines start after it.
const double _iconSlot = 44;
const double _iconGap = 14;

/// Small quiet header above a group of rows.
class LtSectionHeader extends StatelessWidget {
  const LtSectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LtSpace.gutter,
        LtSpace.s24,
        LtSpace.gutter,
        LtSpace.s4,
      ),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Expanded(child: Text(title, style: context.text.caption)),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A 28 pt illustrated icon on a faint tinted circle.
class LtRowIcon extends StatelessWidget {
  const LtRowIcon(this.icon, {super.key, this.color, this.muted = false});

  final LtIcons icon;
  final Color? color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: _iconSlot,
      height: _iconSlot,
      decoration: BoxDecoration(
        color: muted ? c.calmSurface : c.iconBackdrop,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: LtIcon(
          icon,
          size: 26,
          color: muted ? c.textSecondary : (color ?? c.actionPrimary),
        ),
      ),
    );
  }
}

/// Rows separated by inset hairlines. No box around the group.
class LtRowGroup extends StatelessWidget {
  const LtRowGroup({
    super.key,
    required this.children,
    this.leadingIcon = true,
  });

  final List<Widget> children;

  /// Whether rows have a leading icon (moves the hairline inset).
  final bool leadingIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inset = LtSpace.gutter + (leadingIcon ? _iconSlot + _iconGap : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.only(left: inset),
              child: Container(height: 0.5, color: c.line),
            ),
          children[i],
        ],
      ],
    );
  }
}

/// One list row, 56–72 pt: leading icon, Headline title, one quiet Subhead
/// line, and a trailing value or chevron. Tapping anywhere on the row runs
/// [onTap]; the press tint fills the row edge to edge, no card.
class LtRow extends StatefulWidget {
  const LtRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.semanticsLabel,
    this.chevron,
    this.dimmed = false,
    this.below,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  /// Defaults to showing a chevron when the row is tappable and has no
  /// trailing widget.
  final bool? chevron;

  /// Quieter title, for skipped or inactive items.
  final bool dimmed;

  /// Optional extra line(s) under the subtitle (e.g. a delta).
  final Widget? below;

  @override
  State<LtRow> createState() => _LtRowState();
}

class _LtRowState extends State<LtRow> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tappable = widget.onTap != null;
    final showChevron = widget.chevron ?? (tappable && widget.trailing == null);
    final content = Row(
      children: [
        if (widget.leading != null) ...[
          widget.leading!,
          const SizedBox(width: _iconGap),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: context.text.headline.copyWith(
                  color: widget.dimmed ? c.textSecondary : c.textPrimary,
                ),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: context.text.subhead.copyWith(color: c.textSecondary),
                ),
              ],
              if (widget.below != null) ...[
                const SizedBox(height: LtSpace.s4),
                widget.below!,
              ],
            ],
          ),
        ),
        if (showChevron) ...[
          const SizedBox(width: LtSpace.s8),
          LtIcon(LtIcons.chevronRight, color: c.vizBaseline, size: 18),
        ],
      ],
    );
    final label =
        widget.semanticsLabel ?? [widget.title, ?widget.subtitle].join('. ');
    // The row's own action covers the content; an interactive trailing
    // widget (a small text button) keeps its own semantics and hit region.
    final main = tappable
        ? Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            onTap: widget.onTap,
            child: content,
          )
        : Semantics(
            container: true,
            label: widget.semanticsLabel,
            excludeSemantics: widget.semanticsLabel != null,
            child: content,
          );
    final scaler = MediaQuery.textScalerOf(context);
    final row = AnimatedContainer(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 90),
      color: _pressed ? c.chipSelected.withValues(alpha: 0.55) : c.clear,
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(
        horizontal: LtSpace.gutter,
        vertical: LtSpace.s12,
      ),
      // At large text on narrow phones a trailing action moves under the
      // text instead of squeezing the title into a narrow column.
      child: LayoutBuilder(
        builder: (context, box) {
          final roomy =
              widget.trailing == null ||
              box.maxWidth - (_iconSlot + _iconGap) >= scaler.scale(200);
          if (roomy) {
            return Row(
              children: [
                Expanded(child: main),
                if (widget.trailing != null) ...[
                  const SizedBox(width: LtSpace.s12),
                  widget.trailing!,
                ],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              main,
              Padding(
                padding: EdgeInsets.only(
                  left: widget.leading == null ? 0 : _iconSlot + _iconGap,
                ),
                child: widget.trailing,
              ),
            ],
          );
        },
      ),
    );
    if (!tappable) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: row,
    );
  }
}

/// Secondary action as plain blue text in a stationary 44 pt hit region.
class LtTextButton extends StatefulWidget {
  const LtTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.center = false,
    this.quiet = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final LtIcons? icon;
  final bool center;

  /// `ink-2` Subhead, for small per-row actions that should not compete
  /// with the screen's next useful action.
  final bool quiet;

  @override
  State<LtTextButton> createState() => _LtTextButtonState();
}

class _LtTextButtonState extends State<LtTextButton> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null;
    final fg = !enabled
        ? c.vizBaseline
        : widget.quiet
        ? (_pressed ? c.textPrimary : c.textSecondary)
        : _pressed
        ? c.actionPrimaryPressed
        : c.actionPrimary;
    final style = widget.quiet
        ? context.text.subhead.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
            fontVariations: const [FontVariation('wght', 600)],
          )
        : context.text.headline.copyWith(color: fg);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: () => _set(false),
        onTap: widget.onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: LtSpace.touch,
            minWidth: LtSpace.touch,
          ),
          child: Row(
            mainAxisSize: widget.center ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                LtIcon(widget.icon!, color: fg, size: 18),
                const SizedBox(width: LtSpace.s4 + 2),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one sheet a screen's content rises on (§7b.3): top radius 28, sheet
/// shadow, a decorative grabber and a surface tinted from the page ground.
class LtSheetPanel extends StatelessWidget {
  const LtSheetPanel({super.key, required this.child, this.grabber = true});

  final Widget child;
  final bool grabber;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.bgSheet,
        borderRadius: LtRadius.sheetTop,
        boxShadow: c.sheetShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (grabber)
            ExcludeSemantics(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.only(top: LtSpace.s8),
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.line,
                    borderRadius: LtRadius.chipAll,
                  ),
                ),
              ),
            ),
          // Pads above the home indicator when the sheet reaches the bottom
          // edge; a no-op when an ancestor already applied the inset.
          Flexible(
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
