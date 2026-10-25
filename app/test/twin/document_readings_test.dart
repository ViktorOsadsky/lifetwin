import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/documents/document_extract.dart';
import 'package:lifesim/documents/document_upload.dart';
import 'package:lifesim/twin/checkin_applier.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';

const profile = {
  'age': 45,
  'sex': 'male',
  'height_cm': 175.0,
  'weight_kg': 76.5625,
  'sleep_hours': 7,
  'smoking_status': 'never',
  'diabetes': false,
  'hypertension_diagnosed': false,
  'general_health': 2,
  'vigorous_recreation_min_week': 60,
  'moderate_recreation_min_week': 120,
  'sedentary_min_day': 360,
  'alcohol_drinks_weekly': 2,
};

DocumentCandidate cand(
  String field,
  Object value, {
  String? unit,
  DateTime? date,
}) => DocumentCandidate(
  field: field,
  value: value,
  unit: unit,
  date: date,
  modelInput: false,
  sourceText: 'line',
  page: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwinModelService model;
  setUpAll(() async => model = await TwinModelService.load());

  late TwinRepository repo;
  setUp(() async {
    repo = TwinRepository(
      model: model,
      store: await TwinStore.open(MemoryBackend()),
      clock: () => DateTime(2026, 10, 26, 9),
    );
    await repo.saveConversationProfile(profile);
  });

  final visit = DateTime(2026, 9, 14);

  test(
    'each field is recorded with its unit, label and the document date',
    () async {
      await repo.recordDocumentReadings([
        cand('blood_pressure', '138/86', unit: 'mmHg', date: visit),
        cand('hba1c', 6.1, unit: '%', date: visit),
        cand('ldl_cholesterol', 131, unit: 'mg/dL', date: visit),
      ]);
      final items = [for (final e in repo.readings()) ...e.items];
      expect(
        {
          for (final i in items)
            i.field: (i.value, i.unit, i.text, i.date, i.source),
        },
        {
          'systolic_bp': (
            138,
            'mmHg',
            '138 mmHg',
            '2026-09-14',
            HistorySource.document,
          ),
          'diastolic_bp': (
            86,
            'mmHg',
            '86 mmHg',
            '2026-09-14',
            HistorySource.document,
          ),
          'hba1c': (6.1, '%', '6.1 %', '2026-09-14', HistorySource.document),
          'ldl_cholesterol': (
            131,
            'mg/dL',
            '131 mg/dL',
            '2026-09-14',
            HistorySource.document,
          ),
        },
      );
      expect(items.firstWhere((i) => i.field == 'hba1c').label, 'A1c');
      expect(
        repo.readings().every(
          (e) => e.kind == HistoryKind.reading && !e.dateNotOnDocument,
        ),
        isTrue,
      );
    },
  );

  test('an undated document uses the confirmation date and says so', () async {
    await repo.recordDocumentReadings([cand('hba1c', 5.8, unit: '%')]);
    final e = repo.readings().single;
    expect(e.items.single.date, isNull);
    expect(e.date, '2026-10-26');
    expect(e.dateNotOnDocument, isTrue);
  });

  test('an implausible value is rejected, not clamped', () async {
    await repo.recordDocumentReadings([
      cand('hba1c', 2.9, unit: '%'),
      cand('hba1c', 20.5, unit: '%'),
      cand('ldl_cholesterol', 19, unit: 'mg/dL'),
      cand('ldl_cholesterol', 401, unit: 'mg/dL'),
      cand('blood_pressure', '20/10', unit: 'mmHg'),
    ]);
    expect(repo.readings(), isEmpty);
    expect(readingSchema['hba1c']!(3) && readingSchema['hba1c']!(20), isTrue);
    expect(
      readingSchema['ldl_cholesterol']!(20) &&
          readingSchema['ldl_cholesterol']!(400),
      isTrue,
    );
    expect(
      profileSchema.containsKey('hba1c') ||
          profileSchema.containsKey('ldl_cholesterol'),
      isFalse,
    );
  });

  test('Skip records nothing', () async {
    final c = DocumentConfirmation([cand('hba1c', 6.1, unit: '%', date: visit)])
      ..answerAboutYou(true)
      ..answer(false);
    await repo.recordDocumentReadings(c.result.notes);
    expect(repo.readings(), isEmpty);
    expect(repo.history().where((e) => e.kind == HistoryKind.reading), isEmpty);
  });

  test('a kept reading appears in history()', () async {
    final c =
        DocumentConfirmation([
            cand('ldl_cholesterol', 131, unit: 'mg/dL', date: visit),
          ])
          ..answerAboutYou(true)
          ..answer(true);
    await repo.recordDocumentReadings(c.result.notes);
    final e = repo.history().firstWhere((e) => e.kind == HistoryKind.reading);
    expect(e.source, HistorySource.document);
    expect(e.items.single.field, 'ldl_cholesterol');
    expect(repo.readings().single.id, e.id);
  });

  test('readings never feed the model, forecast or profile', () async {
    final before = repo.assess().raw;
    final profileBefore = Map.of(repo.profile);
    await repo.recordDocumentReadings([
      cand('hba1c', 9.5, unit: '%', date: visit),
      cand('ldl_cholesterol', 190, unit: 'mg/dL', date: visit),
    ]);
    expect(repo.assess().raw, before);
    expect(repo.profile, profileBefore);
    expect(repo.readings(), isNotEmpty);
  });

  test('Delete my data clears the readings', () async {
    await repo.recordDocumentReadings([
      cand('hba1c', 6.1, unit: '%', date: visit),
    ]);
    await repo.deleteMyData();
    expect(repo.readings(), isEmpty);
    expect(repo.history(), isEmpty);
  });
}
