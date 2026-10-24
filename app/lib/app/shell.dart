import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/lt_space.dart';
import '../theme/lt_theme.dart';
import '../widgets/lt_icon.dart';

/// Tab shell: Room, Plan, Activity.
class LtShell extends StatelessWidget {
  const LtShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _tabs = [
    (LtIcons.room, 'Room'),
    (LtIcons.plan, 'Plan'),
    (LtIcons.activity, 'Activity'),
  ];

  void _go(int i) =>
      shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: c.bgGround,
      body: shell,
      bottomNavigationBar: Container(
        height: LtSpace.tabBar + bottom,
        padding: EdgeInsets.only(bottom: bottom),
        decoration: BoxDecoration(
          color: c.bgSheet,
          border: Border(top: BorderSide(color: c.line, width: 0.5)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: shell.currentIndex == i,
                  label: _tabs[i].$2,
                  excludeSemantics: true,
                  onTap: () => _go(i),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _go(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LtIcon(
                          _tabs[i].$1,
                          size: 24,
                          color: shell.currentIndex == i
                              ? c.actionPrimary
                              : c.textSecondary,
                        ),
                        const SizedBox(height: 2),
                        // Like iOS tab bars, labels grow only a little
                        // with Dynamic Type so the bar keeps its height.
                        MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.2,
                          child: Text(
                            _tabs[i].$2,
                            style: context.text.caption.copyWith(
                              color: shell.currentIndex == i
                                  ? c.actionPrimary
                                  : c.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
