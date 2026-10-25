import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lifetwin_on_device/lifetwin_on_device.dart';

void main() => runApp(const ProjectionApp());

const ink = Color(0xFF172B37);
const teal = Color(0xFF078F83);
const violet = Color(0xFF8253C8);
const paper = Color(0xFFF4F7F4);

class ProjectionApp extends StatelessWidget {
  const ProjectionApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LifeTwin Projection Lab',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: teal),
      scaffoldBackgroundColor: paper,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
    ),
    home: const ProjectionHome(),
  );
}

class ProjectionHome extends StatefulWidget {
  const ProjectionHome({super.key});

  @override
  State<ProjectionHome> createState() => _ProjectionHomeState();
}

class _ProjectionHomeState extends State<ProjectionHome> {
  final controllers = <String, TextEditingController>{
    'age': TextEditingController(text: '65'),
    'bmi': TextEditingController(text: '27'),
    'sleep_hours': TextEditingController(text: '7'),
    'vigorous_recreation_min_week': TextEditingController(text: '0'),
    'moderate_recreation_min_week': TextEditingController(text: '150'),
    'sedentary_min_day': TextEditingController(text: '360'),
  };
  final categories = <String, int>{
    'sex_nhanes': 1,
    'smoking_status': 0,
    'diabetes_diagnosed': 0,
    'hypertension_diagnosed': 0,
    'general_health': 3,
  };
  LifeTwinProjectionLab? lab;
  Map<String, dynamic>? result;
  String? error;
  bool includeExtrapolation = true;

  @override
  void initState() {
    super.initState();
    loadLifeTwinProjectionLab()
        .then((value) {
          if (!mounted) return;
          setState(() => lab = value);
          runModels();
        })
        .catchError((Object exception) {
          if (mounted) {
            setState(
              () => error = 'Could not load local model assets: $exception',
            );
          }
        });
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void runModels() {
    if (lab == null) return;
    try {
      final profile = <String, dynamic>{...categories};
      for (final entry in controllers.entries) {
        final value = double.parse(entry.value.text.trim());
        profile[entry.key] = entry.key == 'age' ? value.toInt() : value;
        if (entry.key == 'age' && value != value.toInt()) {
          throw const FormatException('Age must be in completed years');
        }
      }
      final next = lab!.assess(
        profile,
        includeExtrapolation: includeExtrapolation,
      );
      setState(() {
        result = next;
        error = next['status'] == 'available'
            ? null
            : '${next['message'] ?? 'Unsupported profile'} ${next['support_issues'] ?? ''}';
      });
    } catch (exception) {
      setState(() {
        result = null;
        error = '$exception';
      });
    }
  }

  Widget numeric(String key, String label, String suffix) => TextField(
    controller: controllers[key],
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      suffixText: suffix,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    onSubmitted: (_) => runModels(),
  );

  Widget choice(String key, String label, Map<int, String> options) =>
      DropdownButtonFormField<int>(
        initialValue: categories[key],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final entry in options.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) => setState(() => categories[key] = value!),
      );

