import 'package:flutter/material.dart';

import '../theme/lt_space.dart';
import '../theme/lt_theme.dart';
import 'lt_icon.dart';

/// Opens a bottom sheet with the LifeTwin shape and shadow.
Future<T?> showLtSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final c = context.colors;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.bgSurface,
    barrierColor: c.textPrimary.withValues(alpha: 0.32),
    elevation: 0,
    shape: const RoundedRectangleBorder(borderRadius: LtRadius.sheetTop),
    clipBehavior: Clip.antiAlias,
    builder: builder,
  );
}

/// Sheet content: grabber, title, close button, scrollable body.
class LtSheetScaffold extends StatelessWidget {
  const LtSheetScaffold({
    super.key,
    required this.title,
    required this.child,
    this.footer,
    this.onClose,
  });

  final String title;
  final Widget child;

  /// Pinned below the scrolling body (typically the primary action).
  final Widget? footer;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: LtRadius.sheetTop,
        boxShadow: c.sheetShadow,
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
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
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  LtSpace.gutter,
                  LtSpace.s8,
                  LtSpace.s8,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(title, style: context.text.title2),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Close',
                      excludeSemantics: true,
                      onTap: onClose ?? () => Navigator.of(context).maybePop(),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap:
                            onClose ?? () => Navigator.of(context).maybePop(),
                        child: SizedBox(
                          width: LtSpace.touch,
                          height: LtSpace.touch,
                          child: Center(
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: c.bgGround,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: LtIcon(
                                  LtIcons.close,
                                  color: c.textSecondary,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    LtSpace.gutter,
                    LtSpace.s8,
                    LtSpace.gutter,
                    LtSpace.s16,
                  ),
                  child: child,
                ),
              ),
              if (footer != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    LtSpace.gutter,
                    0,
                    LtSpace.gutter,
                    LtSpace.s16,
                  ),
                  child: footer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
