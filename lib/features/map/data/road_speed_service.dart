import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ccs_app/core/config/app_config.dart';

abstract class RoadSpeedTransport {
  Future<Map<String, dynamic>> lookup(List<Map<String, Object?>> points);
  void cancel();
}

/// Only the authenticated CCS backend receives the trace from the app.
class BackendRoadSpeedTransport implements RoadSpeedTransport {
  HttpClient? _client;
  int _generation = 0;
  @override
  void cancel() {
    _generation++;
    _client?.close(force: true);
    _client = null;
  }

  @override
  Future<Map<String, dynamic>> lookup(List<Map<String, Object?>> points) async {
    final generation = _generation;
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken().timeout(const Duration(seconds: 5));
    if (token == null ||
        generation != _generation ||
        FirebaseAuth.instance.currentUser?.uid != user?.uid) {
      throw StateError('Session unavailable');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    _client = client;
    final timer = Timer(
      const Duration(seconds: 6),
      () => client.close(force: true),
    );
    try {
      final request = await client.postUrl(
        Uri.parse('$telegramAuthBaseUrl/api/road-speed-limit'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(jsonEncode({'points': points}));
      final response = await request.close();
      if (response.statusCode != 200) {
        return {
          'status': 'unavailable',
          'retryAfterSeconds': response.statusCode == 429 ? 30 : 60,
        };
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 16384) throw StateError('Response too large');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Invalid response');
      }
      return decoded;
    } finally {
      timer.cancel();
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }
}