  Widget panel(Widget child) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE0E8E5)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A172B37),
          blurRadius: 22,
          offset: Offset(0, 9),
        ),
      ],
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 980;
    final form = panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'PROFILE INPUTS',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
              color: teal,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Change one value, then run both methods.',
            style: TextStyle(color: Color(0xFF587078)),
          ),
          const SizedBox(height: 20),
          numeric('age', 'Age', 'years'),
          const SizedBox(height: 12),
          choice('sex_nhanes', 'Survey sex category', {1: 'Male', 2: 'Female'}),
          const SizedBox(height: 12),
          numeric('bmi', 'BMI', ''),
          const SizedBox(height: 12),
          numeric('sleep_hours', 'Usual workday sleep', 'h'),
          const SizedBox(height: 12),
          numeric(
            'moderate_recreation_min_week',
            'Moderate recreation',
            'min/wk',
          ),
          const SizedBox(height: 12),
          numeric(
            'vigorous_recreation_min_week',
            'Vigorous recreation',
            'min/wk',
          ),
          const SizedBox(height: 12),
          numeric('sedentary_min_day', 'Awake sitting', 'min/day'),
          const SizedBox(height: 12),
          choice('smoking_status', 'Smoking', {
            0: 'Never',
            1: 'Former',
            2: 'Current',
          }),
          const SizedBox(height: 12),
          choice('diabetes_diagnosed', 'Diagnosed diabetes', {
            0: 'No',
            1: 'Yes',
          }),
          const SizedBox(height: 12),
          choice('hypertension_diagnosed', 'Diagnosed hypertension', {
            0: 'No',
            1: 'Yes',
          }),
          const SizedBox(height: 12),
          choice('general_health', 'Self-rated health', {
            1: 'Excellent',
            2: 'Very good',
            3: 'Good',
            4: 'Fair',
            5: 'Poor',
          }),
          const SizedBox(height: 18),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show unvalidated ages 80–110'),
            subtitle: const Text(
              'Uses Cox age coefficients beyond training support',
            ),
            value: includeExtrapolation,
            onChanged: (value) => setState(() => includeExtrapolation = value),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: lab == null ? null : runModels,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Run models'),
          ),
        ],
      ),
    );
    final output = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          panel(Text(error!, style: const TextStyle(color: Color(0xFFB4473F)))),
        if (lab == null && error == null)
          const Center(child: CircularProgressIndicator()),
        if (result?['status'] == 'available') ...[
          _summary(result!),
          const SizedBox(height: 18),
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'IF INPUTS STAY FIXED',
                  style: TextStyle(
                    color: teal,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Exploratory survival projection',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Wrap(
                  spacing: 22,
                  runSpacing: 8,
                  children: [
                    _Legend(color: teal, label: 'Age updated yearly'),
                    _Legend(color: violet, label: 'Age updated every 5 years'),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 330,
                  child: CustomPaint(
                    painter: _ProjectionPainter(
                      result!['annual'] as Map,
                      result!['five_year'] as Map,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Faded segments use assessment ages above 79. The 50% line shows a median crossing in the mathematical simulation, not an individual death age.',
                  style: TextStyle(color: Color(0xFF587078), height: 1.4),
                ),
                _yearTable(result!),
              ],
            ),
          ),
          const SizedBox(height: 18),
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How these curves were made',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Yearly: multiply one-year Cox survival estimates after raising age by one each year. Five-year: multiply one five-year Cox estimate per block, keeping the starting age fixed inside that block. All other inputs stay fixed. Neither recurrence was trained or validated as a longitudinal lifespan model.',
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Neural reference and model versions'),
                  children: [
                    const Text(
                      'Neural reference: age 55, male survey category, BMI 27, seven hours sleep, 150 moderate and zero vigorous recreational minutes per week, 360 sitting minutes per day, never smoker, no reported diabetes or hypertension, self-rated health good.',
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      'Neural: ${(result!['neural_hazard'] as Map)['model_version']}',
                    ),
                    SelectableText(
                      'Cox: ${(result!['current_cox'] as Map)['model_version']}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'LifeTwin / Projection Lab',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: paper,
        surfaceTintColor: paper,
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1360),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 72),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Test the model, not the story.',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Local neural hazard + two Cox age-stepping experiments. Inputs stay in this browser.',
                    style: TextStyle(color: Color(0xFF587078), fontSize: 16),
                  ),
                  const SizedBox(height: 26),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 340, child: form),
                        const SizedBox(width: 22),
                        Expanded(child: output),
                      ],
                    )
                  else
                    Column(
                      children: [form, const SizedBox(height: 20), output],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(Map<String, dynamic> data) {
    final neural = data['neural_hazard'] as Map;
    final current = data['current_cox'] as Map;
    final annual = data['annual'] as Map;
    final fiveYear = data['five_year'] as Map;
    String crossing(Map value) {
      final age = value['median_crossing_age'] as num?;
      if (age == null) return 'Not reached';
      return '${age.toStringAsFixed(1)}${value['median_crossing_extrapolated'] == true ? '*' : ''}';
    }

    return Column(
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _Metric(
              label: 'NEURAL RELATIVE HAZARD',
              value:
                  '${(neural['relative_hazard_vs_reference'] as num).toStringAsFixed(2)}×',
              detail:
                  'Versus fixed age-55 reference profile. Not a probability.',
            ),
            _Metric(
              label: 'CURRENT 5-YEAR COX',
              value:
                  '${(current['survival_percent_by_year'] as Map)['5'].toStringAsFixed(1)}%',
              detail:
                  'Supported snapshot horizon; separate model from neural hazard.',
            ),
            _Metric(
              label: '50% CROSSING · YEARLY',
              value: crossing(annual),
              detail:
                  '* In extrapolated region; not validated life expectancy.',
            ),
            _Metric(
              label: '50% CROSSING · 5-YEAR',
              value: crossing(fiveYear),
              detail:
                  '* In extrapolated region; not validated life expectancy.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _yearTable(Map<String, dynamic> data) {
    final yearly = <int, Map>{
      for (final point in (data['annual']['points'] as List).cast<Map>())
        point['age'] as int: point,
    };
    final blocks = <int, Map>{
      for (final point in (data['five_year']['points'] as List).cast<Map>())
        point['age'] as int: point,
    };
    final ages = {...yearly.keys, ...blocks.keys}.toList()..sort();
    String percent(Map? point) => point == null
        ? '—'
        : '${(point['survival_percent'] as num).toStringAsFixed(2)}%${point['extrapolated'] == true ? '*' : ''}';
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Inspect values for each age'),
      children: [
        SizedBox(
          height: 275,
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Age')),
                  DataColumn(label: Text('Yearly')),
                  DataColumn(label: Text('5-year blocks')),
                ],
                rows: [
                  for (final age in ages)
                    DataRow(
                      cells: [
                        DataCell(Text('$age')),
                        DataCell(Text(percent(yearly[age]))),
                        DataCell(Text(percent(blocks[age]))),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.detail,
  });
  final String label;
  final String value;
  final String detail;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 226,
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE0E8E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: teal,
              fontSize: 11,
              letterSpacing: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            value,
            style: const TextStyle(fontSize: 31, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF587078),
              height: 1.3,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 22, height: 4, color: color),
      const SizedBox(width: 7),
      Text(label),
    ],
  );
}

class _ProjectionPainter extends CustomPainter {
  _ProjectionPainter(this.annual, this.fiveYear);
  final Map annual;
  final Map fiveYear;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(
      42,
      12,
      math.max(1, size.width - 60),
      math.max(1, size.height - 50),
    );
    final annualPoints = (annual['points'] as List).cast<Map>();
    final blockPoints = (fiveYear['points'] as List).cast<Map>();
    final firstAge = annualPoints.first['age'] as int;
    final lastAge = math.max(
      annualPoints.last['age'] as int,
      blockPoints.last['age'] as int,
    );
    double x(num age) =>
        bounds.left +
        bounds.width * (age - firstAge) / math.max(1, lastAge - firstAge);
    double y(num percent) => bounds.bottom - bounds.height * percent / 100;
    final grid = Paint()
      ..color = const Color(0xFFE4ECE9)
      ..strokeWidth = 1;
    final labelStyle = const TextStyle(fontSize: 11, color: Color(0xFF60747B));
    void label(String value, Offset position) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, position);
    }

    for (final percent in [0, 25, 50, 75, 100]) {
      canvas.drawLine(
        Offset(bounds.left, y(percent)),
        Offset(bounds.right, y(percent)),
        grid,
      );
      label('$percent%', Offset(0, y(percent) - 7));
    }
    for (var age = ((firstAge + 9) ~/ 10) * 10; age <= lastAge; age += 10) {
      canvas.drawLine(
        Offset(x(age), bounds.top),
        Offset(x(age), bounds.bottom),
        grid,
      );
      label('$age', Offset(x(age) - 8, bounds.bottom + 9));
    }
    if (firstAge < 80 && lastAge > 79) {
      final mark = Paint()
        ..color = const Color(0xFFC79A61)
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(x(80), bounds.top),
        Offset(x(80), bounds.bottom),
        mark,
      );
      label(
        'Age 80 · assessment limit',
        Offset(math.min(x(80) + 5, bounds.right - 145), 0),
      );
    }
    void curve(List<Map> points, Color color) {
      for (var i = 1; i < points.length; i++) {
        final a = Offset(
          x(points[i - 1]['age'] as num),
          y(points[i - 1]['survival_percent'] as num),
        );
        final b = Offset(
          x(points[i]['age'] as num),
          y(points[i]['survival_percent'] as num),
        );
        final extrapolated = points[i]['extrapolated'] == true;
        final paint = Paint()
          ..color = extrapolated ? color.withValues(alpha: .43) : color
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(a, b, paint);
      }
    }

    curve(blockPoints, violet);
    curve(annualPoints, teal);
  }

  @override
  bool shouldRepaint(covariant _ProjectionPainter oldDelegate) => true;
}
