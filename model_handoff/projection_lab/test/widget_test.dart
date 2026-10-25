import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifetwin_projection_lab/main.dart';

void main() {
  testWidgets('local sample loads both model outputs', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProjectionApp());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    expect(find.text('NEURAL RELATIVE HAZARD'), findsOneWidget);
    expect(find.text('CURRENT 5-YEAR COX'), findsOneWidget);
    expect(find.text('Exploratory survival projection'), findsOneWidget);
    expect(find.text('Run models'), findsOneWidget);
  });
}
