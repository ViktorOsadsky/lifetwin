import 'package:flutter/material.dart';

import '../../widgets/lt_scaffold.dart';
import '../activity/record_measurements_sheet.dart';

/// Full-page host for the F15 content; the same content opens as a sheet from
/// the Activity tab.
class RecordMeasurementsScreen extends StatelessWidget {
  const RecordMeasurementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LtPage(
      title: 'Record real measurements',
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: RecordMeasurementsContent(),
      ),
    );
  }
}
