import 'package:flutter/material.dart';

import 'health/health_screen.dart';

void main() => runApp(const LifeTwinApp());

/// Temporary host for the Apple Health import until Track C's game shell lands.
class LifeTwinApp extends StatelessWidget {
  const LifeTwinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LifeTwin',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2F5BD3), useMaterial3: true),
      home: Builder(
        builder: (context) => HealthImportScreen(
          onDone: (result) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Confirmed ${result.confirmed.length}, to ask ${result.toAsk.length}, '
                'samples ${result.samples.length}'),
          )),
        ),
      ),
    );
  }
}
