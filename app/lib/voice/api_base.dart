import 'dart:async';

import 'package:http/http.dart' as http;

import 'backend_http_client.dart';
import 'backend_config.dart';

/// One address, or several separated by commas, tried in parallel.
String get apiBaseUrl => BackendConfig.current.apiUrl;

/// Finds which server address answers. A Mac advertises its `.local` name on
/// every network it is on (USB cable, Wi-Fi), so a phone that can reach only one
/// of them can wait a long time on the others. Checking all candidates at once
/// against `/health` (no personal data) and keeping the first that answers
/// avoids that wait.
class ApiBase {
  ApiBase([String? urls, http.Client? client])
    : candidates = [
        for (final u in (urls ?? apiBaseUrl).split(','))
          if (u.trim().isNotEmpty) u.trim(),
      ],
      _client = client ?? BackendHttpClient();

  final List<String> candidates;
  final http.Client _client;
  Future<String>? _found;

  /// The address to use. With a single candidate there is nothing to check.
  Future<String> url() {
    if (candidates.length == 1) return Future.value(candidates.single);
    return _found ??= _race().then(
      (u) => u,
      onError: (Object e) {
        _found = null; // try again next time
        throw e;
      },
    );
  }

  /// Call after a request fails, so the next one checks the addresses again.
  void forget() => _found = null;

  Future<String> _race() {
    final done = Completer<String>();
    var left = candidates.length;
    for (final c in candidates) {
      _client
          .get(Uri.parse('$c/health'))
          .timeout(const Duration(seconds: 4))
          .then((r) {
            if (r.statusCode == 200 && !done.isCompleted) done.complete(c);
          })
          .catchError((_) {})
          .whenComplete(() {
            if (--left == 0 && !done.isCompleted) done.completeError(Exception('no server answered'));
          });
    }
    return done.future;
  }
}
