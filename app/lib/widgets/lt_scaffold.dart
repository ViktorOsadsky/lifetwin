import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/lt_space.dart';
import '../theme/lt_theme.dart';
import 'lt_icon.dart';

/// Pushed-screen scaffold: iOS inline nav bar with a back button and title.
class LtPage extends StatelessWidget {
  const LtPage({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.background,
    this.sheetToBottom = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  /// Optional full-bleed layer behind the page (for example a Habitat).
  final Widget? background;

  /// Let the child run under the home indicator, for a sheet that should
  /// reach the bottom edge (the sheet pads its own content).
  final bool sheetToBottom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bgGround,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ?background,
          SafeArea(
            bottom: !sheetToBottom,
            child: Column(
              children: [
                SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: 'Back',
                        excludeSemantics: true,
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/room');
                          }
                        },
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/room');
                            }
                          },
                          child: SizedBox(
                            width: 56,
                            height: 52,
                            child: Center(
                              child: LtIcon(
                                LtIcons.chevronLeft,
                                color: c.actionPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: context.text.headline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: trailing ?? const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Titled placeholder used by routes another agent will fill in.
class LtStub extends StatelessWidget {
  const LtStub({super.key, required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LtSpace.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: context.text.title1,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LtSpace.s8),
            Text(
              note,
              style: context.text.subhead.copyWith(color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Large-title header for top-level tab screens.
class LtLargeTitle extends StatelessWidget {
  const LtLargeTitle({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LtSpace.gutter,
        LtSpace.s8,
        LtSpace.gutter,
        LtSpace.s12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: context.text.largeTitle),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
