// Document readings and diagnoses are long-term context (owner ruling 2026-10-25): kept
// on the phone with no expiry until Delete my data, sent to the coach and to the ideas
// request only with memory consent, and never a model input.
import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/documents/document_extract.dart';
import 'package:lifesim/experiment/recommendations.dart';
import 'package:lifesim/twin/twin_model.dart';
import 'package:lifesim/twin/twin_repository.dart';
import 'package:lifesim/wellness/coach_context.dart';

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

DocumentCandidate cand(String field, Object value, {String? unit, DateTime? date}) => DocumentCandidate(
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

  late MemoryBackend backend;
  late TwinRepository repo;
  var clock = DateTime(2026, 10, 26, 9);

  Future<TwinRepository> open() async =>
      TwinRepository(model: model, store: await TwinStore.open(backend), clock: () => clock);

  setUp(() async {
    clock = DateTime(2026, 10, 26, 9);
    backend = MemoryBackend();
    repo = await open();
    await repo.saveConversationProfile(profile);
    await repo.recordImport({'diabetes': true}, source: HistorySource.document);
    await repo.recordDocumentReadings([
      cand('blood_pressure', '138/86', unit: 'mmHg', date: DateTime(2026, 9, 14)),
      cand('hba1c', 6.1, unit: '%', date: DateTime(2026, 9, 14)),
      cand('ldl_cholesterol', 131, unit: 'mg/dL', date: DateTime(2026, 9, 14)),
    ]);
  });

  Map<String, dynamic> shown(Map<String, dynamic> ctx) => ctx['document_context'] as Map<String, dynamic>;

  test('with memory consent the coach context carries readings with date and unit, and diagnoses', () async {
    await repo.applyMemoryConsent(true);
    final doc = shown(coachContext(repo, now: clock));
    expect(doc['diagnoses'], ['diabetes']);
    final readings = (doc['readings'] as List).cast<Map<String, dynamic>>();
    expect({for (final r in readings) r['field']: (r['value'], r['unit'], r['date'], r['source'])}, {
      'systolic_bp': (138, 'mmHg', '2026-09-14', 'document'),
      'diastolic_bp': (86, 'mmHg', '2026-09-14', 'document'),
      'a1c': (6.1, '%', '2026-09-14', 'document'),
      'ldl': (131.0, 'mg/dL', '2026-09-14', 'document'),
    });
  });

  test('without memory consent nothing from the documents is sent as context', () async {
    expect(coachContext(repo, now: clock).containsKey('document_context'), isFalse);
    expect(recommendationsRequestBody(repo).containsKey('document_context'), isFalse);
  });

  test('the ideas request carries the same context, only with memory consent', () async {
    await repo.applyMemoryConsent(true);
    final body = recommendationsRequestBody(repo, localDate: '2026-10-26');
    expect(shown(body)['diagnoses'], ['diabetes']);
    expect(shown(body)['readings'], isNotEmpty);
    // It never becomes a model input.
    expect((body['profile'] as Map).containsKey('hba1c'), isFalse);
    expect((body['profile'] as Map).containsKey('ldl'), isFalse);
  });

  test('it is kept across a restart with no expiry, years later', () async {
    await repo.applyMemoryConsent(true);
    clock = DateTime(2031, 1, 5, 9);
    final reopened = await open();
    final doc = shown(coachContext(reopened, now: clock));
    expect(doc['diagnoses'], ['diabetes']);
    expect((doc['readings'] as List).length, 4);
  });

  test('Delete my data clears it', () async {
    await repo.applyMemoryConsent(true);
    await repo.deleteMyData();
    expect(backend.text, isNull);
    expect(repo.readings(), isEmpty);
    final reopened = await open();
    await reopened.applyMemoryConsent(true);
    expect(coachContext(reopened, now: clock).containsKey('document_context'), isFalse);
  });
}
