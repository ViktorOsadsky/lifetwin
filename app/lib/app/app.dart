import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/lt_theme.dart';
import 'router.dart';

class LifeTwinApp extends StatefulWidget {
  const LifeTwinApp({super.key, this.router});

  final GoRouter? router;

  @override
  State<LifeTwinApp> createState() => _LifeTwinAppState();
}

class _LifeTwinAppState extends State<LifeTwinApp> {
  late final GoRouter _router = widget.router ?? buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LifeTwin',
      debugShowCheckedModeBanner: false,
      theme: buildLtTheme(),
      routerConfig: _router,
    );
  }
}
