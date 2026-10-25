// A store file that parses but holds a part of the wrong shape (a broken or older write)
// must not stop LifeTwin opening: the unreadable part is dropped and the rest is kept.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifesim/twin/twin_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = {'age': 70, 'sex': 'female', 'height_cm': 165, 'weight_kg': 70};

  Future<TwinRepository> openWith(Map<String, Object?> doc) =>
      TwinRepository.open(backend: MemoryBackend()..text = jsonEncode({'version': 1, ...doc}));

  final broken = <String, Map<String, Object?>>{
    'profile is a list': {'profile': [1]},
    'profile_meta is a list': {'profile': profile, 'profile_meta': [1]},
    'a history entry without a time': {
      'profile': profile,
      'history': [
        {'id': 'h1'},
      ],
    },
    'history is a map': {'profile': profile, 'history': {'a': 1}},
    'a check-in without a date': {
      'profile': profile,
      'checkins': [
        {'kind': 'daily'},
      ],
    },
    'first_joined is a number': {'profile': profile, 'first_joined': 5},
    'first_joined is not a date': {'profile': profile, 'first_joined': 'soon'},
    'ideas is a string': {'profile': profile, 'ideas': 'x'},
    'twin is a list': {'profile': profile, 'twin': [1]},
    'outside_ai_consent is a list': {'profile': profile, 'outside_ai_consent': [true]},
    'a day log without a date': {
      'profile': profile,
      'daily_logs': [
        {'sleep_hours': 7},
      ],
    },
    'a health score point without a time': {
      'profile': profile,
      'health_score': [
        {'score': 3},
      ],
    },
  };

  for (final e in broken.entries) {
    test('opens when ${e.key}', () async {
      final repo = await openWith(e.value);
      final s = repo.store;
      // Everything the app reads at start-up still reads.
      s.profile;
      s.profileMeta;
      s.checkins;
      s.dayLogs;
      s.historyEntries;
      s.healthScorePoints;
      s.twin;
      s.ideasState;
      s.outsideAiConsent;
      s.outsideAiProvider;
      s.firstJoined;
      for (final c in s.checkins) {
        DateTime.parse(c.date);
      }
      for (final d in s.dayLogs) {
        DateTime.parse(d.date);
      }
      if (e.value['profile'] == profile) expect(s.profile, profile, reason: 'the readable parts are kept');
    });
  }

  test('a readable entry next to an unreadable one is kept', () async {
    final repo = await openWith({
      'profile': profile,
      'first_joined': '2026-10-01',
      'history': [
        {'id': 'bad'},
      ],
    });
    expect(repo.store.firstJoined, '2026-10-01');
    expect(repo.store.profile, profile);
  });
}
