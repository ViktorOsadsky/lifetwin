import 'package:flutter/material.dart';

import '../theme.dart';

/// Tracks the page routes so a screen can tell how deep it is (Room = 0). Register it as a
/// `MaterialApp.navigatorObservers` entry; without it no Home button is shown.
class HomeDepth extends NavigatorObserver {
  HomeDepth._();
  static final instance = HomeDepth._();

  final List<Route<dynamic>> _pages = [];

  /// How many pages sit under [route]; null when [route] is not a tracked page.
  static int? of(Route<dynamic>? route) {
    if (route == null) return null;
    final i = instance._pages.indexOf(route);
    return i < 0 ? null : i;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) return;
    if (previousRoute == null) _pages.clear();
    _pages.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _pages.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _pages.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _pages.indexOf(oldRoute);
    if (i < 0 || newRoute is! PageRoute) {
      _pages.remove(oldRoute);
      return;
    }
    _pages[i] = newRoute;
  }
}

/// One Home control for every deep screen: a house and "Home", back to the Room in one tap.
/// Shown only two or more levels below the Room (never on Home, never right under it, where Back
/// already lands). At 1.6x text or a very narrow screen the label drops; the 48pt target and the
/// "Go to Home" screen-reader name stay.
class HomeButton extends StatelessWidget {
  const HomeButton({super.key, this.onLeaveCheck});

  /// True when leaving now would cut a conversation or a save short; a quiet sheet asks first.
  final bool Function()? onLeaveCheck;

  /// Whether this route is deep enough to show Home.
  static bool shownFor(BuildContext context) {
    final depth = HomeDepth.of(ModalRoute.of(context));
    return depth != null && depth >= 2;
  }

  Future<void> _go(BuildContext context) async {
    final nav = Navigator.of(context);
    if (onLeaveCheck?.call() ?? false) {
      final leave = await showModalBottomSheet<bool>(
        context: context,
        builder: (c) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, child: Text('Leave this conversation?', style: LtText.display(24))),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.of(c).pop(false),
                  child: const Text('Keep going'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.of(c).pop(true),
                  child: const Text('Leave'),
                ),
              ],
            ),
          ),
        ),
      );
      if (leave != true) return;
    }
    nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    if (!shownFor(context)) return const SizedBox.shrink();
    final compact = MediaQuery.textScalerOf(context).scale(10) >= 15.5 || MediaQuery.sizeOf(context).width < 340;
    return Semantics(
      button: true,
      label: 'Go to Home',
      excludeSemantics: true,
      onTap: () => _go(context),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _go(context),
        child: Container(
          constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 14),
          decoration: BoxDecoration(
            color: LtColors.paper,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: LtColors.control, width: LtBorders.control),
            boxShadow: LtShadows.soft,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.home_rounded, size: 28, color: LtColors.ink),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text('Home', style: LtText.body(size: 17, weight: FontWeight.w700), maxLines: 1),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
