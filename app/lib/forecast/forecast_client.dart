import 'dart:convert';

import 'package:http/http.dart' as http;

import '../voice/api_base.dart';

/// The fields POST /api/predict accepts (contracts/prediction.request.schema.json).
const forecastProfileFields = {
  'age',
  'sex',
  'height_cm',
  'weight_kg',
  'sleep_hours',
  'exercise_minutes_weekly',
  'smoking_status',
  'alcohol_drinks_weekly',
  'diabetes',
  'systolic_bp',
  'diastolic_bp',
};

/// One server forecast (contracts/prediction.schema.json). Survival values are 0 to 1.
class Forecast {
  const Forecast({
    required this.supported,
    required this.survival,
    required this.maxHorizonYears,
    required this.modelVersion,
    this.filledIn = const [],
    this.reason,
    this.limitations = const [],
    this.curve = const [],
  });

  final bool supported;

  /// Years (1, 3, 5) to the share of similar people still living then.
  final Map<int, double> survival;
  final int maxHorizonYears;
  final String modelVersion;

  /// Plain words for answers the model filled in with typical survey values.
  final List<String> filledIn;

  /// Why there is no forecast, when [supported] is false.
  final String? reason;
  final List<String> limitations;

  /// The model's monthly curve up to [maxHorizonYears], as returned.
  final List<({double years, double survival})> curve;

  /// "about 93": out of 100 people, at the longest supported horizon.
  int outOf100(int years) => (100 * (survival[years] ?? 0)).round();

  static Forecast parse(Object? json) {
    if (json is! Map || json['status'] is! String || json['model_version'] is! String) {
      throw const ForecastFailure('unexpected response');
    }
    final supported = json['status'] == 'supported';
    final survival = <int, double>{
      for (final p in (json['survival'] as List? ?? const []))
        if (p is Map && p['years'] is num && p['survival'] is num)
          (p['years'] as num).toInt(): (p['survival'] as num).toDouble(),
    };
    final max = (json['max_horizon_years'] as num?)?.toInt() ?? 5;
    if (supported && !survival.containsKey(max)) throw const ForecastFailure('missing horizon');
    return Forecast(
      supported: supported,
      survival: survival,
      maxHorizonYears: max,
      modelVersion: json['model_version'] as String,
      filledIn: [
        for (final f in (json['filled_in'] as List? ?? const []))
          if (f is Map && f['label'] is String) f['label'] as String,
      ],
      reason: json['reason'] as String?,
      limitations: [
        for (final l in (json['limitations'] as List? ?? const []))
          if (l is String) l,
      ],
      curve: [
        for (final p in (json['curve'] as List? ?? const []))
          if (p is Map && p['years'] is num && p['survival'] is num)
            (years: (p['years'] as num).toDouble(), survival: (p['survival'] as num).toDouble()),
      ],
    );
  }
}

abstract class ForecastClient {
  /// Throws [ForecastFailure] when there is no usable answer.
  Future<Forecast> predict(Map<String, dynamic> confirmedProfile);
}

class ForecastFailure implements Exception {
  const ForecastFailure(this.message, {this.plain, this.modelMissing = false});
  final String message;

  /// The server has no model installed yet (HTTP 501): "still learning".
  final bool modelMissing;

  /// A message from the server that is safe and useful to show.
  final String? plain;
  @override
  String toString() => 'ForecastFailure($message)';
}

/// Calls POST /api/predict with the confirmed answers only.
class HttpForecastClient implements ForecastClient {
  HttpForecastClient({required this.base, http.Client? client}) : _client = client ?? http.Client();

  final ApiBase base;
  final http.Client _client;

  @override
  Future<Forecast> predict(Map<String, dynamic> confirmedProfile) async {
    final body = {
      for (final e in confirmedProfile.entries)
        if (forecastProfileFields.contains(e.key) && e.value != null) e.key: e.value,
    };
    try {
      final url = await base.url();
      final r = await _client
          .post(
            Uri.parse('$url/api/predict'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 501) {
        throw const ForecastFailure(
          'model not installed',
          plain: 'The forecast is not set up on this server yet.',
          modelMissing: true,
        );
      }
      if (r.statusCode != 200) throw ForecastFailure('HTTP ${r.statusCode}', plain: _reason(r.bodyBytes));
      return Forecast.parse(jsonDecode(utf8.decode(r.bodyBytes)));
    } on ForecastFailure {
      rethrow;
    } catch (e) {
      base.forget();
      throw ForecastFailure('$e');
    }
  }

  static String? _reason(List<int> body) {
    try {
      final json = jsonDecode(utf8.decode(body));
      final message = json is Map ? json['message'] : null;
      return message is String && message.trim().isNotEmpty ? message.trim() : null;
    } catch (_) {
      return null;
    }
  }
}
